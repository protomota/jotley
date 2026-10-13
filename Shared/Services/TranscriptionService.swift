import Foundation
import Speech
import AVFoundation
import CoreMedia

@available(macOS 26.0, iOS 26.0, *)
public enum LocalSpeech {
    public enum Engine: String, Sendable { case speech = "SpeechTranscriber", dictation = "DictationTranscriber" }
    public struct Configuration: Sendable {
        public let module: any SpeechModule
        public let engine: Engine
        public let locale: Locale
    }
    public struct Language: Identifiable, Sendable {
        public let id: String
        public var name: String { Locale.current.localizedString(forIdentifier: id) ?? id }
    }
    public struct Readiness: Sendable {
        public enum Status: Sendable { case unsupported, downloading, supported, installed }
        public let configuration: Configuration?
        public let status: Status
        public let details: String
        init(configuration: Configuration?, status: AssetInventory.Status, details: String = "") {
            self.configuration = configuration
            self.details = details
            switch status {
            case .installed: self.status = .installed
            case .supported: self.status = .supported
            case .downloading: self.status = .downloading
            case .unsupported: self.status = .unsupported
            @unknown default: self.status = .unsupported
            }
        }
        public var needsSetup: Bool { configuration != nil && status != .installed }
        public var message: String {
            if status == .installed { return "On-device speech is ready. Transcription works offline." }
            if needsSetup {
                return "The Apple speech model for this language needs setup. Open Settings and choose Set Up On-Device Speech. Apple Intelligence uses a separate model."
            }
            return "Apple speech is unavailable for the selected language on this device. Choose a language listed in Settings, or refresh speech availability."
        }
    }
    // Prefer an installed fallback over downloading a better engine. Otherwise
    // explicit setup selects SpeechTranscriber before DictationTranscriber.
    static func preferredIndex(statuses: [AssetInventory.Status]) -> Int? {
        statuses.firstIndex(of: .installed) ?? statuses.firstIndex(where: { $0 == .supported || $0 == .downloading }) ?? statuses.indices.first
    }
    static func exactLocale(_ requested: Locale, in supported: [Locale]) -> Locale? {
        supported.first { $0.identifier(.bcp47) == requested.identifier(.bcp47) }
    }
    public static func languages() async -> [Language] {
        let speech = await SpeechTranscriber.supportedLocales
        let dictation = await DictationTranscriber.supportedLocales
        return Set((speech + dictation).map { $0.identifier(.bcp47) }).sorted().map { Language(id: $0) }
    }
    /// A local availability check only: never initiates an installation or download.
    public static func readiness(locale: Locale) async -> Readiness {
        var candidates: [(Configuration, AssetInventory.Status)] = []
        let speechAvailable = SpeechTranscriber.isAvailable
        let speechLocales = await SpeechTranscriber.supportedLocales
        let dictationLocales = await DictationTranscriber.supportedLocales
        var speechEquivalent = exactLocale(locale, in: speechLocales)
        var dictationEquivalent = exactLocale(locale, in: dictationLocales)
        if speechAvailable && speechEquivalent == nil {
            speechEquivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        }
        if dictationEquivalent == nil {
            dictationEquivalent = await DictationTranscriber.supportedLocale(equivalentTo: locale)
        }
        var details = ["Requested language: \(locale.identifier(.bcp47))",
                       "SpeechTranscriber available: \(speechAvailable)",
                       "SpeechTranscriber languages: \(speechLocales.map { $0.identifier(.bcp47) }.sorted().joined(separator: ", "))",
                       "DictationTranscriber languages: \(dictationLocales.map { $0.identifier(.bcp47) }.sorted().joined(separator: ", "))"]
        if speechAvailable, let equivalent = speechEquivalent {
            let module = SpeechTranscriber(locale: equivalent, preset: .timeIndexedProgressiveTranscription)
            let status = await AssetInventory.status(forModules: [module])
            candidates.append((.init(module: module, engine: .speech, locale: equivalent), status))
            details.append("SpeechTranscriber \(equivalent.identifier(.bcp47)): \(status)")
        }
        if let equivalent = dictationEquivalent {
            let module = DictationTranscriber(locale: equivalent, contentHints: [],
                transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
            let status = await AssetInventory.status(forModules: [module])
            candidates.append((.init(module: module, engine: .dictation, locale: equivalent), status))
            details.append("DictationTranscriber \(equivalent.identifier(.bcp47)): \(status)")
        }
        for index in candidates.indices where candidates[index].1 == .installed {
            let config = candidates[index].0
            let formats = await config.module.availableCompatibleAudioFormats
            details.append("\(config.engine.rawValue) usable audio formats: \(formats)")
            if formats.isEmpty {
                // Asset inventory alone can report installed while the engine
                // cannot analyze audio. Keep explicit setup available and prefer
                // another usable installed engine over this incomplete one.
                candidates[index].1 = .supported
                details.append("\(config.engine.rawValue) assets reported installed, but no usable audio format is exposed; setup is still required.")
            }
        }
        guard let index = preferredIndex(statuses: candidates.map(\.1)) else {
            return .init(configuration: nil, status: .unsupported, details: details.joined(separator: "\n"))
        }
        return .init(configuration: candidates[index].0, status: candidates[index].1, details: details.joined(separator: "\n"))
    }
    static func configuration(from ready: Readiness) throws -> Configuration {
        guard ready.status == .installed, let config = ready.configuration else {
            throw LocalError.message(ready.message)
        }
        return config
    }
    public static func configuration(locale: Locale) async throws -> Configuration {
        // Use exactly the same canonical locale and engine selection as Settings.
        // A separate equivalent-locale lookup can disagree with explicit setup.
        let ready = await readiness(locale: locale)
        do {
            guard let config = ready.configuration else { throw LocalError.message(ready.message) }
            // Reassert local asset ownership whenever speech is used. Reservation
            // does not install/download assets; only explicit setUp can do that.
            try await AssetInventory.reserve(locale: config.locale)
            let status = await AssetInventory.status(forModules: [config.module])
            return try configuration(from: .init(configuration: config, status: status, details: ready.details))
        } catch {
            recordFailure(error, locale: locale, details: ready.details)
            throw error
        }
    }
    public static let lastFailureDefaultsKey = "localSpeechLastFailure"
    static func recordFailure(_ error: Error, locale: Locale, details: String = "") {
        guard !(error is CancellationError) else { return }
        let failure = error as NSError
        UserDefaults.standard.set("\(Date().formatted(.iso8601)) · \(locale.identifier(.bcp47))\n\(failure.localizedDescription) (\(failure.domain), \(failure.code))\n\(details)", forKey: lastFailureDefaultsKey)
    }
    static func prepare(configuration: Configuration) async throws -> (SpeechAnalyzer, AVAudioFormat) {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [configuration.module]) else {
            throw LocalError.message("No compatible on-device speech audio format.")
        }
        let analyzer = SpeechAnalyzer(modules: [configuration.module])
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation()
            return (analyzer, format)
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
    /// Invoked only by the user's explicit Settings action. Apple's shared asset
    /// installation needs connectivity; audio and transcription stay on-device.
    public static func setUp(locale: Locale,
        progress: @escaping @Sendable (Double) async -> Void) async throws {
        try Task.checkCancellation()
        let ready = await readiness(locale: locale)
        guard let config = ready.configuration else { throw LocalError.message(ready.message) }
        try Task.checkCancellation()
        // Reserve even preinstalled assets so Apple knows this app uses them.
        try await AssetInventory.reserve(locale: config.locale)
        // Recheck after reservation rather than rejecting a supported locale based
        // on its pre-reservation inventory status. The request returns nil if ready.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [config.module]) {
            let reporter = Task {
                while !Task.isCancelled {
                    await progress(request.progress.fractionCompleted)
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                }
            }
            defer { reporter.cancel() }
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await request.downloadAndInstall()
            } onCancel: { request.progress.cancel() }
        }
        try Task.checkCancellation()
        guard await AssetInventory.status(forModules: [config.module]) == .installed else {
            throw LocalError.message("Apple has not finished installing this language's speech model. Connect to the internet and try Set Up On-Device Speech again.")
        }
        // A successful asset request is not sufficient: verify the same analyzer
        // preparation that live recording uses before presenting speech as ready.
        let verified = try await configuration(locale: locale)
        do {
            let (analyzer, _) = try await prepare(configuration: verified)
            await analyzer.cancelAndFinishNow()
        } catch {
            recordFailure(error, locale: locale, details: "Setup verification: \(verified.engine.rawValue) \(verified.locale.identifier(.bcp47))")
            throw error
        }
        UserDefaults.standard.removeObject(forKey: lastFailureDefaultsKey)
        await progress(1)
    }
    /// File transcription also recovers audio from interrupted sessions. No install request here.
    public static func transcribe(files: [URL], locale: Locale,
        snapshot: @escaping @Sendable (LocalTranscript) async -> Void) async throws -> LocalTranscript {
        var transcript = LocalTranscript(), offset = 0.0
        for url in files {
            try Task.checkCancellation()
            let audio = try AVAudioFile(forReading: url)
            // Pause/resume and interrupted captures can leave valid empty files.
            // An analyzer with no input may never terminate its result stream.
            // Keep these segments on disk, but do not submit them for recognition.
            guard audio.length > 0 else { continue }
            let config = try await configuration(locale: locale)
            let analyzer = SpeechAnalyzer(modules: [config.module])
            let prefix = transcript
            let segmentOffset = offset
            let results: Task<LocalTranscript, Error>
            if let module = config.module as? SpeechTranscriber {
                results = Task {
                    var value = prefix
                    for try await result in module.results {
                        try Task.checkCancellation()
                        value.accept(text: String(result.text.characters), start: segmentOffset + result.range.start.seconds,
                                     end: segmentOffset + CMTimeRangeGetEnd(result.range).seconds, final: result.isFinal)
                        await snapshot(value)
                    }
                    return value
                }
            } else if let module = config.module as? DictationTranscriber {
                results = Task {
                    var value = prefix
                    for try await result in module.results {
                        try Task.checkCancellation()
                        value.accept(text: String(result.text.characters), start: segmentOffset + result.range.start.seconds,
                                     end: segmentOffset + CMTimeRangeGetEnd(result.range).seconds, final: result.isFinal)
                        await snapshot(value)
                    }
                    return value
                }
            } else { throw LocalError.message("Unsupported speech module.") }
            do {
                transcript = try await withTaskCancellationHandler {
                    try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
                    return try await results.value
                } onCancel: {
                    results.cancel()
                    Task { await analyzer.cancelAndFinishNow() }
                }
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
            offset += Double(audio.length) / audio.processingFormat.sampleRate
        }
        try Task.checkCancellation()
        return transcript
    }
}

