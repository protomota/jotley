import Foundation
import AVFoundation
import Combine
import CoreData
import Darwin
import UIKit
import ActivityKit
import BackgroundTasks

/// Apple's continued-processing runtime is requested only for an explicit
/// summary action. The OS can still expire it; checkpointed work then resumes
/// in the foreground. No silent audio session is used to keep the app alive.
@MainActor final class SummaryBackgroundRuntime {
    private let identifier = (Bundle.main.bundleIdentifier ?? "com.protomota.jotley") + ".summary." + UUID().uuidString
    private var assertion: UIBackgroundTaskIdentifier = .invalid
    private var continuedTask: BGContinuedProcessingTask?
    private var submission: Task<Void, Never>?
    private var finished = false
    private var currentProgress: LocalSummaryProgress = .preparing
    private var priorSections: Int64 = 0
    private var lastPass = 0
    private var lastTotal = 0
    private let expired: @MainActor () -> Void

    init(expired: @escaping @MainActor () -> Void) { self.expired = expired }
    func begin() {
        assertion = UIApplication.shared.beginBackgroundTask(withName: "Finish Jotley summary") { [weak self] in
            self?.expire() // UIKit delivers this handler on the main actor.
        }
        #if !targetEnvironment(simulator)
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, !self.finished, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false); return
                }
                self.continuedTask = task
                task.progress.totalUnitCount = 2 * Self.unit
                task.progress.completedUnitCount = 0
                task.expirationHandler = { [weak self] in Task { @MainActor in self?.expire() } }
                self.update(self.currentProgress)
                self.endAssertion()
            }
        }
        guard registered else { return } // The short runtime remains available.
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Summarizing your note", subtitle: "Preparing summary")
        request.strategy = .fail // Never queue a second copy of the same inference.
        submission = Task { [weak self] in
            do { try await Self.submit(request) }
            catch { /* Fall back to the short runtime and durable checkpoint. */ }
            guard let self else { return }
            if self.finished { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: self.identifier) }
        }
        #endif
    }
    @concurrent private static func submit(_ request: BGContinuedProcessingTaskRequest) async throws {
        try await BGTaskScheduler.shared.submitTaskRequest(request)
    }
    /// Apple can stop a continued-processing task whose progress stops moving,
    /// so progress also advances while the final summary streams in.
    private var streamedSnapshots: Int64 = 0
    private static let unit: Int64 = 100
    func update(_ progress: LocalSummaryProgress) {
        currentProgress = progress
        guard let task = continuedTask else { return }
        task.updateTitle("Summarizing your note", subtitle: [progress.title, progress.detail].compactMap { $0 }.joined(separator: " · "))
        let unit = Self.unit
        switch progress {
        case .reading(let completed, let total, let pass):
            if pass != lastPass { priorSections += Int64(lastTotal); lastPass = pass }
            lastTotal = total
            task.progress.totalUnitCount = (priorSections + Int64(total)) * unit + 2 * unit
            task.progress.completedUnitCount = (priorSections + Int64(completed)) * unit
        case .writing:
            task.progress.totalUnitCount = (priorSections + Int64(lastTotal)) * unit + 2 * unit
            task.progress.completedUnitCount = (priorSections + Int64(lastTotal)) * unit + min(unit * 2 - 20, streamedSnapshots / 3)
        case .finishing:
            task.progress.completedUnitCount = task.progress.totalUnitCount - 10
        default: break
        }
    }
    func streamed() {
        streamedSnapshots += 1
        if case .writing = currentProgress { update(.writing) }
    }
    private func expire() {
        guard !finished else { return }
        expired()
        finish(success: false)
    }
    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        if success, let task = continuedTask { task.progress.completedUnitCount = task.progress.totalUnitCount }
        continuedTask?.setTaskCompleted(success: success); continuedTask = nil
        submission?.cancel(); submission = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        endAssertion()
    }
    private func endAssertion() {
        if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion); assertion = .invalid }
    }
}

struct MobileSummaryJob: Codable, Sendable {
    let noteID: UUID
    let templateKey: String
    let localeIdentifier: String
    var checkpoint: LocalSummaryCheckpoint
}

/// Apple Intelligence hardware is required; model setup is checked separately.
enum MobileDeviceEligibility {
    static var identifier: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
        #else
        var system = utsname(); uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        #endif
    }
    static var unsupportedReason: String? { JotleyAppleIntelligenceEligibility.unsupportedReason }
}

