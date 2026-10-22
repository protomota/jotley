import SwiftUI
import AppKit
import CoreData
import AVFoundation
import UniformTypeIdentifiers
import FoundationModels

@main struct JotleyApp: App {
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
        .commands {
            CommandGroup(after: .appInfo) {
                if updates.isEnabled {
                    Button("Check for Updates…") { updates.check() }
                        .disabled(!updates.canCheck || !updates.isIdle)
                }
            }
            CommandGroup(replacing: .newItem) {
            Button("New Transcription") { Task { await appDelegate.activeNotesViewModel?.startNewNote() } }.keyboardShortcut("n")
        } }
    }
}

@MainActor
final class LocalAppModel: ObservableObject {
    static let shared = LocalAppModel()
    @Published var notes: [NSManagedObject] = []
    @Published var selected: UUID?
    @Published var message = ""
    @Published var busy = false
    @Published var preview = ""
    @Published var language = "en-US"
    @Published var speechStatus = "Checking installed speech models…"
    @Published var summaryStatus = ""
    let recorder = ProcessTapRecorder()
    private(set) var store: SharedPersistenceController?
    private var operation: Task<Void, Never>?
    var current: NSManagedObject? { notes.first { $0.localNoteID == selected } }
    var ready: Bool { store?.ready == true }

    init() {
        if let reason = JotleyAppleIntelligenceEligibility.unsupportedReason {
            message = reason
            return
        }
        do {
            store = try SharedPersistenceController(syncMode: NoteSyncMode.application())
            if let reason = store?.errorMessage { message = reason }
            try reload()
            try recoverRecordings()
        } catch { message = error.localizedDescription }
        Task { await refreshReadiness() }
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
    func recordingDirectory(for note: NSManagedObject) throws -> URL {
        guard let store else { throw LocalError.message("Local storage is unavailable.") }
        let relative = note.text("sourceURL")
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains(":") else {
            throw LocalError.message("This note has no local audio.")
        }
        let url = store.root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(store.root.standardizedFileURL.path + "/") else {
            throw LocalError.message("Audio path is outside the local store.")
        }
        return url
    }
    func audioFiles(for note: NSManagedObject) throws -> [URL] {
        let directory = try recordingDirectory(for: note)
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let segments = try children.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("recording.json").path) }
            .map { ($0, try DurableAudioWriter.manifest(at: $0).createdAt) }.sorted { $0.1 < $1.1 }
        return try segments.map { try DurableAudioWriter.audioFile(at: $0.0) }
    }
    func recoverRecordings() throws {
        guard let store, ready else { return }
        let root = store.root.appendingPathComponent("Recordings")
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        var recovered = 0
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            let segments = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("recording.json").path) }
            var recoveredSegments: [URL] = []
            for segment in segments {
                do {
                    if try !DurableAudioWriter.manifest(at: segment).complete {
                        _ = try DurableAudioWriter.audioFile(at: segment)
                        recoveredSegments.append(segment)
                    }
                } catch { message = "Some audio needs recovery: \(error.localizedDescription). Original files were preserved." }
            }
            if !recoveredSegments.isEmpty {
                // Capture saves its note before writing audio. Fetch the current
                // store state; an absent note may have been deleted via sync.
                // Retain/recover its audio without inserting another note.
                if let note = try store.notes().first(where: { $0.localNoteID == id }) {
                    try store.saveNoteChanges(note, values: [
                        "sourceURL": "Recordings/\(id.uuidString)"
                    ])
                    recovered += 1
                }
                // Mark only after audio and any surviving note are safely recovered.
                for segment in recoveredSegments {
                    var manifest = try DurableAudioWriter.manifest(at: segment)
                    manifest.complete = true
                    try JSONEncoder().encode(manifest).write(to: segment.appendingPathComponent("recording.json"), options: .atomic)
                }
            }
        }
        try reload()
        if recovered > 0 { message = "Recovered \(recovered) interrupted transcription session(s). Select a note to continue." }
    }
    func transcribe() {
        guard let note = current, !busy, !recorder.recording, !recorder.isBusy else { return }
        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US")
        busy = true; preview = ""; message = "Transcribing saved audio on this Mac…"
        operation = Task {
            defer { busy = false; operation = nil; preview = "" }
            do {
                guard #available(macOS 26.0, *) else { throw LocalError.message("macOS 26 is required.") }
                let files = try audioFiles(for: note)
                guard !files.isEmpty else { throw LocalError.message("No audio segments found.") }
                let value = try await LocalSpeech.transcribe(files: files, locale: locale) { [weak self] value in
                    await MainActor.run { self?.preview = value.displayText }
                }
                try Task.checkCancellation()
                guard !note.isDeleted, note.managedObjectContext != nil else { throw CancellationError() }
                guard !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LocalError.message("No speech was recognized. Existing transcript and audio were preserved.")
                }
                guard let store else { throw LocalError.message("The note store is unavailable.") }
                try store.saveNoteChanges(note, values: ["transcription": value.text,
                    "transcriptUtterancesJSON": String(decoding: try JSONEncoder().encode(value.utterances.map { TranscriptUtterance(text: $0.text, start: $0.start, end: $0.end) }), as: UTF8.self)])
                message = "Transcript saved locally."; objectWillChange.send()
            } catch { message = error is CancellationError ? "Transcription cancelled; existing content and audio preserved." : error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel() }
    func exportObsidian() {
        guard let note = current, !busy, !recorder.recording, !recorder.isBusy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Export Here"; panel.message = "Choose an Obsidian vault folder for Markdown and local audio."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            let base = "Jotley-\(UUID().uuidString)"
            var markdown = "# \(note.text("title"))\n\n\(note.text("summary"))\n\n## Transcript\n\n\(note.text("transcription"))\n\n## Notes\n\n\(note.text("notes"))\n"
            // Synced notes can refer to recordings held only on their source device.
            var includedAudio = false
            if let directory = try? recordingDirectory(for: note),
               FileManager.default.fileExists(atPath: directory.path) {
                let audio = try audioFiles(for: note)
                let attachments = folder.appendingPathComponent(base + "-audio")
                try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
                for (index, file) in audio.enumerated() {
                    let name = "segment-\(index + 1).caf"
                    try FileManager.default.copyItem(at: file, to: attachments.appendingPathComponent(name))
                    markdown += "\n![[\(base)-audio/\(name)]]\n"
                }
                includedAudio = !audio.isEmpty
            }
            try markdown.write(to: folder.appendingPathComponent(base + ".md"), atomically: true, encoding: .utf8)
            message = includedAudio ? "Markdown and audio exported to the selected folder." : "Markdown exported to the selected folder."
        } catch { message = "Export failed: \(error.localizedDescription). Local source files were retained." }
    }
}
