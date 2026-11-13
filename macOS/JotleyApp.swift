import SwiftUI
import AppKit
import CoreData
import FoundationModels

@main enum JotleyMain {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--mcp-stdio") {
            await JotleyMCPStdioBridge.run()
        } else {
            #if DEBUG
            if let fixture = ProcessInfo.processInfo.environment["JOTLEY_SCREENSHOT_DATA"] {
                do {
                    LocalAppModel.isolatedStoreForTesting = try screenshotLibrary(fixture)
                } catch {
                    fatalError("Could not create the isolated screenshot library: \(error)")
                }
            }
            #endif
            JotleyApp.main()
        }
    }

    #if DEBUG
    @MainActor private static func screenshotLibrary(_ fixture: String) throws -> SharedPersistenceController {
        struct Sample: Decodable {
            let title: String
            let folder: String
            let tags: [String]
            let transcript: String
            let summary: String
        }
        let samples = try JSONDecoder().decode([Sample].self, from: Data(fixture.utf8))
        let store = try SharedPersistenceController(inMemory: true)
        for (index, sample) in samples.enumerated() {
            guard let note = try store.create(title: sample.title, text: sample.transcript, noteType: "voice") as? Note
            else { throw LocalError.message("Could not create a screenshot note.") }
            note.timestamp = Date().addingTimeInterval(Double(-index * 3_600))
            note.summary = sample.summary
            if !sample.folder.isEmpty {
                note.folder = Folder.getOrCreate(named: sample.folder, in: store.context)
            }
            for tag in sample.tags { try note.addTagByName(tag, in: store.context) }
            let utterances = sample.transcript.components(separatedBy: "\n\n").enumerated().map { index, text in
                TranscriptUtterance(text: text, start: Double(index * 25), end: Double((index + 1) * 25))
            }
            note.setTranscriptUtterances(utterances)
        }
        try store.save()
        return store
    }
    #endif
}

struct JotleyApp: App {
    private let openingSize = CGSize(width: 1080, height: 720)
    @NSApplicationDelegateAdaptor private var appDelegate: JotleyAppDelegate
    @ObservedObject private var local = LocalAppModel.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var updates = JotleyUpdates.shared
    var body: some Scene {
        WindowGroup(id: "main") {
            if let store = local.store, store.ready {
                RootView(recorder: local.recorder)
                    .environment(\.managedObjectContext, store.context)
                    .environmentObject(store)
                    .tint(Color.themePrimaryAccent)
                    .frame(minWidth: 900, minHeight: 600)
            } else { Text(local.message).padding().frame(minWidth: 600, minHeight: 300) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: openingSize.width, height: openingSize.height)
        .restorationBehavior(MacScreenshotFixture.isActive ? .disabled : .automatic)
        .defaultLaunchBehavior(MacScreenshotFixture.isActive ? .presented : .automatic)
        .commands {
            if MacScreenshotFixture.isActive {
                ScreenshotWindowCommands()
            }
            CommandGroup(after: .appInfo) {
                if updates.isEnabled {
                    Button("Check for Updates…") { updates.check() }
                        .disabled(!updates.canCheck || !updates.isIdle)
                }
            }
            CommandGroup(after: .help) {
                Button("Send Feedback…") {
                    NSWorkspace.shared.open(JotleyEngagement.feedbackURL)
                }
            }
            CommandGroup(replacing: .newItem) {
            Button("New Transcription") { Task { await appDelegate.activeNotesViewModel?.startNewNote() } }.keyboardShortcut("n")
        } }
    }
}

private struct ScreenshotWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Open Screenshot Window") { openWindow(id: "main") }
                .keyboardShortcut("0", modifiers: [.command, .option])
        }
    }
}

enum MacScreenshotFixture {
    static var isActive: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["JOTLEY_SCREENSHOT_DATA"] != nil
        #else
        false
        #endif
    }
}

@MainActor
final class LocalAppModel: ObservableObject {
    #if DEBUG
    /// Native UI harnesses install an isolated library before shared is first used.
    /// They must never open or clean up the user's development library.
    static var isolatedStoreForTesting: SharedPersistenceController?
    #endif
    static let shared = LocalAppModel()
    @Published var notes: [NSManagedObject] = []
    @Published var selected: UUID?
    @Published var message = ""
    @Published var busy = false
    @Published var language = "en-US"
    @Published var speechStatus = "Checking installed speech models…"
    @Published var summaryStatus = ""
    let recorder = ProcessTapRecorder()
    let mcp = JotleyMCPService()
    private(set) var store: SharedPersistenceController?
    var current: NSManagedObject? { notes.first { $0.localNoteID == selected } }
    var ready: Bool { store?.ready == true }

    init() {
        #if DEBUG
        if let isolated = Self.isolatedStoreForTesting {
            store = isolated
            do { try reload() } catch { message = error.localizedDescription }
            return
        }
        #endif
        if let reason = JotleyAppleIntelligenceEligibility.unsupportedReason {
            message = reason
            return
        }
        do {
            store = try SharedPersistenceController(syncMode: NoteSyncMode.application())
            if let reason = store?.errorMessage { message = reason }
            try reload()
            if let store, store.ready {
                do { try LegacyAudioCleanup.remove(in: store.root) }
                catch { message = "Could not remove previous audio: \(error.localizedDescription). Your transcript text is preserved." }
            }
        } catch { message = error.localizedDescription }
        Task {
            if let store, store.ready { await mcp.attach(store: store) }
            await refreshReadiness()
        }
    }
    func reload() throws {
        notes = try store?.notes() ?? []
        if selected == nil { selected = notes.first?.localNoteID }
    }
    func refreshReadiness() async {
        guard #available(macOS 26.0, *) else {
            speechStatus = "On-device speech requires macOS 26 or later."; return
        }
        do {
            let config = try await LocalSpeech.configuration(locale: Locale(identifier: language))
            speechStatus = "Installed: \(config.engine.rawValue) · \(config.locale.identifier)"
        } catch { speechStatus = error.localizedDescription }
        summaryStatus = LocalSummary.readiness(locale: Locale(identifier: language)) ?? "On-device summaries ready."
    }
    func exportObsidian() {
        guard let note = current, !busy, !recorder.recording, !recorder.isBusy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Export Here"; panel.message = "Choose an Obsidian vault folder for Markdown."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            let markdown = "# \(note.text("title"))\n\n\(note.text("summary"))\n\n## Transcript\n\n\(note.text("transcription"))\n\n## Notes\n\n\(note.text("notes"))\n"
            try markdown.write(to: folder.appendingPathComponent("Jotley-\(UUID().uuidString).md"), atomically: true, encoding: .utf8)
            message = "Markdown exported to the selected folder."
        } catch { message = "Export failed: \(error.localizedDescription)" }
    }
}