/// Receives microphone/system audio while it is being captured. Only already-installed
/// on-device assets are used; explicit setup lives separately in Settings.
/// The durable writer remains independent of inference.
@available(macOS 26.0, iOS 26.0, *)
public final class LiveSpeechSession: @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let analysis: Task<Void, Error>
    private let results: Task<LocalTranscript, Error>
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var inputRate: Double = 0
    private var conversionError: Error?
    private let failure: (@Sendable (Error) -> Void)?

    private init(analyzer: SpeechAnalyzer, format: AVAudioFormat,
                 continuation: AsyncStream<AnalyzerInput>.Continuation,
                 analysis: Task<Void, Error>, results: Task<LocalTranscript, Error>,
                 failure: (@Sendable (Error) -> Void)?) {
        self.analyzer = analyzer; self.format = format; self.continuation = continuation
        self.analysis = analysis; self.results = results; self.failure = failure
    }
    public static func start(locale: Locale,
        failure: (@Sendable (Error) -> Void)? = nil,
        snapshot: @escaping @Sendable (LocalTranscript) async -> Void) async throws -> LiveSpeechSession {
        let config = try await LocalSpeech.configuration(locale: locale)
        let analyzer: SpeechAnalyzer
        let format: AVAudioFormat
        do {
            (analyzer, format) = try await LocalSpeech.prepare(configuration: config)
        } catch {
            LocalSpeech.recordFailure(error, locale: locale, details: "Recording: \(config.engine.rawValue) \(config.locale.identifier(.bcp47))")
            throw error
        }
        UserDefaults.standard.removeObject(forKey: LocalSpeech.lastFailureDefaultsKey)
        let stream = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(128))
        let results: Task<LocalTranscript, Error>
        if let module = config.module as? SpeechTranscriber {
            results = Task {
                var value = LocalTranscript()
                do {
                    for try await result in module.results {
                        value.accept(text: String(result.text.characters), start: result.range.start.seconds,
                                     end: CMTimeRangeGetEnd(result.range).seconds, final: result.isFinal)
                        await snapshot(value)
                    }
                } catch {
                    if !(error is CancellationError), !Task.isCancelled { failure?(error) }
                    throw error
                }
                return value
            }
        } else if let module = config.module as? DictationTranscriber {
            results = Task {
                var value = LocalTranscript()
                do {
                    for try await result in module.results {
                        value.accept(text: String(result.text.characters), start: result.range.start.seconds,
                                     end: CMTimeRangeGetEnd(result.range).seconds, final: result.isFinal)
                        await snapshot(value)
                    }
                } catch {
                    if !(error is CancellationError), !Task.isCancelled { failure?(error) }
                    throw error
                }
                return value
            }
        } else { throw LocalError.message("Unsupported on-device speech module.") }
        let analysis = Task {
            do { try await analyzer.start(inputSequence: stream.stream) }
            catch {
                if !(error is CancellationError), !Task.isCancelled { failure?(error) }
                throw error
            }
        }
        do { try await analysis.value }
        catch { results.cancel(); await analyzer.cancelAndFinishNow(); throw error }
        return LiveSpeechSession(analyzer: analyzer, format: format, continuation: stream.continuation,
                                 analysis: analysis, results: results, failure: failure)
    }
    /// Called on the capture queue with mono Float32 microphone samples.
    public func append(_ data: Data, sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        guard conversionError == nil else { return }
        do {
            guard !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Float>.size) else {
                throw LocalError.message("Live audio contains an incomplete PCM sample.")
            }
            guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                                 channels: 1, interleaved: false),
                  let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: UInt32(data.count / 4)),
                  let samples = input.floatChannelData?[0] else { throw LocalError.message("Invalid live audio buffer.") }
            input.frameLength = UInt32(data.count / 4)
            data.withUnsafeBytes { bytes in if let base = bytes.baseAddress { memcpy(samples, base, data.count) } }
            if inputFormat == format { try enqueue(input); return }
            if converter == nil || inputRate != sampleRate {
                converter = AVAudioConverter(from: inputFormat, to: format); inputRate = sampleRate
            }
            guard let converter, let output = AVAudioPCMBuffer(pcmFormat: format,
                frameCapacity: UInt32(ceil(Double(input.frameLength) * format.sampleRate / sampleRate)) + 256) else {
                throw LocalError.message("Live audio conversion is unavailable.")
            }
            var supplied = false, error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return input
            }
            if status == .error { throw error ?? LocalError.message("Live audio conversion failed.") as NSError }
            if output.frameLength > 0 { try enqueue(output) }
        } catch { conversionError = error; continuation.finish(); failure?(error) }
    }
    private func enqueue(_ buffer: AVAudioPCMBuffer) throws {
        if case .dropped = continuation.yield(AnalyzerInput(buffer: buffer)) {
            throw LocalError.message("Live transcription fell behind the microphone. Transcription must stop to avoid silently losing words.")
        }
    }
    private func capturedError() -> Error? { lock.lock(); defer { lock.unlock() }; return conversionError }
    public func finish() async throws -> LocalTranscript {
        continuation.finish()
        do {
            try await analysis.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let value = try await results.value
            if let error = capturedError() { throw error }
            return value
        } catch {
            results.cancel(); analysis.cancel(); await analyzer.cancelAndFinishNow(); throw capturedError() ?? error
        }
    }
    public func cancel() async {
        continuation.finish(); results.cancel(); analysis.cancel(); await analyzer.cancelAndFinishNow()
    }
}