/// Serialize microphone session changes away from the main actor. Ownership keeps
/// an older session's deactivation from stopping a newer live transcription.
actor LocalAudioSession {
    static let shared = LocalAudioSession()
    private var owner: UUID?
    private var transition: Task<Void, Error>?
    private var transitionID: UUID?
    private let queue = DispatchQueue(label: "Jotley.AudioSession", qos: .userInitiated)
    func activate(owner: UUID) async throws {
        let previous = transition, id = UUID()
        let next = Task {
            _ = try? await previous?.value
            try await self.performActivation(owner: owner)
        }
        transition = next; transitionID = id
        defer { if transitionID == id { transition = nil; transitionID = nil } }
        try await next.value
    }
    private func performActivation(owner: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setActive(true)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        self.owner = owner
    }
    func deactivate(owner: UUID) async {
        let previous = transition, id = UUID()
        let next = Task<Void, Error> {
            _ = try? await previous?.value
            await self.performDeactivation(owner: owner)
        }
        transition = next; transitionID = id
        defer { if transitionID == id { transition = nil; transitionID = nil } }
        _ = try? await next.value
    }
    private func performDeactivation(owner: UUID) async {
        guard self.owner == owner else { return }
        self.owner = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                continuation.resume()
            }
        }
    }
}

/// One-way upgrade cleanup, confined to the two legacy audio directories in
/// this iOS sandbox. Notes, transcripts, the database and Mac files stay intact.
enum LegacyMobileAudioCleanup {
    static func remove(in root: URL, fileManager: FileManager = .default) throws {
        for directory in ["Recordings", "DeletedRecordings"] {
            let url = root.appendingPathComponent(directory, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }
}

/// Count microphone buffers independently of UI scheduling. Quiet or zero-valued
/// samples are not proof of a disconnected microphone; only absent buffers stall.
final class MicrophoneCaptureProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: Int64 = 0
    private var lastBufferTime: TimeInterval
    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) { lastBufferTime = startedAt }
    func received(frames: Int, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard frames > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        self.frames += Int64(frames); lastBufferTime = time

    }
    func snapshot(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> (frames: Int64, stalled: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (frames, time - lastBufferTime >= 3)
    }
}

/// Each update replaces the current take's provisional text. Persist volatile
/// words too: without an audio file, an interruption must not discard them.
@MainActor struct MobileTranscriptCheckpoint {
    let baseText: String
    let baseUtterances: [TranscriptUtterance]
    let offset: TimeInterval
    func save(_ value: LocalTranscript, to note: Note, in store: SharedPersistenceController) throws -> String {
        let text = [baseText, value.displayText].filter { !$0.isEmpty }.joined(separator: " ")
        note.transcription = text
        // Persist provisional words too. The saved-note display deliberately
        // filters interim recognition results, so checkpoints mark them durable.
        note.setTranscriptUtterances(utterances(for: value).map {
            TranscriptUtterance(id: $0.id, text: $0.text, start: $0.start, end: $0.end,
                speaker: $0.speaker, confidence: $0.confidence)
        })
        try store.save()
        return text
    }
    func utterances(for value: LocalTranscript) -> [TranscriptUtterance] {
        let previous = baseUtterances.isEmpty ? TranscriptUtterance.fallbackUtterances(from: baseText) : baseUtterances
        var current = value.utterances.map {
            TranscriptUtterance(id: "live-\(offset)-\($0.start)", text: $0.text,
                start: offset + $0.start, end: offset + $0.end)
        }
        if !value.tentative.isEmpty, let start = value.tentativeStart, let end = value.tentativeEnd {
            current.append(TranscriptUtterance(id: "live-\(offset)-\(start)", text: value.tentative,
                start: offset + start, end: offset + end, isInterim: true))
        }
        return previous + current
    }
    func displayUtterances(for value: LocalTranscript) -> [TranscriptUtterance] {
        let all = utterances(for: value)
        return TranscriptUtterance.coalescedForDisplay(all.filter { !$0.isInterim }) + all.filter(\.isInterim)
    }
}

enum TranscriptionState { case idle, listening, paused }

/// The mobile lifecycle can be verified without a simulator speech model.
protocol MobileSpeechSession: Sendable {
    func append(_ data: Data, sampleRate: Double)
    func finish() async throws -> LocalTranscript
    func cancel() async
}
extension LiveSpeechSession: MobileSpeechSession {}

@MainActor
final class LiveTranscriptionManager: ObservableObject {
    static let willBeginTranscription = Notification.Name("JotleyWillBeginLiveTranscription")
    @Published private(set) var transcriptionState: TranscriptionState = .idle
    @Published private(set) var busy = false
    @Published private(set) var transcriptionDuration: TimeInterval = 0
    private(set) var audioLevel: Float = 0
    @Published private(set) var activeNoteID: UUID?
    @Published private(set) var liveTranscript = ""
    @Published private(set) var liveUtterances: [TranscriptUtterance] = []
    @Published var captureScreenVisible = false
    @Published var errorMessage: String?
    @Published private(set) var summaryNoteID: UUID?
    @Published private(set) var summaryPreview = ""
    @Published private(set) var summaryProgress: LocalSummaryProgress = .preparing
    let summaryNotifications: JotleySummaryNotifications
    private let store: SharedPersistenceController?
    private let audioSessionOwner = UUID()
    private var pendingInterruption: String?
    private var pendingStop: String?
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var speech: (any MobileSpeechSession)?
    private var stopRequests = 0
    private var transitionWaiters: [CheckedContinuation<Void, Never>] = []
    #if DEBUG && targetEnvironment(simulator)
    // Explicit test injection only; no synthetic speech is compiled into releases.
    var simulatedSpeechStart: (@MainActor (@escaping @Sendable (LocalTranscript) async -> Void) async throws -> any MobileSpeechSession)?
    var simulatedCaptureStart: (@MainActor () async -> Void)?
    var simulatedSummaryGeneration: (@MainActor (@escaping @Sendable (String) async -> Void) async throws -> String)?
    var simulatedTagGeneration: (@MainActor (String, [LocalTagCandidate]) async throws -> [String])?
    #endif
    private var sessionID: UUID?
    private var endingSession = false
    private var speechHasFailed = false
    private var pendingTranscript: LocalTranscript?
    private var transcriptFlushTask: Task<Void, Never>?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let notificationCenter: NotificationCenter
    private var previousDuration: TimeInterval = 0
    private var segmentRate: Double = 0
    private var captureProgress: MicrophoneCaptureProgress?
    private var engineObserver: NSObjectProtocol?
    private var baseTranscript = ""
    private var baseUtterances: [TranscriptUtterance] = []
    private(set) var transcriptOffset: TimeInterval = 0
    private var captureLease: UUID?
    private var summaryTask: Task<Void, Never>?
    private var summaryRuntime: SummaryBackgroundRuntime?
    private var pendingSummaryJob: MobileSummaryJob?
    private var summaryPausedBySystem = false
    var summaryRecoveryURL: URL? { store?.root.appendingPathComponent("SummaryGeneration.json") }
    private let liveActivity = LocalTranscriptionLiveActivity()
    var locale: Locale { Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US") }
    var isTranscribing: Bool { transcriptionState != .idle }
    var canStart: Bool { !busy && stopRequests == 0 && !isTranscribing && summaryNoteID == nil }

    init(store: SharedPersistenceController?, notificationCenter: NotificationCenter = .default, summaryNotifications: JotleySummaryNotifications? = nil) {
        self.summaryNotifications = summaryNotifications ?? .shared
        self.store = store; self.notificationCenter = notificationCenter
        guard let store, store.ready else { return }
        do { try LegacyMobileAudioCleanup.remove(in: store.root) } catch { errorMessage = "Could not remove previous audio: \(error.localizedDescription). Your transcript text is preserved." }
        if let url = summaryRecoveryURL, FileManager.default.fileExists(atPath: url.path) {
            do { pendingSummaryJob = try JSONDecoder().decode(MobileSummaryJob.self, from: Data(contentsOf: url)) }
            catch { errorMessage = "Summary recovery could not be read. Your saved transcript and summary are unchanged: \(error.localizedDescription)" }
        }
        let center = notificationCenter
        observers.append(center.addObserver(forName: AVAudioApplication.inputMuteStateChangeNotification, object: nil, queue: .main) { [weak self] notice in
            guard notice.userInfo?[AVAudioApplication.muteStateKey] as? Bool == true else { return }
            Task { @MainActor [weak self] in self?.handleInterruption("The microphone is muted. Transcription is paused. Unmute the microphone, then tap Resume. Words already transcribed are saved.") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main) { [weak self] notice in
            if let context = notice.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext, context.source == .app { return }
            Task { @MainActor [weak self] in
                self?.handleInterruption("Transcription paused by an audio interruption. Resume when the microphone is available.")
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notice in
            guard let raw = notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in self?.handleInterruption("The audio input changed. Transcription is paused; reconnect the microphone or resume with the new input.") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activeNoteID != nil else { return }
                let message = "Audio services restarted. Live transcription stopped; words already transcribed are saved."
                if self.busy { self.pendingStop = message }
                else { self.errorMessage = message; await self.stopTranscription() }
            }
        })
    }
    private func handleInterruption(_ message: String) {
        guard activeNoteID != nil else { return }
        if busy { pendingInterruption = message }
        else if transcriptionState == .listening { pauseTranscription(); errorMessage = message }
    }
    private func finishTransition() {
        busy = false
        let waiters = transitionWaiters
        transitionWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if let message = pendingStop {
            pendingStop = nil; pendingInterruption = nil
            Task { @MainActor [weak self] in self?.errorMessage = message; await self?.stopTranscription() }
        } else if let message = pendingInterruption {
            pendingInterruption = nil
            if transcriptionState == .listening { pauseTranscription(); errorMessage = message }
        }
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
        if let engineObserver { notificationCenter.removeObserver(engineObserver) }
        timer?.invalidate(); transcriptFlushTask?.cancel()
    }

    func createNote(text: String = "", title: String = "Untitled") throws -> Note {
        guard let store, store.ready, canStart else { throw LocalError.message("Finish the current transcription or summary first.") }
        guard let note = try store.create(title: title, text: text, noteType: "voice") as? Note else { throw LocalError.message("Unable to create a local note.") }
        return note
    }
    func startTranscription(note existing: Note? = nil) async {
        guard canStart, let store else { return }
        busy = true; defer { finishTransition() }
        errorMessage = nil
        do {
            if let reason = MobileDeviceEligibility.unsupportedReason { throw LocalError.message(reason) }
            #if DEBUG && targetEnvironment(simulator)
            let permitted = simulatedSpeechStart != nil ? true : await AVAudioApplication.requestRecordPermission()
            #else
            let permitted = await AVAudioApplication.requestRecordPermission()
            #endif
            guard permitted else { throw LocalError.message("Microphone access is required. Enable Microphone in Settings → Apps → Jotley.") }
            guard stopRequests == 0 else { return }
            let note: Note
            if let existing { note = existing } else {
                guard let created = try store.create(title: "Untitled") as? Note else { throw LocalError.message("Unable to create note.") }
                note = created
            }
            guard note.managedObjectContext === store.context, !note.isDeleted, let id = note.id else { throw LocalError.message("This note is unavailable.") }
            captureLease = try store.beginRecording(note)
            activeNoteID = id; note.noteType = "voice"; try store.save()
            baseTranscript = note.transcription ?? ""; baseUtterances = note.transcriptUtterances
            if baseUtterances.isEmpty { baseUtterances = TranscriptUtterance.fallbackUtterances(from: baseTranscript) }
            transcriptOffset = baseUtterances.compactMap(\.end).max() ?? 0
            transcriptionDuration = 0; previousDuration = 0; liveTranscript = baseTranscript
            liveUtterances = baseUtterances.isEmpty ? TranscriptUtterance.fallbackUtterances(from: baseTranscript) : baseUtterances
            // Prepare the local speech engine before opening the microphone.
            // No saved audio exists to retry if the model is unavailable.
            let token = UUID(); sessionID = token; endingSession = false; speechHasFailed = false
            let snapshot: @Sendable (LocalTranscript) async -> Void = { [weak self] value in
                await MainActor.run { [weak self] in
                    guard self?.sessionID == token else { return }
                    self?.stageTranscript(value, token: token)
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            if let simulatedSpeechStart { speech = try await simulatedSpeechStart(snapshot) }
            else { speech = try await prepareSpeech(snapshot: snapshot, token: token) }
            #else
            speech = try await prepareSpeech(snapshot: snapshot, token: token)
            #endif
            guard stopRequests == 0 else { return }
            guard !speechHasFailed else { throw LocalError.message("The speech engine could not start. Try again after checking on-device speech in Settings.") }
            notificationCenter.post(name: Self.willBeginTranscription, object: nil)
            try await startSegment()
            guard stopRequests == 0 else { return }
            transcriptionState = .listening
            liveActivity.start(noteID: id)
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateCaptureProgress() }
            }
        } catch {
            endingSession = true; sessionID = nil; pendingStop = nil; pendingInterruption = nil
            flushTranscript()
            closeSegment(); await speech?.cancel(); speech = nil; activeNoteID = nil; transcriptionState = .idle
            if let captureLease { store.endRecording(lease: captureLease); self.captureLease = nil }
            errorMessage = Self.microphoneErrorMessage(error)
            await LocalAudioSession.shared.deactivate(owner: audioSessionOwner)
        }
    }
    private func prepareSpeech(snapshot: @escaping @Sendable (LocalTranscript) async -> Void, token: UUID) async throws -> LiveSpeechSession {
        try await LiveSpeechSession.start(locale: locale, failure: { [weak self] error in
            Task { @MainActor [weak self] in self?.speechFailed(error, sessionID: token) }
        }, snapshot: snapshot)
    }
    private func startSegment() async throws {
        #if DEBUG && targetEnvironment(simulator)
        if simulatedSpeechStart != nil {
            await simulatedCaptureStart?()
            guard stopRequests == 0 else { return }
            segmentRate = 1
            captureProgress = MicrophoneCaptureProgress()
            captureProgress?.received(frames: 1)
            return
        }
        #endif
        guard let speech, let token = sessionID else { throw LocalError.message("Prepare on-device speech before starting the microphone.") }
        try await LocalAudioSession.shared.activate(owner: audioSessionOwner)
        guard stopRequests == 0 else { return }
        guard AVAudioSession.sharedInstance().isInputAvailable else {
            throw LocalError.message("No microphone is available. Disconnect iPhone Mirroring or another app using the microphone, then try again.")
        }
        guard !AVAudioApplication.shared.isInputMuted else {
            throw LocalError.message("The microphone is muted. Unmute it before starting live transcription.")
        }
        let engine = AVAudioEngine(); let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else { throw LocalError.message("The microphone's audio format is unavailable.") }
        self.engine = engine; self.segmentRate = format.sampleRate
        let progress = MicrophoneCaptureProgress()
        captureProgress = progress
        engineObserver = notificationCenter.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self, weak engine] _ in
            Task { @MainActor [weak self, weak engine] in
                guard let self, let engine, self.engine === engine else { return }
                self.handleInterruption("The microphone connection changed. Transcription is paused. Tap Resume to reconnect the input, words already transcribed are saved.")
            }
        }
        // iOS 27's throwing API reports tap setup failures. Its documented buffer
        // range is 100–400 ms; 2048 frames was only 43 ms on a 48 kHz iPhone.
        let tapFrames = AVAudioFrameCount(ceil(format.sampleRate * 0.15))
        try input.installAudioTap(onBus: 0, bufferSize: tapFrames, format: format) { [weak self, weak engine] buffer, _ in
            do {
                let data = try Self.monoPCM(buffer)
                let peak = data.withUnsafeBytes { $0.bindMemory(to: Float.self).reduce(Float(0)) { max($0, abs($1)) } }
                progress.received(frames: Int(buffer.frameLength))
                speech.append(data, sampleRate: format.sampleRate)
                Task { @MainActor [weak self, weak engine] in
                    guard let self, let engine, self.sessionID == token, self.engine === engine, !self.endingSession else { return }
                    self.audioLevel = peak
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.speechFailed(error, sessionID: token)
                }
            }
        }
        tapInstalled = true
        engine.prepare(); try engine.start()
    }
    private func updateCaptureProgress() {
        guard transcriptionState == .listening, let progress = captureProgress, segmentRate > 0 else { return }
        #if DEBUG && targetEnvironment(simulator)
        if simulatedSpeechStart != nil { progress.received(frames: 1) }
        #endif
        let captured = progress.snapshot()
        transcriptionDuration = previousDuration + Double(captured.frames) / segmentRate
        liveActivity.update(seconds: transcriptionDuration, recording: true)
        if captured.stalled {
            handleInterruption("The microphone stopped delivering audio. Transcription is paused; the timer counts microphone input only. Close iPhone Mirroring or another app using the microphone, then tap Resume. Words already transcribed are saved.")
        }
    }
    nonisolated static func microphoneErrorMessage(_ error: Error) -> String {
        if error is LocalError { return error.localizedDescription }
        return "Jotley couldn’t start the microphone. Close iPhone Mirroring or another app using audio, check Microphone in Settings → Apps → Jotley, then try again. Existing notes are preserved."
    }
    nonisolated static func monoPCM(_ buffer: AVReadOnlyAudioPCMBuffer) throws -> Data {
        try monoPCM(AVAudioPCMBuffer(copying: buffer))
    }
    nonisolated static func monoPCM(_ buffer: AVAudioPCMBuffer) throws -> Data {
        guard let channels = buffer.floatChannelData else { throw LocalError.message("Microphone returned no PCM samples.") }
        let count = Int(buffer.frameLength); let channelCount = Int(buffer.format.channelCount)
        var samples = [Float](repeating: 0, count: count)
        for frame in 0..<count {
            for channel in 0..<channelCount { samples[frame] += channels[channel][frame] / Float(channelCount) }
        }
        return samples.withUnsafeBytes { Data($0) }
    }
    private func closeSegment() {
        if let engineObserver { notificationCenter.removeObserver(engineObserver); self.engineObserver = nil }
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine = nil
        if let progress = captureProgress, segmentRate > 0 {
            previousDuration += Double(progress.snapshot().frames) / segmentRate
        }
        captureProgress = nil; transcriptionDuration = previousDuration; audioLevel = 0
    }
    private func speechFailed(_ error: Error, sessionID token: UUID) {
        guard sessionID == token, !endingSession, !speechHasFailed else { return }
        speechHasFailed = true
        let message = "Live transcription stopped: \(error.localizedDescription) Words received so far remain in the note. Only transcript text is saved."
        if busy { pendingStop = message }
        else {
            errorMessage = message
            Task { @MainActor [weak self] in await self?.stopTranscription() }
        }
    }
    func pauseTranscription() {
        guard transcriptionState == .listening, !busy, stopRequests == 0 else { return }
        closeSegment(); transcriptionState = .paused
        liveActivity.update(seconds: transcriptionDuration, recording: false, force: true)
    }
    func resumeTranscription() async {
        guard transcriptionState == .paused, !busy, stopRequests == 0, activeNoteID != nil else { return }
        busy = true; defer { finishTransition() }
        do {
            try await startSegment()
            guard stopRequests == 0 else { return }
            transcriptionState = .listening
            liveActivity.update(seconds: transcriptionDuration, recording: true, force: true)
        } catch { closeSegment(); errorMessage = Self.microphoneErrorMessage(error) }
    }
    func stopTranscription() async {
        // A Stop/Close during setup, Resume or another Stop must wait for the
        // transition, rather than dismissing the sheet with an active engine.
        stopRequests += 1
        defer { stopRequests -= 1 }
        while busy {
            await withCheckedContinuation { transitionWaiters.append($0) }
        }
        guard isTranscribing || speech != nil || activeNoteID != nil else { return }
        busy = true; defer { finishTransition() }
        // Finalization returns an authoritative snapshot. Fence queued streaming
        // callbacks now so they cannot overwrite it, even after Close returns.
        flushTranscript()
        endingSession = true; sessionID = nil
        closeSegment(); timer?.invalidate(); timer = nil
        // An interrupted session with no buffers has nothing to finalize. Waiting
        // for speech results in this state can leave Stop stuck indefinitely.
        if transcriptionDuration == 0 || speechHasFailed { await speech?.cancel() }
        else {
            do { if let speech { accept(try await speech.finish()) } } catch { errorMessage = "Live transcription could not finish: \(error.localizedDescription). Words received so far remain in the note. Only transcript text is saved." }
        }
        speech = nil; sessionID = nil; transcriptionState = .idle
        liveActivity.end(seconds: transcriptionDuration)
        activeNoteID = nil
        await LocalAudioSession.shared.deactivate(owner: audioSessionOwner)
        if let captureLease { store?.endRecording(lease: captureLease); self.captureLease = nil }
    }
    private func stageTranscript(_ value: LocalTranscript, token: UUID) {
        pendingTranscript = value
        guard transcriptFlushTask == nil else { return }
        transcriptFlushTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.sessionID == token, !self.endingSession else { return }
            self.flushTranscript()
        }
    }
    private func flushTranscript() {
        transcriptFlushTask?.cancel(); transcriptFlushTask = nil
        if let value = pendingTranscript {
            pendingTranscript = nil
            accept(value)
        }
    }

