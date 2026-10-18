#if JOTLEY_MAC_ROUTING_HARNESS
import Foundation
import CoreData
import Darwin
import SwiftUI
import AppKit
import UserNotifications
import AVFoundation
import CoreText
@testable import Jotley

@MainActor private final class SummaryObserverState: ObservableObject {
    @Published var summary = ""
    @Published var error: String?
    @Published var generating = false
    @Published var inlineEdit = 0
    @Published var rawMarkdown = false
}

private struct SummaryObserverView: View {
    let note: Note
    @ObservedObject var state: SummaryObserverState
    @FocusState private var summaryFocused: Bool
    @FocusState private var transcriptFocused: Bool
    @State private var transcript = ""
    @StateObject private var stream = StreamingSummaryViewModel()
    var body: some View {
        DetailTabPanel(note: note, selectedTab: .constant(DetailTab.summary.rawValue),
            isGeneratingSummary: $state.generating, summaryGenerationError: $state.error,
            editableSummary: $state.summary, isSummaryEditorFocused: $summaryFocused,
            summaryInlineEditRequestCounter: $state.inlineEdit, editableTranscript: $transcript,
            isTranscriptEditorFocused: $transcriptFocused,
            showRawMarkdown: $state.rawMarkdown, streamingSummaryViewModel: stream)
    }
}

@MainActor private final class RecordingLayoutDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@objc(JotleyRoutingRefusedNote)
private final class RoutingRefusedNote: Note {
    static var rejectsNewNotes = true
    override func validateForInsert() throws {
        if Self.rejectsNewNotes, title == "Untitled Note" { throw LocalError.message("Injected note creation failure.") }
        try super.validateForInsert()
    }
    override func validateForUpdate() throws {
        // Refuse a mistaken recording update before hardware access. Its changed
        // fields remain observable, so the baseline routing bug still fails.
        if title == "Keep selected note", noteType != "local" || sourceURL != nil {
            throw LocalError.message("The prior selected note cannot become the new recording.")
        }
        try super.validateForUpdate()
    }
}

/// Compile this existing source against the built app with the harness flag to
/// exercise its actual view model without adding a second implementation.
@main private struct MacRoutingHarness {
    @MainActor static func main() async {
        UserDefaults.standard.set(false, forKey: JotleySummaryNotifications.enabledKey)
        if CommandLine.arguments.contains("--layout-preview") {
            previewRecordingControls()
            return
        }
        do {
            if CommandLine.arguments.contains("--summary-scroll-only") {
                guard let store = LocalAppModel.shared.store,
                      let note = try store.create(title: "Summary scroll fixture", text: "Maya reviews Friday.") as? Note else { throw LocalError.message("Summary scroll store unavailable") }
                defer { try? store.deleteNoteAndAudio(note) }
                let model = NotesListViewModel(viewContext: store.context, recorder: LocalAppModel.shared.recorder, persistenceController: store)
                try await verifySummaryFollowAndCancel(note: note, store: store, viewModel: model)
            } else { try await verifyRouting() }
        }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor private static func verifyRouting() async throws {
        let watchdog = Task.detached {
            try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.environment["JOTLEY_RUN_TITLE_TESTS"] == "1" ? 90 : 20))
            if !Task.isCancelled { fputs("Routing test timed out.\n", stderr); _exit(2) }
        }
        defer { watchdog.cancel() }
        guard JotleyUpdates.allowsUpdate(recording: false, recorderBusy: false, processing: false),
              !JotleyUpdates.allowsUpdate(recording: true, recorderBusy: false, processing: false),
              !JotleyUpdates.allowsUpdate(recording: false, recorderBusy: true, processing: false),
              !JotleyUpdates.allowsUpdate(recording: false, recorderBusy: false, processing: true),
              !JotleyUpdates.shared.isEnabled else { throw LocalError.message("Sparkle must wait for idle capture and stay disabled in the isolated test app.") }
        print("PASS: Sparkle waits for recording/finalization/processing and stays disabled in local test variants.")
        var microphoneRequests = 0
        for status: AVAuthorizationStatus in [.authorized, .denied, .restricted] {
            let allowed = await ProcessTapRecorder.authorizeMicrophone(status: status) {
                microphoneRequests += 1
                return true
            }
            guard allowed == (status == .authorized), microphoneRequests == 0 else {
                throw LocalError.message("Determined microphone permissions were requested again.")
            }
        }
        for grant in [true, false] {
            let allowed = await ProcessTapRecorder.authorizeMicrophone(status: .notDetermined) {
                microphoneRequests += 1
                return grant
            }
            guard allowed == grant else { throw LocalError.message("Microphone consent was ignored.") }
        }
        guard microphoneRequests == 2 else { throw LocalError.message("Microphone prompt count is incorrect.") }
        print("PASS: microphone permissions consult macOS and request consent only for undetermined access.")
        let engagementSuite = "JotleyMacEngagement-" + UUID().uuidString
        let engagementDefaults = UserDefaults(suiteName: engagementSuite)!
        defer { engagementDefaults.removePersistentDomain(forName: engagementSuite) }
        let engagement = JotleyEngagement(defaults: engagementDefaults)
        engagement.completedSummary(result: " ")
        for _ in 0..<5 { engagement.completedSummary(result: "Saved local result") }
        engagement.beginProcessing()
        guard engagement.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Prompt interrupted processing") }
        engagement.endProcessing()
        guard engagement.claimPrompt(isIdle: false) == nil,
              engagement.claimPrompt(isIdle: true) == .review,
              engagement.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Mac native review milestone is incorrect") }
        let relaunched = JotleyEngagement(defaults: engagementDefaults)
        for _ in 0..<3 { relaunched.completedSummary(result: "Saved summary") }
        guard relaunched.claimPrompt(isIdle: true) == nil,
              JotleyEngagement(defaults: engagementDefaults).claimPrompt(isIdle: true) == nil else { throw LocalError.message("Mac must not show a custom review prompt after the native request") }
        guard JotleyWebsiteTipPolicy.allowsTips(countryCode: "USA"),
              !JotleyWebsiteTipPolicy.allowsTips(countryCode: nil),
              !JotleyWebsiteTipPolicy.allowsTips(countryCode: "GBR") else {
            throw LocalError.message("Website tip eligibility must fail closed")
        }
        print("PASS: Mac review/support milestones wait for saved results and idle time, persist, and never repeat; web tips respect storefront eligibility.")

