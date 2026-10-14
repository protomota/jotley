import SwiftUI
import CoreData

@main
struct JotleyiOSApp: App {
    private let store: SharedPersistenceController?
    private let launchError: String?
    @StateObject private var transcriptionManager: LiveTranscriptionManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        var persistence: SharedPersistenceController?
        var failure = MobileDeviceEligibility.unsupportedReason
        if failure == nil {
            do {
                #if DEBUG && targetEnvironment(simulator)
                if let data = ProcessInfo.processInfo.environment["JOTLEY_SCREENSHOT_DATA"]?.data(using: .utf8) {
                    // Explicit simulator-only fixtures use a disposable in-memory store.
                    // No fixture path or data-loading hook is compiled into shipping builds.
                    if let progress = ProcessInfo.processInfo.environment["JOTLEY_TEST_ENGAGEMENT_COUNT"], let count = Int(progress) {
                        UserDefaults.standard.set(count, forKey: JotleyEngagement.countKey)
                        UserDefaults.standard.set(true, forKey: JotleyEngagement.reviewKey)
                    }
                    let fixtureStore = try SharedPersistenceController(inMemory: true)
                    let samples = try JSONDecoder().decode([ScreenshotNote].self, from: data)
                    for (index, sample) in samples.enumerated() {
                        let object = try fixtureStore.create(title: sample.title, text: sample.transcript, noteType: "voice")
                        if let note = object as? Note {
                            note.summary = sample.summary
                            note.summaryType = sample.summary.isEmpty ? "default-summary" : "Concise"
                            note.timestamp = Date().addingTimeInterval(Double(-index * 3600))
                            note.folder = Folder.getOrCreate(named: sample.folder, in: fixtureStore.context)
                            for tag in sample.tags { try note.addTagByName(tag, in: fixtureStore.context) }
                            note.setTranscriptUtterances(sample.transcript.components(separatedBy: "\n\n").enumerated().map { TranscriptUtterance(text: $0.element, start: Double($0.offset * 25), end: Double(($0.offset + 1) * 25)) })
                        }
                    }
                    try fixtureStore.save()
                    persistence = fixtureStore
                    UserDefaults.standard.set(ProcessInfo.processInfo.environment["JOTLEY_SCREENSHOT_APPEARANCE"] ?? "Light", forKey: "selectedAppearanceMode")
                } else { persistence = try SharedPersistenceController(syncMode: NoteSyncMode.application()) }
                #else
                persistence = try SharedPersistenceController(syncMode: NoteSyncMode.application())
                #endif
                if persistence?.ready != true { failure = persistence?.errorMessage }
            } catch { failure = error.localizedDescription }
        }
        store = persistence; launchError = failure
        let recorder = LiveTranscriptionManager(store: failure == nil ? persistence : nil)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["JOTLEY_TEST_SUMMARY_SCROLL"] == "1" {
            recorder.simulatedSummaryGeneration = { update in
                try await Task.sleep(for: .seconds(3))
                var content = ""
                for index in 1...160 {
                    try await Task.sleep(for: .milliseconds(200))
                    content += "## Summary update \(index)\n\nThe team agreed to keep voice notes and summaries on the device. Maya will review the milestones and Sam will check the next steps.\n\n"
                    await update(content)
                }
                return content
            }
        }
        if ["1", "layout"].contains(ProcessInfo.processInfo.environment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] ?? "") {
            recorder.simulatedSpeechStart = { snapshot in
                let session = SimulatorLifecycleSpeech(snapshot: snapshot)
                await session.publishCards()
                return session
            }
        }
        #endif
        if failure == nil {
            do { try LocalNoteExport.cleanupStaleExports() }
            catch {
                let message = "Temporary export cleanup failed: \(error.localizedDescription). Your notes and saved exports remain available."
                recorder.errorMessage = [recorder.errorMessage, message].compactMap { $0 }.joined(separator: " ")
            }
        }
        _transcriptionManager = StateObject(wrappedValue: recorder)
    }
    var body: some Scene {
        WindowGroup {
            if let store, launchError == nil {
                MainTabView()
                    .environment(\.managedObjectContext, store.context)
                    .environmentObject(store)
                    .environmentObject(transcriptionManager)
                    .task { transcriptionManager.resumePendingSummary() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background { transcriptionManager.saveEdits() }
                        if phase == .active { transcriptionManager.resumePendingSummary() }
                    }
            } else {
                ContentUnavailableView("Jotley Unavailable", systemImage: "iphone", description: Text(launchError ?? "Local notes are unavailable."))
                    .accessibilityIdentifier("unsupportedDeviceView")
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct ScreenshotNote: Decodable {
    let title: String
    let folder: String
    let tags: [String]
    let transcript: String
    let summary: String
}
#endif

#if DEBUG && targetEnvironment(simulator)
/// Deterministic lifecycle/UI fixture, never a speech-recognition acceptance test.
private struct SimulatorLifecycleSpeech: MobileSpeechSession {
    let snapshot: @Sendable (LocalTranscript) async -> Void
    nonisolated func append(_ data: Data, sampleRate: Double) {}
    func publishCards() async {
        if ProcessInfo.processInfo.environment["JOTLEY_TEST_TRANSCRIPTION_LIFECYCLE"] == "layout" {
            var first = LocalTranscript()
            first.accept(text: "First spoken words.", start: 0, end: 1, final: false)
            await snapshot(first)
            Task {
                try? await Task.sleep(for: .seconds(8))
                var growing = first
                growing.accept(text: "First spoken words.", start: 0, end: 1, final: true)
                growing.accept(text: "Second spoken words.", start: 5, end: 6, final: false)
                await snapshot(growing)
                try? await Task.sleep(for: .seconds(8))
                growing.accept(text: "Second spoken words.", start: 5, end: 6, final: true)
                for index in 2..<18 {
                    growing.accept(text: "Transcript card \(index + 1). Words from the active session remain on this device.",
                        start: Double(index * 5), end: Double(index * 5 + 4), final: true)
                }
                growing.accept(text: "Full-page transcript words.", start: 90, end: 91, final: false)
                await snapshot(growing)
                try? await Task.sleep(for: .seconds(4))
                growing.accept(text: "Full-page transcript words.", start: 90, end: 91, final: true)
                growing.accept(text: "Newest transcript words.", start: 95, end: 96, final: false)
                await snapshot(growing)
            }
            return
        }
        var value = LocalTranscript()
        for index in 0..<16 {
            value.accept(text: "Transcript card \(index + 1). Words from the active session remain on this device.",
                start: Double(index * 5), end: Double(index * 5 + 4), final: true)
        }
        value.accept(text: "Last live words.", start: 80, end: 81, final: false)
        await snapshot(value)
        let initial = value
        Task {
            try? await Task.sleep(for: .seconds(2))
            var next = initial
            next.accept(text: "Last live words.", start: 80, end: 81, final: true)
            next.accept(text: "Latest incoming words.", start: 85, end: 86, final: false)
            await snapshot(next)
        }
    }
    func finish() async throws -> LocalTranscript {
        try await Task.sleep(for: .milliseconds(500))
        var value = LocalTranscript()
        value.accept(text: "Completed transcript.", start: 0, end: 1, final: true)
        Task {
            try? await Task.sleep(for: .seconds(2))
            var late = LocalTranscript()
            late.accept(text: "LATE WORDS MUST NEVER APPEAR", start: 2, end: 3, final: true)
            await snapshot(late)
        }
        return value
    }
    func cancel() async {}
}
#endif
