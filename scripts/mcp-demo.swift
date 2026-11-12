// Captures the actual native Settings and notes views using an isolated library.
// It never opens the user's library or edits an agent's saved configuration.
import AppKit
import CoreData
import MCP
import SwiftUI
@testable import Jotley

@main private struct MCPDemo {
    @MainActor static func main() {
        Task { @MainActor in
            do {
                if CommandLine.arguments.dropFirst().first == "--help" {
                    print("Usage: scripts/test-mcp.sh --demo --serve /absolute/output/folder")
                } else {
                    guard ["--serve", "--backup", "--supporter", "--transcript", "--feature-review"].contains(CommandLine.arguments.dropFirst().first ?? "") else {
                        throw LocalError.message("Use --demo --serve /absolute/output/folder to capture the native app views.")
                    }
                    if CommandLine.arguments[1] == "--feature-review" { try await featureReview() }
                    else if ["--backup", "--supporter", "--transcript"].contains(CommandLine.arguments[1]) { try await backupPreview() }
                    else { try await serve() }
                }
                exit(0)
            } catch { fputs("DEMO FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.run()
    }

    @MainActor private static func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    @MainActor private static func featureReview() async throws {
        guard CommandLine.arguments.count >= 3 else { throw LocalError.message("Provide a feature review output folder.") }
        let controlPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : CommandLine.arguments[2]
        let output = URL(fileURLWithPath: controlPath, isDirectory: true)
        let store = try SharedPersistenceController(inMemory: true)
        LocalAppModel.isolatedStoreForTesting = store
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: JotleyOnboarding.completedKey)
        defaults.set(true, forKey: "recordSystemAudio")
        defaults.set("Light", forKey: "selectedAppearanceMode")
        defaults.removeObject(forKey: CustomSpeechWords.defaultsKey)
        let token = UUID().uuidString + UUID().uuidString
        let service = JotleyMCPService(defaults: defaults, port: 0, token: token)
        await service.attach(store: store)
        await service.setEnabled(true, persistPreference: false)
        service.setAllowsWriting(true)
        let local = LocalAppModel.shared
        if ProcessInfo.processInfo.environment["JOTLEY_DEMO_SIMULATED_RECORDING"] == "1" {
            JotleyAppDelegate().setupStatusItem()
            let recorder = local.recorder
            recorder.simulatedStart = { [weak recorder] _, _, _ in
                var speech = LocalTranscript()
                speech.accept(text: "Jason will review the design.", start: 0, end: 3, final: true)
                speech.accept(text: "Share the notes with the team.", start: 14, end: 17, final: true)
                recorder?.beginSimulatedLiveTranscription(speech)
            }
        }
        let host = NSHostingView(rootView: RootView(recorder: local.recorder)
            .environment(\.managedObjectContext, store.context).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 740),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Jotley Feature Review"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        print("READY: isolated Mac feature review"); fflush(stdout)
        var seeded = false
        var changedWords = false
        while !FileManager.default.fileExists(atPath: output.appendingPathComponent("stop").path) {
            if !seeded, FileManager.default.fileExists(atPath: output.appendingPathComponent("seed-note").path) {
                seeded = true
                let note = try store.create(title: "Launch planning", text: "JSON is reviewing the design.\n\nSend JSON the revised notes. Keep JSONKit as written.") as! Note
                note.setTranscriptUtterances([
                    TranscriptUtterance(text: "JSON is reviewing the design.", start: 0, end: 5),
                    TranscriptUtterance(text: "Send JSON the revised notes. Keep JSONKit as written.", start: 25, end: 31)
                ])
                note.summary = "## Launch plan\n\nReview the design and send the revised notes."
                try store.save(); try local.reload()
                print("READY: timed sample note"); fflush(stdout)
            }
            if !changedWords, FileManager.default.fileExists(atPath: output.appendingPathComponent("mcp-add").path) {
                changedWords = true
                let client = try await MCPIntegration.connect(endpoint: service.endpoint, token: token)
                let current = try await client.callTool(name: "list_custom_words", arguments: [:])
                let state = try JSONSerialization.jsonObject(with: Data(MCPIntegration.text(current.content).utf8)) as? [String: Any]
                guard let revision = state?["revision"] as? String else { throw LocalError.message("Couldn’t read the Custom Words revision.") }
                let updated = try await client.callTool(name: "update_custom_words", arguments: ["expected_revision": .string(revision), "add": ["North Studio"]])
                guard updated.isError != true else { throw LocalError.message("Couldn’t update Custom Words through MCP.") }
                print("PASS: update_custom_words added North Studio"); fflush(stdout)
                await client.disconnect()
            }
            try await pause(0.25)
        }
        await service.setEnabled(false, persistPreference: false)
    }

    @MainActor private static func backupPreview() async throws {
        guard CommandLine.arguments.count >= 3 else { throw LocalError.message("Provide a session output folder") }
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let empty = ProcessInfo.processInfo.environment["JOTLEY_BACKUP_EMPTY"] == "1"
        let store = try empty ? SharedPersistenceController(inMemory: true) : MCPIntegration.fixture()
        LocalAppModel.isolatedStoreForTesting = store
        let service = JotleyMCPService(defaults: UserDefaults(suiteName: "JotleyBackupNativeQA")!, port: 0, token: String(repeating: "a", count: 64))
        let supporterPreview = CommandLine.arguments[1] == "--supporter"
        let content: AnyView
        if CommandLine.arguments[1] == "--transcript" {
            let note = try store.create(title: "Transcript editing", text: "Review the disign. Keep the purple branding. Ship after both checks pass.") as! Note
            let utterances = [TranscriptUtterance(id: "review", text: "Review the disign.", start: 0, end: 4),
                              TranscriptUtterance(id: "brand", text: "Keep the purple branding.", start: 12, end: 18),
                              TranscriptUtterance(id: "ship", text: "Ship after both checks pass.", start: 28, end: 34)]
            try store.saveNoteChanges(note, values: ["transcriptUtterancesJSON": String(decoding: try JSONEncoder().encode(utterances), as: UTF8.self)])
            content = AnyView(TranscriptEditorPreview(note: note, viewModel: NotesListViewModel(viewContext: store.context, recorder: ProcessTapRecorder(), persistenceController: store)).environmentObject(store))
        } else if supporterPreview {
            content = AnyView(VStack(alignment: .leading, spacing: 20) {
                Text("Jotley supporter thank-you — sample purchase only").font(.headline)
                Text("No Apple account, receipt, payment or personal data is used.")
                Button("Preview verified support thank-you") {
                    JotleySupporterStore.shared.recordVerifiedPurchase(id: UUID().uuidString, kind: .support)
                }.accessibilityIdentifier("previewVerifiedSupportThankYou")
                JotleySupporterBadge()
                Text("A real support ticket receives this same badge after its server-verified payment. Note-taking features remain free.")
                Spacer()
            }.padding(40).jotleySupporterCelebration(.support))
        } else {
            content = AnyView(SettingsView(mcp: service, selectedSection: .general).environmentObject(store))
        }
        let host = NSHostingView(rootView: content.preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = supporterPreview ? "Jotley — Supporter Preview" : "Jotley — Backup Test"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("READY: native backup Settings with \(try store.notes().count) synthetic notes; MCP stays disabled")
        fflush(stdout)
        while !FileManager.default.fileExists(atPath: output.appendingPathComponent("stop").path) { try await pause(0.5) }
        let backup = try LibraryBackupService.export(from: store, templates: .shared)
        try LibraryBackupService.encode(backup).write(to: output.appendingPathComponent("verified-library.json"), options: .atomic)
        print("PASS: native backup test finished with \(backup.noteCount) notes")
        window.orderOut(nil)
    }

    @MainActor private static func serve() async throws {
        guard CommandLine.arguments.count >= 3 else { throw LocalError.message("Provide a session output folder") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let store = try MCPIntegration.fixture()
        LocalAppModel.isolatedStoreForTesting = store
        let suite = "JotleyMCPExternalDemo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "foldersExpanded")
        defer { defaults.removePersistentDomain(forName: suite) }
        let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        let service = JotleyMCPService(defaults: defaults, port: JotleyMCPService.defaultPort, token: token)
        await service.attach(store: store)
        let host = NSHostingView(rootView: SettingsView(mcp: service, selectedSection: .mcp)
            .environmentObject(store).preferredColorScheme(.dark)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 820), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Jotley"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await pause(1)
        func snapshot(_ name: String) throws {
            let frame = window.contentView?.superview ?? host
            frame.layoutSubtreeIfNeeded()
            guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { throw LocalError.message("Cannot capture Settings window") }
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
        }
        try snapshot("settings-off.png")
        await service.setEnabled(true)
        try MCPIntegration.expect(service.enabled, service.errorMessage ?? "Sample server did not start")
        await service.testConnection()
        try await pause(0.5)
        try snapshot("settings-ready.png")
        service.setAllowsWriting(true)
        try await pause(0.5)
        try snapshot("settings-write.png")
        let notesHost = NSHostingView(rootView: RootView(recorder: LocalAppModel.shared.recorder)
            .environment(\.managedObjectContext, store.context).environmentObject(store)
            .defaultAppStorage(defaults)
            .preferredColorScheme(.dark))
        let notesWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 850), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        notesWindow.title = "Jotley"
        notesWindow.isReleasedWhenClosed = false
        notesWindow.contentView = notesHost
        notesWindow.appearance = NSAppearance(named: .darkAqua)
        notesWindow.makeKeyAndOrderFront(nil)
        try await pause(1)
        func snapshotNote(_ name: String) throws {
            guard notesWindow.isVisible else { return }
            let frame = notesWindow.contentView?.superview ?? notesHost
            frame.layoutSubtreeIfNeeded()
            guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { throw LocalError.message("Cannot capture note window") }
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
        }
        try snapshotNote("note-before.png")
        let config = folder.appendingPathComponent("client.json")
        try service.clientConfiguration!.write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        print("READY: isolated sample server; client configuration saved")
        fflush(stdout)
        while !FileManager.default.fileExists(atPath: folder.appendingPathComponent("stop").path) {
            try await pause(0.5)
            try snapshot("settings-live.png")
            try snapshotNote("note-live.png")
        }
        try snapshot("settings-agent.png")
        try snapshotNote("note-after.png")
        await service.setEnabled(false)
        window.orderOut(nil)
        notesWindow.orderOut(nil)
        print("PASS: external-client demo session stopped")
    }

}

private struct TranscriptEditorPreview: View {
    @ObservedObject var note: Note
    @ObservedObject var viewModel: NotesListViewModel
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript editing — isolated sample note").font(.headline)
            Text("Correct a paragraph, then return to bubbles. Recorded times remain attached.").font(.callout)
            if !editing { Button("Edit Transcript") { editing = true } }
            ScrollView {
                if editing {
                    LocalMacTranscriptEditor(note: note, viewModel: viewModel) { editing = false }
                } else {
                    TranscriptParagraphsView(transcript: note.transcription ?? "", utterances: note.transcriptUtterances,
                        interimText: "", isRecordingActive: false, showEllipsis: false)
                }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