    private func accept(_ value: LocalTranscript) {
        guard let store, let id = activeNoteID, let note = fetch(id), !note.isDeleted else { return }
        liveTranscript = [baseTranscript, value.displayText].filter { !$0.isEmpty }.joined(separator: " ")
        let checkpoint = MobileTranscriptCheckpoint(baseText: baseTranscript,
            baseUtterances: baseUtterances, offset: transcriptOffset)
        liveUtterances = checkpoint.displayUtterances(for: value)
        do {
            _ = try checkpoint.save(value, to: note, in: store)
        } catch {
            // A failed checkpoint is fatal for a session without an audio backup.
            if endingSession { errorMessage = "Could not save the latest transcript: \(error.localizedDescription)" }
            else if let sessionID { speechFailed(error, sessionID: sessionID) }
        }
    }

    private func fetch(_ id: UUID) -> Note? {
        guard let store else { return nil }
        let request = NSFetchRequest<Note>(entityName: "Note"); request.predicate = NSPredicate(format: "id == %@", id as CVarArg); request.fetchLimit = 1
        return try? store.context.fetch(request).first
    }


    func delete(_ note: Note) throws {
        guard !busy, !isTranscribing, summaryNoteID == nil, let store else { throw LocalError.message("Finish transcribing or processing before deleting a note.") }
        try store.deleteNoteAndAudio(note)
    }

