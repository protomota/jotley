import AppKit
import Foundation
import AVFoundation
import AudioToolbox
import Combine

@MainActor
public final class ProcessTapRecorder: ObservableObject {
    @Published public private(set) var recording = false
    @Published public private(set) var paused = false
    @Published public private(set) var starting = false
    @Published public private(set) var finishing = false
    public var isBusy: Bool { starting || finishing }
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var elapsed: Double = 0
    private let queue = DispatchQueue(label: "jotley.local.capture")
    private var tap: ProcessTap?
    private var engine: AVAudioEngine?
    private var writer: DurableAudioWriter?
    private var root: URL?
    private var noteID: UUID?
    private var systemAudio = false
    private var timer: Timer?
    private var startedAt: Date?
    private var previousElapsed = 0.0

    private var liveSpeech: LiveSpeechSession?
    private var speechWarning: String?
    public var hasOnlySpeechWarning: Bool { errorMessage != nil && errorMessage == speechWarning }
    @Published public private(set) var transcription = ""
    @Published public private(set) var currentAudioLevel: Float = 0
    public var isRecording: Bool { recording }
    public var isRecordingNewNote: Bool { recording }
    public var elapsedTime: Double { elapsed }
    public var icon: NSImage? { NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Transcribing") }
    public var existingTranscript = ""
    public private(set) var transcriptTimeOffset: TimeInterval = 0
    public var latestTranscriptDelta: String {
        #if !SWIFT_PACKAGE
        return transcriptValue.tentative
        #else
        return transcription
        #endif
    }
    public var accumulatedTranscript: String {
        #if !SWIFT_PACKAGE
        return [existingTranscript, transcriptValue.text].filter { !$0.isEmpty }.joined(separator: " ")
        #else
        return transcription
        #endif
    }
    public var onTranscript: ((LocalTranscript) -> Void)?
    public var speechLocale = Locale(identifier: "en-US")
    #if DEBUG && !SWIFT_PACKAGE
    // Exercise the real start route without requesting microphone access in UI tests.
    var simulatedStart: (@MainActor (URL, UUID, Bool) async throws -> Void)?
    private var simulatedSession = false
    func beginSimulatedLiveTranscription(_ snapshot: LocalTranscript) {
        simulatedSession = true; recording = true; paused = false; elapsed = 32; currentAudioLevel = 0.12
        transcriptTimeOffset = existingUtterances.compactMap(\.end).max() ?? 0
        accept(snapshot)
    }
    func publishSimulatedLiveTranscript(_ snapshot: LocalTranscript) {
        guard simulatedSession, recording else { return }
        accept(snapshot)
    }
    #endif
    public init() {}
    private func accept(_ value: LocalTranscript) {
        transcription = value.displayText
        #if !SWIFT_PACKAGE
        transcriptValue = value
        #endif
        onTranscript?(value)
    }

    public func start(root: URL, noteID: UUID, systemAudio: Bool) async throws {
        guard !recording, !isBusy else { throw LocalError.message("A transcription session is already in progress.") }
        starting = true
        defer { starting = false }
        #if DEBUG && !SWIFT_PACKAGE
        if let simulatedStart { try await simulatedStart(root, noteID, systemAudio); return }
        #endif
        guard await Self.authorizeMicrophone(status: AVCaptureDevice.authorizationStatus(for: .audio), request: {
            await AVCaptureDevice.requestAccess(for: .audio)
        }) else {
            throw LocalError.message("Microphone access was denied. Enable it in System Settings → Privacy & Security → Microphone.")
        }
        self.root = root; self.noteID = noteID; self.systemAudio = systemAudio
        transcriptTimeOffset = try DurableAudioWriter.recordedDuration(in: root.appendingPathComponent("Recordings/\(noteID.uuidString)"))
        #if !SWIFT_PACKAGE
        // Synced notes may have existing text/timestamps without audio on this Mac.
        transcriptTimeOffset = max(transcriptTimeOffset, existingUtterances.compactMap(\.end).max() ?? 0)
        #endif
        elapsed = 0; previousElapsed = 0; errorMessage = nil; speechWarning = nil
        accept(LocalTranscript())
        do {
            liveSpeech = try await LiveSpeechSession.start(locale: speechLocale) { [weak self] value in
                await MainActor.run { self?.accept(value) }
            }
        } catch {
            speechWarning = "Live transcription unavailable: \(error.localizedDescription) Captured audio remains available locally."
            errorMessage = speechWarning
        }
        do { try startSegment() } catch {
            await liveSpeech?.cancel(); liveSpeech = nil; throw error
        }
        recording = true; paused = false
        NotificationCenter.default.post(name: .processTapRecordingStateChanged, object: self)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.startedAt, !self.paused else { return }
                self.elapsed = self.previousElapsed + Date().timeIntervalSince(started)
            }
        }
    }
    // macOS owns the grant. Never cache it in preferences or request it again
    // after a grant/denial; re-read the system state when starting capture.
    static func authorizeMicrophone(status: AVAuthorizationStatus, request: () async -> Bool) async -> Bool {
        switch status {
        case .authorized: return true
        case .notDetermined: return await request()
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
    private func startSegment() throws {
        guard let root, let noteID else { throw LocalError.message("No transcription session.") }
        let directory = root.appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(noteID.uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            if systemAudio {
                let tap = ProcessTap()
                self.tap = tap
                tap.activate()
                guard tap.errorMessage == nil, var description = tap.aggregateDeviceStreamDescription,
                      let format = AVAudioFormat(streamDescription: &description) else {
                    throw LocalError.message(tap.errorMessage ?? "System audio capture is unavailable.")
                }
                let writer = try DurableAudioWriter(directory: directory, noteID: noteID, sampleRate: format.sampleRate)
                self.writer = writer
                let live = liveSpeech
                try tap.run(on: queue, ioBlock: { [weak self] _, input, _, _, _ in
                    do {
                        let data = try Self.mix(input, format: format)
                        try writer.append(data)
                        live?.append(data, sampleRate: format.sampleRate)
                        let peak = data.withUnsafeBytes { bytes in bytes.bindMemory(to: Float.self).reduce(Float(0)) { max($0, abs($1)) } }
                        Task { @MainActor [weak self] in self?.currentAudioLevel = peak }
                    } catch {
                        Task { @MainActor [weak self] in self?.captureFailed(error) }
                    }
                }, invalidationHandler: { _ in })
            } else {
                let engine = AVAudioEngine()
                self.engine = engine
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else {
                    throw LocalError.message("No microphone input is available.")
                }
                let writer = try DurableAudioWriter(directory: directory, noteID: noteID, sampleRate: format.sampleRate)
                self.writer = writer
                let live = liveSpeech
                input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                    do {
                        let data = try Self.mix(UnsafePointer(buffer.audioBufferList), format: format)
                        try writer.append(data)
                        live?.append(data, sampleRate: format.sampleRate)
                        let peak = data.withUnsafeBytes { bytes in bytes.bindMemory(to: Float.self).reduce(Float(0)) { max($0, abs($1)) } }
                        Task { @MainActor [weak self] in self?.currentAudioLevel = peak }
                    } catch {
                        Task { @MainActor [weak self] in self?.captureFailed(error) }
                    }
                }
                try engine.start()
            }
            startedAt = Date()
        } catch {
            stopCapture(); throw error
        }
    }
    private func captureFailed(_ error: Error) {
        guard recording else { return }
        errorMessage = "Capture stopped: \(error.localizedDescription). Captured audio was preserved."
        // Stop input immediately, but retain the active session until its owner
        // finalizes speech and releases recording ownership. Marking it idle here
        // would allow a new recording to replace state before the queued stop runs.
        _ = stopCapture()
        Task {
            #if !SWIFT_PACKAGE
            if let owner = JotleyAppDelegate.shared?.recordingNotesViewModel { await owner.stopRecording() }
            else { _ = await stop() }
            #else
            _ = await stop()
            #endif
        }
    }
    public func togglePause() throws {
        guard recording, !isBusy else { return }
        #if DEBUG && !SWIFT_PACKAGE
        if simulatedSession { paused.toggle(); return }
        #endif
        if paused { try startSegment(); paused = false }
        else {
            let captureError = stopCapture()
            previousElapsed = elapsed; paused = true
            if let captureError { throw captureError }
        }
    }
    @discardableResult
    private func stopCapture() -> Error? {
        if let startedAt { elapsed = previousElapsed + Date().timeIntervalSince(startedAt) }
        startedAt = nil
        tap?.invalidate(); tap = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        queue.sync {} // All capture callbacks finish before closing the durable file.
        var captureError: Error?
        do { try writer?.close() }
        catch {
            captureError = error
            errorMessage = "Audio could not be finalized: \(error.localizedDescription). Raw capture was retained."
        }
        writer = nil
        return captureError
    }
    public func stopCaptureSession() {
        #if DEBUG && !SWIFT_PACKAGE
        simulatedSession = false
        #endif
        stopCapture(); timer?.invalidate(); timer = nil
        recording = false; paused = false
        NotificationCenter.default.post(name: .processTapRecordingStateChanged, object: self)
    }

    public func stop() async -> String {
        guard !finishing else { return transcription }
        finishing = true
        defer { finishing = false }
        stopCaptureSession()
        if let live = liveSpeech {
            liveSpeech = nil
            do { accept(try await live.finish()) }
            catch { errorMessage = "Live transcription could not finish: \(error.localizedDescription). Audio is saved for retry." }
        }
        currentAudioLevel = 0
        return transcription
    }
    #if !SWIFT_PACKAGE
    var existingUtterances: [TranscriptUtterance] = []
    var transcriptUtterances: [TranscriptUtterance] {
        return existingUtterances + transcriptValue.utterances.map { TranscriptUtterance(text: $0.text, start: transcriptTimeOffset + $0.start, end: transcriptTimeOffset + $0.end) }
    }
    private var transcriptValue = LocalTranscript()
    #endif

    nonisolated private static func mix(_ input: UnsafePointer<AudioBufferList>, format: AVAudioFormat) throws -> Data {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let bytes: Int
        switch format.commonFormat {
        case .pcmFormatFloat32: bytes = 4
        case .pcmFormatInt16: bytes = 2
        case .pcmFormatInt32: bytes = 4
        default: throw LocalError.message("Unsupported capture sample format.")
        }
        let frameCount = buffers.map { Int($0.mDataByteSize) / (bytes * max(1, Int($0.mNumberChannels))) }.max() ?? 0
        var samples = [Float](repeating: 0, count: frameCount)
        var contributors = [Int](repeating: 0, count: frameCount)
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / (bytes * channels)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    let index = frame * channels + channel
                    switch format.commonFormat {
                    case .pcmFormatFloat32: sum += data.assumingMemoryBound(to: Float.self)[index]
                    case .pcmFormatInt16: sum += Float(data.assumingMemoryBound(to: Int16.self)[index]) / 32768
                    case .pcmFormatInt32: sum += Float(data.assumingMemoryBound(to: Int32.self)[index]) / 2147483648
                    default: break
                    }
                }
                samples[frame] += sum / Float(channels); contributors[frame] += 1
            }
        }
        for frame in 0..<frameCount where contributors[frame] > 0 { samples[frame] /= Float(contributors[frame]) }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