        guard let modelURL = Bundle.main.url(forResource: "JotleyNotes", withExtension: "momd"),
              let bundledModel = NSManagedObjectModel(contentsOf: modelURL),
              let model = bundledModel.copy() as? NSManagedObjectModel,
              let entity = model.entitiesByName["Note"] else { throw LocalError.message("Test model missing.") }
        entity.managedObjectClassName = NSStringFromClass(RoutingRefusedNote.self)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JotleyMacRouting-\(UUID())")
        let store = try SharedPersistenceController(root: root, model: model)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        guard let note = try store.create(title: "Keep selected note", text: "Earlier recorded words.") as? Note else {
            throw LocalError.message("Test note missing.")
        }
        let recorder = ProcessTapRecorder()
        let viewModel = NotesListViewModel(viewContext: store.context, recorder: recorder, persistenceController: store)
        viewModel.selectedNoteIDs = [note.objectID]
        viewModel.createBlankNote()
        viewModel.showSyncError = false
        await viewModel.startNewNote()
        guard viewModel.showSyncError, viewModel.selectedNoteIDs == [note.objectID],
              note.title == "Keep selected note", note.transcription == "Earlier recorded words.",
              note.noteType == "local", note.sourceURL == nil,
              !recorder.isRecording, !recorder.isBusy, viewModel.newNoteBeingRecorded == nil,
              try store.notes().count == 1,
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("Recordings").path) else {
            throw LocalError.message("Failed new-note creation changed or recorded the previous selection.")
        }
        let lease = try store.beginRecording(note); store.endRecording(lease: lease)
        print("PASS: failed new-note creation leaves the previous selection, transcript, metadata and recording state intact.")
        // Ordinary creation must still select a fresh note without changing the
        // prior note; this check does not request microphone access.
        RoutingRefusedNote.rejectsNewNotes = false
        viewModel.showSyncError = false
        viewModel.createBlankNote(text: "Fresh note content.", title: "New selected note")
        let notes = try store.notes()
        guard notes.count == 2, let created = notes.first(where: { $0.objectID != note.objectID }) as? Note,
              viewModel.selectedNoteIDs == [created.objectID], created.noteType == "local", created.sourceURL == nil,
              created.title == "New selected note", created.transcription == "Fresh note content.",
              note.noteType == "local", note.sourceURL == nil, note.transcription == "Earlier recorded words.",
              !viewModel.showSyncError,
              !recorder.isRecording, !recorder.isBusy, viewModel.newNoteBeingRecorded == nil,
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("Recordings").path) else {
            throw LocalError.message("Successful creation did not select a fresh note or preserve the previous note.")
        }
        let nextLease = try store.beginRecording(created); store.endRecording(lease: nextLease)
        print("PASS: successful creation selects a fresh note and preserves prior content.")
        try await verifyTranscriptEditing(note: created, store: store, viewModel: viewModel)
        try verifyRecovery()
        try await verifySummaryObserverLifetime(note: created)
        try verifyTranscriptRevisions(note: created)
        try await verifySummaryPresentation(note: created)
        try await verifyMacAskPresentation(note: created, store: store)
        try verifySearchEditingAlignment()
        try verifyGeneratedTitlePersistence(note: created, store: store)
        try await verifyAutomaticTags(note: created, store: store, viewModel: viewModel)
        try await verifyPlusStartsCaptureImmediately(store: store)
        try await verifyRecordingControlLayout()
        if ProcessInfo.processInfo.environment["JOTLEY_RUN_TITLE_TESTS"] == "1" {
            try await verifyOnDeviceTitle(note: created, viewModel: viewModel)
        }
    }
    @MainActor private static func verifyPlusStartsCaptureImmediately(store: SharedPersistenceController) async throws {
        _ = NSApplication.shared
        let recorder = ProcessTapRecorder()
        var calls: [UUID] = []
        recorder.simulatedStart = { _, id, _ in
            calls.append(id)
            try await Task.sleep(for: .milliseconds(150))
            throw LocalError.message("Injected capture-start rejection; no microphone was accessed.")
        }
        defer { recorder.simulatedStart = nil }
        let before = try store.notes().map(\.objectID)
        let viewModel = NotesListViewModel(viewContext: store.context, recorder: recorder, persistenceController: store)
        let start = Task { await viewModel.startNewNote() }
        for _ in 0..<30 { if !calls.isEmpty { break }; try await Task.sleep(for: .milliseconds(10)) }
        guard calls.count == 1 else { throw LocalError.message("New transcription must immediately call capture start.") }
        await viewModel.startNewNote()
        await start.value
        let created = try store.notes().filter { !before.contains($0.objectID) }
        guard calls.count == 1, created.count == 1, created.first?.localNoteID == calls.first,
              !recorder.starting, !recorder.isRecording else {
            throw LocalError.message("Repeated + taps created duplicate notes or left capture busy after failure.")
        }
        guard let newNote = created.first else { throw LocalError.message("New transcription note is missing.") }
        defer { try? store.deleteNoteAndAudio(newNote) }
        // The failure path must release its note lease, allowing a retry.
        let lease = try store.beginRecording(newNote); store.endRecording(lease: lease)
        print("PASS: Mac new-transcription route starts capture on a fresh note immediately, blocks duplicate starts and releases a failed start.")
    }
    @MainActor private static func verifyAutomaticTags(note: Note, store: SharedPersistenceController, viewModel: NotesListViewModel) async throws {
        let suite = "JotleyMacSummaryDelivery-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var delivered = 0
        let notifications = JotleySummaryNotifications(defaults: defaults, authorization: { .authorized },
            requestAuthorization: { true }, enqueue: { request in
                guard note.summary == "Finished design summary.", request.content.userInfo["noteID"] as? String == note.id?.uuidString else {
                    throw LocalError.message("A notification was sent before its summary was saved.")
                }
                delivered += 1
            }, isActive: { true })
        let viewModel = NotesListViewModel(viewContext: store.context, recorder: ProcessTapRecorder(), persistenceController: store, summaryNotifications: notifications)
        let other = try store.create(title: "Other tag bucket", text: "Related note")
        try store.saveNoteChanges(other, values: [:], replacingTags: ["AI", "Design"])
        try store.saveNoteChanges(note, values: [:], replacingTags: ["Outdated"])
        note.title = "Design review"
        viewModel.simulatedSummaryGeneration = { _ in "Finished design summary." }
        viewModel.simulatedTagGeneration = { _, _ in ["Artificial Intelligence", "AI Tools", "Design"] }
        defer { viewModel.simulatedSummaryGeneration = nil; viewModel.simulatedTagGeneration = nil; try? store.deleteNoteAndAudio(other) }
        await viewModel.generateSummary(note: note, templateKey: "Concise")
        guard note.summary == "Finished design summary.", note.tagNames == ["AI", "Design"], delivered == 1,
              (other.value(forKey: "tags") as? NSSet)?.count == 2 else {
            throw LocalError.message("Mac summary must replace old tags and reuse existing library buckets.")
        }
        viewModel.simulatedTagGeneration = { _, _ in throw LocalError.message("Injected tagging failure") }
        await viewModel.generateSummary(note: note, templateKey: "Concise")
        guard note.tagNames == ["AI", "Design"], note.summary == "Finished design summary.", delivered == 2 else {
            throw LocalError.message("Tagging failure must preserve existing tags and save the completed summary.")
        }
        viewModel.simulatedSummaryGeneration = { _ in throw LocalError.message("Injected summary failure") }
        await viewModel.generateSummary(note: note, templateKey: "Concise")
        guard delivered == 2, note.summary == "Finished design summary." else { throw LocalError.message("Failed summaries must not notify.") }
        viewModel.showSyncError = false
        print("PASS: Mac summaries replace tags and deliver local notifications only after saved results, including tag-warning results.")
    }
    @MainActor private static func verifySummaryFollowAndCancel(note: Note, store: SharedPersistenceController, viewModel: NotesListViewModel) async throws {
        note.summary = "Previously saved summary."
        try store.save()
        viewModel.simulatedSummaryGeneration = { _ in
            try await Task.sleep(for: .seconds(60))
            return "Cancelled test must never save"
        }
        let generation = Task { await viewModel.generateSummary(note: note, templateKey: "Concise") }
        await Task.yield()
        defer { generation.cancel(); viewModel.simulatedSummaryGeneration = nil }
        let host = NSHostingView(rootView: NoteDetailPlaceholderView(note: note, selectedTab: .constant(DetailTab.summary.rawValue), viewModel: viewModel)
            .environment(\.managedObjectContext, store.context).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
        defer { window.close() }
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        for count in [12, 36] {
            viewModel.streamingSummaryViewModel.summary = (1...count).map {
                "## Summary update \($0)\nMaya will review milestones Friday. Sam will test the next steps and share feedback with the team.\n"
            }.joined(separator: "\n")
            viewModel.objectWillChange.send()
            try await Task.sleep(for: .milliseconds(600))
            host.layoutSubtreeIfNeeded()
            guard let scroll = scrollViews(host).filter({ ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 100 }).max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }),
                  let document = scroll.documentView else { throw LocalError.message("Mac summary scroll fixture did not overflow.") }
            let visible = scroll.documentVisibleRect
            let distance = document.isFlipped ? document.bounds.maxY - visible.maxY : visible.minY - document.bounds.minY
            guard distance < 30 else { throw LocalError.message("Mac summary did not follow the bottom: \(distance) points away.") }
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("jotley-summary-mac-preview.png"))
            }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw LocalError.message("Mac summary snapshot unavailable") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var purplePixels = 0
            for y in (bitmap.pixelsHigh - 65)..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       color.blueComponent > color.greenComponent + 0.2,
                       color.redComponent > color.greenComponent + 0.1 { purplePixels += 1 }
                }
            }
            guard purplePixels > 300 else { throw LocalError.message("Cancel Generation is not visibly styled in the pinned footer.") }
        }
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("jotley-summary-mac-preview.png"))
        }
        window.makeKeyAndOrderFront(nil)
        guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { throw LocalError.message("Cancel key event unavailable") }
        if !window.performKeyEquivalent(with: escape) { window.sendEvent(escape) }
        try await Task.sleep(for: .milliseconds(300))
        guard !viewModel.isGeneratingSummary, note.summary == "Previously saved summary." else { throw LocalError.message("Pinned Cancel Generation did not cancel/preserve the saved summary.") }
        await generation.value
        print("PASS: real Mac summary view follows growing content and keeps a visible Cancel Generation footer; Escape cancels the actual task and preserves saved content.")
    }

    @MainActor private static func verifyTranscriptEditing(note: Note, store: SharedPersistenceController, viewModel: NotesListViewModel) async throws {
        note.transcription = "Original Mac words."
        note.summary = "Preserved summary."
        note.sourceURL = "local://preserved-recording"
        note.setTranscriptUtterances([TranscriptUtterance(text: "Original Mac words.", start: 1, end: 3)])
        try store.context.save()
        let host = NSHostingView(rootView: LocalMacTranscriptEditor(note: note, viewModel: viewModel).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 440), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        func textViews(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        guard let editor = textViews(host).first(where: { $0.isEditable }), editor.string == "Original Mac words." else {
            throw LocalError.message("Mac transcript editor did not open with editable saved words.")
        }
        editor.selectAll(nil); editor.insertText("Corrected Mac words.\n\nAnother paragraph.", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(150))
        window.makeKeyAndOrderFront(nil)
        guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36),
              window.performKeyEquivalent(with: key) else {
            throw LocalError.message("Mac transcript Save keyboard action was inaccessible.")
        }
        try await Task.sleep(for: .milliseconds(150))
        guard note.transcription == "Corrected Mac words.\n\nAnother paragraph.",
              note.transcriptUtterances.map(\.text) == ["Corrected Mac words.", "Another paragraph."],
              note.summary == "Preserved summary.", note.sourceURL == "local://preserved-recording" else {
            throw LocalError.message("Mac editor failed to persist corrected words or preserve existing content.")
        }
        do {
            try note.saveEditedTranscript("Stale draft", original: "Original Mac words.", in: store)
            throw LocalError.message("Mac accepted a stale transcript draft.")
        } catch let error as LocalError {
            guard error.localizedDescription.contains("changed while") else { throw error }
        }
        print("PASS: actual Mac transcript TextEditor and Save persist edited paragraphs, preserve summary/audio metadata and reject stale drafts.")
    }
    @MainActor private static func verifyMacAskPresentation(note: Note, store: SharedPersistenceController) async throws {
        let original = ThemeManager.shared.currentAppearanceMode
        defer { ThemeManager.shared.setAppearanceMode(original) }
        note.title = "Release planning"
        note.transcription = "Mina owns the release checklist. The team will test recording and review the new widgets."
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Jotley-Ask-Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var images: [Data] = []
        for mode in [AppearanceMode.dark, .light] {
            ThemeManager.shared.setAppearanceMode(mode)
            let host = NSHostingView(rootView: LocalMacAskNoteView(note: note).environmentObject(store))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 650),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host; window.orderFrontRegardless()
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            guard host.fittingSize.width >= 580, host.fittingSize.height >= 650,
                  let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw LocalError.message("Mac Ask AI did not mount at its intended readable size.")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let background = bitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB) else {
                throw LocalError.message("Mac Ask AI header was not rendered opaquely.")
            }
            let brightness = (background.redComponent + background.greenComponent + background.blueComponent) / 3
            guard mode == .light ? brightness > 0.8 : brightness < 0.3 else {
                throw LocalError.message("Mac Ask AI header does not follow its light/dark appearance.")
            }
            guard let png = bitmap.representation(using: .png, properties: [:]), !png.isEmpty else {
                throw LocalError.message("Mac Ask AI screen did not render.")
            }
            images.append(png)
            let file = output.appendingPathComponent("Mac-Ask-AI-\(mode == .dark ? "dark" : "light").png")
            try png.write(to: file)
            print("JOTLEY_MAC_ASK_SCREENSHOT \(file.path)")
        }
        guard images[0] != images[1] else { throw LocalError.message("Mac Ask AI did not update its appearance.") }
        print("PASS: actual Mac Ask AI screen mounts at 580×650 and renders distinct light/dark appearances.")
    }
    @MainActor private static func verifyGeneratedTitlePersistence(note: Note, store: SharedPersistenceController) throws {
        for title in [nil, "", "Untitled", "Untitled Note"] as [String?] {
            note.title = title
            try store.saveNoteChanges(note, values: note.generatedSummaryValues("Saved summary", template: "Meeting", generatedTitle: "Planning the Free Jotley Release"))
            store.context.refresh(note, mergeChanges: false)
            guard note.title == "Planning the Free Jotley Release", note.summary == "Saved summary", note.summaryType == "Meeting" else {
                throw LocalError.message("An untitled note did not persist its generated title with its summary.")
            }
        }
        note.title = "Untitled Note"
        guard note.shouldReplaceTitleFromGeneratedSummary() else { throw LocalError.message("Untitled fixture rejected generation.") }
        // A user can name the note while the model is still generating.
        note.title = "My own title"
        try store.saveNoteChanges(note, values: note.generatedSummaryValues("New summary", template: "Study", generatedTitle: "Model title"))
        store.context.refresh(note, mergeChanges: false)
        guard note.title == "My own title", note.summary == "New summary" else { throw LocalError.message("Title generation overwrote a user's concurrent edit.") }
        note.title = "Untitled Note"
        try store.saveNoteChanges(note, values: note.generatedSummaryValues("Summary survives title failure", template: "Concise", generatedTitle: nil))
        store.context.refresh(note, mergeChanges: false)
        guard note.title == "Untitled Note", note.summary == "Summary survives title failure" else {
            throw LocalError.message("A failed title discarded the successful summary.")
        }
        print("PASS: generated titles persist with summaries; user edits win; title failure retains the summary.")
    }
    @MainActor private static func verifyOnDeviceTitle(note: Note, viewModel: NotesListViewModel) async throws {
        note.title = "Untitled Note"
        note.transcription = "The team agreed to keep Jotley's existing interface and release version two as a free app. Recording and summaries will use installed Apple models. Optional iCloud sync will share notes between devices."
        note.summary = nil
        await viewModel.generateSummary(note: note, templateKey: "Concise")
        guard let title = note.title, !title.isEmpty, title != "Untitled Note", note.hasMeaningfulSummaryText,
              !viewModel.isGeneratingSummary, !viewModel.showSyncError else {
            throw LocalError.message("The actual on-device summary flow did not save both summary and title: \(viewModel.syncErrorMessage)")
        }
        let generatedTitle = title
        var progress: [LocalSummaryProgress] = [], snapshots: [String] = []
        let progressObserver = viewModel.streamingSummaryViewModel.$progress.sink { progress.append($0) }
        let streamObserver = viewModel.streamingSummaryViewModel.$summary.sink { if !$0.isEmpty { snapshots.append($0) } }
        defer { progressObserver.cancel(); streamObserver.cancel() }
        note.transcription = Array(repeating: note.transcription ?? "", count: 64).joined(separator: "\n\n")
        let began = Date()
        await viewModel.generateSummary(note: note, templateKey: "Meeting")
        guard note.title == generatedTitle, note.summaryType == LocalSummaryTemplate.meeting.key, !viewModel.showSyncError else {
            throw LocalError.message("Template regeneration changed an already named note or failed.")
        }
        guard progress.contains(.preparing),
              progress.contains(.writing), snapshots.count > 1, !viewModel.isGeneratingSummary else {
            throw LocalError.message("Mac long-note generation did not report preparation and live text before finishing.")
        }
        print("PASS: installed Apple model generated summary/title and regenerated a long transcript in \(Date().timeIntervalSince(began)) seconds with \(snapshots.count) live snapshots; preparation progress was reported and the title was preserved.")
    }
    @MainActor private static func verifyRecordingControlLayout() async throws {
        let original = ThemeManager.shared.currentAppearanceMode
        defer { ThemeManager.shared.setAppearanceMode(original) }
        for mode in [AppearanceMode.dark, .light] {
            ThemeManager.shared.setAppearanceMode(mode)
            var sizes: [NSSize] = []
            for timer in ["0m 28s", "180m 00s"] {
                let host = NSHostingView(rootView: NoteRecordingControls(timerText: timer, appIcon: nil,
                    audioLevel: 0, isPaused: timer == "180m 00s", onPause: {}, onStop: {}))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(100))
                sizes.append(host.fittingSize)
                window.close()
            }
            guard sizes[0].height == 52, sizes[1].height == 52, sizes[0].width > 196, sizes[1].width > sizes[0].width else {
                throw LocalError.message("Recording controls compressed Stop or failed to grow for a longer timer: \(sizes)")
            }
        }
        print("PASS: actual recording controls retain 52-point height and grow for long timers in light and dark mode.")
    }
    @MainActor private static func previewRecordingControls() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = RecordingLayoutDelegate()
        app.delegate = delegate
        ThemeManager.shared.setAppearanceMode(CommandLine.arguments.contains("--light") ? .light : .dark)
        let recorder = ProcessTapRecorder()
        let widget = RecordingWidgetViewModel(recorder: recorder)
        let host = NSHostingView(rootView: VStack(spacing: 22) {
            Text("Recording control layout — no audio capture")
            NoteRecordingControls(timerText: "0m 28s", appIcon: nil, audioLevel: 0, isPaused: false, onPause: {}, onStop: {})
            NoteRecordingControls(timerText: "180m 00s", appIcon: nil, audioLevel: 0, isPaused: true, onPause: {}, onStop: {})
            RecordingWidgetView(viewModel: widget)
        }.padding(30).foregroundColor(Color.themeTextPrimary).background(Color.themeContentBackground))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 450, height: 360),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Jotley Recording Layout"; window.isReleasedWhenClosed = false
        window.contentView = host; window.orderFrontRegardless()
        withExtendedLifetime(delegate) { app.run() }
    }
    @MainActor private static func verifyTranscriptRevisions(note: Note) throws {
        guard let context = note.managedObjectContext else { throw LocalError.message("Missing fixture context.") }
        for revision in 0..<100 {
            let text = "Revision \(revision) " + String(repeating: "你好📝", count: 128)
            note.transcription = text
            note.setTranscriptUtterances([TranscriptUtterance(id: "fixture", text: text, start: 12, end: 14, speaker: 3, confidence: 0.88)])
            let display = note.transcriptUtterances
            guard display.count == 1, display[0].text == text, display[0].start == 12,
                  display[0].end == 14, display[0].speaker == 3, display[0].confidence == 0.88 else {
                throw LocalError.message("A transcript revision returned stale text or timing metadata.")
            }
        }
        try context.save()
        let expected = note.transcriptUtterances
        let otherContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        otherContext.persistentStoreCoordinator = context.persistentStoreCoordinator
        guard let other = try otherContext.existingObject(with: note.objectID) as? Note else {
            throw LocalError.message("Second-context fixture missing.")
        }
        other.transcription = "Unsaved text from another context."
        other.setTranscriptUtterances([TranscriptUtterance(text: other.transcription!, start: 42, end: 44)])
        guard other.transcriptUtterances.first?.start == 42, note.transcriptUtterances == expected else {
            throw LocalError.message("A different context replaced this note's display data.")
        }
        note.transcription = "Fresh manual fallback."
        note.setTranscriptUtterances([])
        guard note.transcriptUtterances.map(\.text) == ["Fresh manual fallback."] else {
            throw LocalError.message("Clearing structured transcript left stale display text.")
        }
        note.transcription = "Updated fallback after unreadable metadata."
        note.setValue("{", forKey: "transcriptUtterancesJSON")
        guard note.transcriptUtterances.map(\.text) == [note.transcription!] else {
            throw LocalError.message("Unreadable metadata reused an obsolete display revision.")
        }
        context.rollback()
        guard note.transcriptUtterances == expected else { throw LocalError.message("Rollback did not restore displayed transcript metadata.") }
        print("PASS: repeated Unicode transcript revisions, independent contexts, clearing, unreadable metadata and rollback display current content.")
    }
    @MainActor private static func verifySummaryObserverLifetime(note: Note) async throws {
        _ = NSApplication.shared
        let state = SummaryObserverState()
        let host = NSHostingView(rootView: AnyView(SummaryObserverView(note: note, state: state)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        NotificationCenter.default.post(name: Notification.Name("SummaryGenerationComplete"), object: nil,
            userInfo: ["noteID": note.objectID, "summary": "Mounted summary result."])
        try await Task.sleep(for: .milliseconds(100))
        state.generating = true
        try await Task.sleep(for: .milliseconds(450))
        guard state.generating else {
            throw LocalError.message("An earlier completion reset a newer summary generation.")
        }
        guard state.summary == "Mounted summary result." else {
            throw LocalError.message("The mounted summary observer fixture did not receive completion.")
        }
        host.rootView = AnyView(EmptyView())
        try await Task.sleep(for: .milliseconds(350))
        NotificationCenter.default.post(name: Notification.Name("SummaryGenerationComplete"), object: nil,
            userInfo: ["noteID": note.objectID, "summary": "Retired summary result."])
        try await Task.sleep(for: .milliseconds(450))
        guard state.summary == "Mounted summary result." else {
            throw LocalError.message("A retired Mac summary view still receives completion notifications.")
        }
        print("PASS: summary completion preserves a newer generation and retired views release subscriptions.")
    }
    @MainActor private static func verifySummaryPresentation(note: Note) async throws {
        let fenced = "```markdown\n# Meeting Notes\n\n**Decision:** Keep the original app.\n- Record live audio.\n```"
        let expected = "# Meeting Notes\n\n**Decision:** Keep the original app.\n- Record live audio."
        guard LocalSummary.markdownForDisplay(fenced) == expected,
              LocalSummary.markdownForDisplay("```md\n# Streaming") == "# Streaming",
              LocalSummary.markdownForDisplay("# Notes\n```swift\nlet x = 1\n```") == "# Notes\n```swift\nlet x = 1\n```" else {
            throw LocalError.message("Summary normalization lost formatting or intentional code.")
        }
        let state = SummaryObserverState(); state.summary = fenced
        let host = NSHostingView(rootView: AnyView(SummaryObserverView(note: note, state: state)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        // A titled window can become key, so text focus behaves as it does in the app.
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func textViews(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        try await Task.sleep(for: .milliseconds(350))
        // The structured view renders SwiftUI text, so check the sections it draws
        // and that no Markdown editor or raw syntax is shown.
        let structured = StructuredSummary(ParsedNoteMarkdown.rendering(fenced))
        let item = structured.sections.first?.items.first
        guard !textViews(host).contains(where: { $0.isEditable }),
              structured.sections.map(\.title) == ["Meeting Notes"],
              structured.sections.first?.paragraphs.map({ String($0.text.characters) }) == ["Decision: Keep the original app."],
              item.map({ String($0.body.characters) }) == "Record live audio." else {
            throw LocalError.message("Fenced summary displayed as code instead of formatted text.")
        }
        state.summary = "## Summary\nKeep the original app.\n\n## Key Points\n- Record live audio."
        try await Task.sleep(for: .milliseconds(200))
        state.inlineEdit = 1
        try await Task.sleep(for: .milliseconds(350))
        guard state.inlineEdit == 0, state.rawMarkdown else {
            throw LocalError.message("Explicit summary editing was not consumed.")
        }
        // Edit the Markdown the way a person types it, then leave the editor.
        guard let editor = textViews(host).first(where: { $0.isEditable }),
              editor.string.contains("- Record live audio.") else {
            throw LocalError.message("The summary editor did not show the Markdown.")
        }
        window.makeFirstResponder(editor)
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        let addition = "\n\n## Action Items\n- **Maya**: Share the edited summary."
        if editor.shouldChangeText(in: end, replacementString: addition) {
            editor.textStorage?.replaceCharacters(in: end, with: addition)
            editor.didChangeText()
        }
        try await Task.sleep(for: .milliseconds(350))
        try await Task.sleep(for: .milliseconds(350))
        let edited = StructuredSummary(ParsedNoteMarkdown.rendering(state.summary))
        let editedItem = edited.sections.last?.items.first
        let editedLabel = editedItem?.label.map { String($0.characters) }
        let editedBody = editedItem.map { String($0.body.characters) }
        guard edited.sections.last?.title == "Action Items",
              editedLabel == "Maya", editedBody == "Share the edited summary." else {
            throw LocalError.message("Typed summary Markdown was not saved as structured sections: label=\(editedLabel ?? "nil") body=\(editedBody ?? "nil") sections=\(edited.sections.map(\.title))")
        }
        print("PASS: Markdown typed into the Mac summary editor is saved and parses into structured sections.")
        state.summary = fenced
        try await Task.sleep(for: .milliseconds(200))
        state.generating = true
        try await Task.sleep(for: .milliseconds(350))
        state.summary = fenced; state.generating = false
        try await Task.sleep(for: .milliseconds(350))
        guard !state.rawMarkdown, !textViews(host).contains(where: { $0.isEditable }) else {
            throw LocalError.message("Template regeneration reopened the Markdown editor.")
        }
        host.rootView = AnyView(EmptyView())
        try await Task.sleep(for: .milliseconds(100))
        host.rootView = AnyView(SummaryObserverView(note: note, state: state))
        try await Task.sleep(for: .milliseconds(350))
        guard !state.rawMarkdown, !textViews(host).contains(where: { $0.isEditable }) else {
            throw LocalError.message("Remounting the summary replayed an old edit request.")
        }
        let originalAppearance = ThemeManager.shared.currentAppearanceMode
        defer { ThemeManager.shared.setAppearanceMode(originalAppearance) }
        for mode in [AppearanceMode.dark, .light, .dark, .light, .dark, .light] {
            ThemeManager.shared.setAppearanceMode(mode)
            try await Task.sleep(for: .milliseconds(200))
            guard host.fittingSize.height > 60, !textViews(host).contains(where: { $0.isEditable }) else {
                throw LocalError.message("Rendered summary disappeared during theme switching.")
            }
            // The structured view reads these colors on every render.
            guard let rgb = NSColor(Color.themeTextPrimary).usingColorSpace(.deviceRGB) else {
                throw LocalError.message("Summary text color missing.")
            }
            let expected: CGFloat = mode == .dark ? 0.85 : 0.1
            guard abs(rgb.redComponent - expected) < 0.04,
                  abs(rgb.greenComponent - expected) < 0.04,
                  abs(rgb.blueComponent - expected) < 0.04 else {
                throw LocalError.message("Summary retained stale color after switching to \(mode.rawValue): \(rgb).")
            }
        }
        print("PASS: six repeated light/dark switches keep the summary rendered with current text colors and never reopen the editor.")
        print("PASS: fenced summaries render as formatted text; regeneration and remounting never replay Markdown editing.")
    }
    @MainActor private static func verifySearchEditingAlignment() throws {
        let field = ThemedNSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 36))
        field.cell = ThemedTextFieldCell(textCell: "")
        field.isEditable = true; field.isSelectable = true; field.isBordered = false
        field.font = .systemFont(ofSize: 14); field.maxDisplayLines = 1; field.configureLineWrapping()
        let window = NSWindow(contentRect: field.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = field
        defer { window.close() }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView,
              let cell = field.cell as? ThemedTextFieldCell else { throw LocalError.message("Search field editor missing.") }
        let drawn = cell.drawingRect(forBounds: field.bounds)
        let edited = field.convert(editor.bounds, from: editor)
        guard abs(drawn.midY - field.bounds.midY) <= 1,
              abs(edited.midY - field.bounds.midY) <= 2 else {
            throw LocalError.message("Search drawing/editor are not vertically centered: \(drawn), \(edited).")
        }
        print("PASS: search text and its active AppKit field editor are centered in the 36-point control.")
    }


    @MainActor private static func verifyRecovery() throws {
        let app = LocalAppModel.shared
        guard Bundle.main.bundleIdentifier == "com.protomota.jotley.mac-routing-tests",
              let store = app.store, store.ready,
              store.root.path.contains("/com.protomota.jotley.mac-routing-tests/") else {
            throw LocalError.message("Recovery checks require the separate test sandbox.")
        }
        guard try store.notes().isEmpty else { throw LocalError.message("Preserve unexpected test sandbox notes.") }
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: store.root)
        }
        for complete in [false, true] {
            let note = try store.create(title: "Deleted recovery fixture")
            guard let id = note.localNoteID else { throw LocalError.message("Recovery fixture has no ID.") }
            let segment = store.root.appendingPathComponent("Recordings/\(id.uuidString)/segment")
            do {
                let writer = try DurableAudioWriter(directory: segment, noteID: id, sampleRate: 16000)
                try writer.append(Data(repeating: 0, count: 64000))
                if complete { try writer.close() }
            }
            try app.reload() // Keep a stale view-model snapshot across deletion.
            store.context.delete(note); try store.save()
            try app.recoverRecordings(); try app.recoverRecordings()
            guard try store.notes().isEmpty, app.notes.isEmpty,
                  try DurableAudioWriter.frameCount(at: segment) == 16000,
                  FileManager.default.fileExists(atPath: segment.appendingPathComponent("audio.caf").path) || complete else {
                throw LocalError.message("Mac recovery recreated a deleted note or lost its raw audio.")
            }
        }
        print("PASS: completed and unfinished local audio never recreate deleted Mac notes.")
        let kept = try store.create(title: "Keep recovery title", text: "Keep recovery words.")
        guard let id = kept.localNoteID else { throw LocalError.message("Recovery fixture has no ID.") }
        let segment = store.root.appendingPathComponent("Recordings/\(id.uuidString)/segment")
        do {
            let writer = try DurableAudioWriter(directory: segment, noteID: id, sampleRate: 16000)
            try writer.append(Data(repeating: 0, count: 64000))
        }
        try app.reload(); try app.recoverRecordings(); try app.recoverRecordings()
        guard try store.notes().count == 1, kept.text("title") == "Keep recovery title",
              kept.text("transcription") == "Keep recovery words.",
              kept.text("sourceURL") == "Recordings/\(id.uuidString)",
              try DurableAudioWriter.manifest(at: segment).complete,
              try DurableAudioWriter.frameCount(at: segment) == 16000,
              FileManager.default.fileExists(atPath: segment.appendingPathComponent("audio.caf").path) else {
            throw LocalError.message("Existing Mac note recovery lost content or audio.")
        }
        print("PASS: interrupted Mac recovery preserves an existing note and its complete raw audio.")
    }
}
#else
import XCTest

final class JotleyLocalUITests: XCTestCase {
    func testOriginalInterfaceCreatesAndPersistsLocalNoteWithoutAccount() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["notesListSearchField"].waitForExistence(timeout: 15))
        let filter = app.buttons["notesListTagFilterButton"]
        XCTAssertEqual(filter.frame.width, 36, accuracy: 1)
        // SwiftUI/macOS accessibility height includes toolbar/container extents.
        // Compare visible heights in the app; the square filter width is reliable.
        XCTAssertTrue(app.toolbars.buttons["Hide Sidebar"].exists)
        XCTAssertFalse(app.buttons["Sign in"].exists)
        let count = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notesListNoteRow-")).count
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["New Note"].click()
        XCTAssertTrue(app.buttons["notesListNoteRow-\(count)"].waitForExistence(timeout: 5), "New Note must create an additional note")
        let title = app.textFields["noteDetailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let name = "Local UI check " + UUID().uuidString
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText(name)
        title.typeKey(.return, modifierFlags: [])
        title.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(app.buttons["notesListNoteRow-0"].exists)
        app.terminate()
        app.launch()
        let search = app.textFields["notesListSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.click(); search.typeText(name)
        XCTAssertTrue(app.buttons["notesListNoteRow-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign in"].exists)
    }
}
#endif