    func summarize(_ note: Note, template: LocalSummaryTemplate) {
        guard canStart, store != nil, let id = note.id else { return }
        let job = MobileSummaryJob(noteID: id, templateKey: template.key, localeIdentifier: locale.identifier,
            checkpoint: LocalSummaryCheckpoint(input: note.transcription ?? "", template: template))
        do { try persistSummaryJob(job) }
        catch { errorMessage = "Could not save summary recovery: \(error.localizedDescription)"; return }
        summaryNotifications.prepareForSummary()
        startSummary(note, job: job)
    }

    private func persistSummaryJob(_ job: MobileSummaryJob) throws {
        guard let url = summaryRecoveryURL else { throw LocalError.message("Local notes are unavailable.") }
        try JSONEncoder().encode(job).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        pendingSummaryJob = job
    }
    private func removeSummaryJob() {
        pendingSummaryJob = nil
        guard let url = summaryRecoveryURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch { errorMessage = "Could not remove summary recovery: \(error.localizedDescription)" }
    }
    func resumePendingSummary(applicationState: UIApplication.State = UIApplication.shared.applicationState) {
        guard applicationState == .active, summaryTask == nil,
              !busy, !isTranscribing, let job = pendingSummaryJob else { return }
        guard let note = fetch(job.noteID), note.transcription == job.checkpoint.input else {
            removeSummaryJob(); summaryNoteID = nil; summaryPausedBySystem = false; return
        }
        startSummary(note, job: job)
    }
    /// Navigation/backgrounding never calls this. Only Apple's expiration
    /// handler pauses inference; completed sections remain in the local record.
    func pauseSummaryForSystem() {
        guard summaryTask != nil else { return }
        summaryPausedBySystem = true
        summaryProgress = .waitingForForeground
        summaryTask?.cancel()
    }
    private func startSummary(_ note: Note, job: MobileSummaryJob) {
        guard let store else { return }
        let id = job.noteID, template = LocalSummaryTemplate.resolve(job.templateKey)
        let locale = Locale(identifier: job.localeIdentifier)
        summaryPausedBySystem = false
        summaryNoteID = id; summaryPreview = job.checkpoint.result ?? ""; summaryProgress = .preparing; errorMessage = nil
        let runtime = SummaryBackgroundRuntime { [weak self] in self?.pauseSummaryForSystem() }
        summaryRuntime = runtime; runtime.begin()
        summaryTask = Task { [weak self] in
            guard let self else { return }
            var completed = false
            defer {
                runtime.finish(success: completed); self.summaryRuntime = nil; self.summaryTask = nil
                if self.summaryPausedBySystem {
                    self.summaryProgress = .waitingForForeground
                    // Expiration can race returning to the foreground. Restart
                    // only after the old inference has fully unwound.
                    Task { @MainActor [weak self] in self?.resumePendingSummary() }
                } else {
                    self.summaryNoteID = nil; self.summaryPreview = ""; self.summaryProgress = .preparing
                }
            }
            do {
                let update: @Sendable (String) async -> Void = { [weak self] value in
                    guard !Task.isCancelled else { return }
                    await MainActor.run { [weak self] in
                        guard self?.summaryNoteID == id else { return }
                        self?.summaryPreview = value
                        if !value.isEmpty {
                            if self?.summaryProgress != .writing { self?.summaryRuntime?.update(.writing) }
                            self?.summaryProgress = .writing; self?.summaryRuntime?.streamed()
                        }
                    }
                }
                let progress: @Sendable (LocalSummaryProgress) async -> Void = { [weak self] value in
                    guard !Task.isCancelled else { return }
                    await MainActor.run { [weak self] in
                        guard self?.summaryNoteID == id else { return }
                        self?.summaryProgress = value; self?.summaryRuntime?.update(value)
                    }
                }
                let checkpoint: @Sendable (LocalSummaryCheckpoint) async throws -> Void = { [weak self] state in
                    try Task.checkCancellation()
                    try await MainActor.run { [weak self] in
                        guard let self, self.summaryNoteID == id, self.pendingSummaryJob != nil else { throw CancellationError() }
                        var next = job; next.checkpoint = state
                        try self.persistSummaryJob(next)
                    }
                }
                let result: String
                if let savedResult = job.checkpoint.result { result = savedResult }
                else {
                    #if DEBUG && targetEnvironment(simulator)
                    if let simulatedSummaryGeneration { result = try await simulatedSummaryGeneration(update) }
                    else { result = try await LocalSummary.generate(job.checkpoint.input, template: template, locale: locale,
                        resuming: job.checkpoint, checkpoint: checkpoint, progress: progress, snapshot: update) }
                    #else
                    result = try await LocalSummary.generate(job.checkpoint.input, template: template, locale: locale,
                        resuming: job.checkpoint, checkpoint: checkpoint, progress: progress, snapshot: update)
                    #endif
                }
                // Keep the completed model result before the separate title call.
                var finishedJob = self.pendingSummaryJob ?? job; finishedJob.checkpoint.result = result
                try self.persistSummaryJob(finishedJob)
                var generatedTitle: String?
                var titleError: Error?
                if note.shouldReplaceTitleFromGeneratedSummary() {
                    self.summaryProgress = .finishing; runtime.update(.finishing)
                    do { generatedTitle = try await LocalSummary.generateTitle(from: result, locale: locale) }
                    catch is CancellationError { throw CancellationError() }
                    catch { titleError = error }
                }
                var generatedTags: [String]?
                self.summaryProgress = .organizingTags; runtime.update(.organizingTags)
                let library = try store.tagLibrary()
                do {
                    #if DEBUG && targetEnvironment(simulator)
                    if let simulatedTagGeneration { generatedTags = try await simulatedTagGeneration(result, library) }
                    else { generatedTags = try await LocalNoteTags.generate(from: result, transcript: job.checkpoint.input, library: library, locale: locale) }
                    #else
                    generatedTags = try await LocalNoteTags.generate(from: result, transcript: job.checkpoint.input, library: library, locale: locale)
                    #endif
                } catch is CancellationError { throw CancellationError() }
                catch { generatedTags = nil }
                try Task.checkCancellation()
                guard !note.isDeleted, note.transcription == job.checkpoint.input else {
                    throw LocalError.message("This transcript changed during generation. Your current note was preserved; generate a summary again.")
                }
                try store.saveNoteChanges(note,
                    values: note.generatedSummaryValues(result, template: template.key, generatedTitle: generatedTitle), replacingTags: LocalNoteTags.completedNames(generatedTags, transcript: job.checkpoint.input, summary: result, library: library))
                self.removeSummaryJob(); completed = true
                await self.summaryNotifications.summarySaved(noteID: id)
                JotleyEngagement.shared.completedSummary(result: result)
                let warnings = [titleError.map { "Title: \($0.localizedDescription)" }].compactMap { $0 }
                if !warnings.isEmpty { self.errorMessage = "Summary saved. " + warnings.joined(separator: " ") }
            } catch is CancellationError {
                if !self.summaryPausedBySystem { self.removeSummaryJob() }
            } catch {
                if Task.isCancelled {
                    if !self.summaryPausedBySystem { self.removeSummaryJob() }
                } else if UIApplication.shared.applicationState != .active {
                    self.summaryPausedBySystem = true
                } else { self.removeSummaryJob(); self.errorMessage = error.localizedDescription }
            }
        }
    }
    func cancelProcessing() {
        summaryPausedBySystem = false; removeSummaryJob()
        summaryTask?.cancel()
        if summaryTask == nil { summaryNoteID = nil; summaryPreview = ""; summaryProgress = .preparing }
    }
    func saveEdits() { flushTranscript(); do { try store?.save() } catch { errorMessage = error.localizedDescription } }
}

// Keep the existing Codable names for installed Live Activity compatibility.
// This schema is also used by the widget extension. No note text,
// microphone samples, remote token or shared-container access is needed.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var isRecording: Bool
        var lastUpdatedAt: Date?
        var formattedDuration: String { String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60) }
        var timerStartDate: Date { (lastUpdatedAt ?? Date()).addingTimeInterval(-Double(elapsedSeconds)) }
    }
    var recordingId: String
    var startTime: Date
}

@MainActor private final class LocalTranscriptionLiveActivity {
    private var activity: Activity<RecordingActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var transition: Task<Void, Never>?
    private var transitionID: UUID?
    init() {
        let orphans = Activity<RecordingActivityAttributes>.activities
        enqueue { for item in orphans { await item.end(nil, dismissalPolicy: .immediate) } }
    }
    func start(noteID: UUID) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RecordingActivityAttributes.ContentState(elapsedSeconds: 0, isRecording: true, lastUpdatedAt: Date())
        do {
            activity = try Activity.request(attributes: RecordingActivityAttributes(recordingId: noteID.uuidString, startTime: Date()),
                content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            lastUpdate = Date()
        } catch {
            // Live Activities are optional; denied/disabled activities must never
            // block microphone capture or the user's transcript.
            activity = nil
        }
    }
    func update(seconds: TimeInterval, recording: Bool, force: Bool = false) {
        guard let activity, force || Date().timeIntervalSince(lastUpdate) >= 15 else { return }
        lastUpdate = Date()
        let state = RecordingActivityAttributes.ContentState(elapsedSeconds: max(0, Int(seconds)), isRecording: recording, lastUpdatedAt: Date())
        enqueue { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }
    func end(seconds: TimeInterval) {
        guard let activity else { return }
        self.activity = nil
        let state = RecordingActivityAttributes.ContentState(elapsedSeconds: max(0, Int(seconds)), isRecording: false, lastUpdatedAt: Date())
        enqueue { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
    }
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = transition, id = UUID()
        transitionID = id
        transition = Task { @MainActor in
            await previous?.value
            await operation()
            if transitionID == id { transition = nil; transitionID = nil }
        }
    }
}
