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

private struct MacTranscriptionPreviewRoot: View {
    @ObservedObject var model: NotesListViewModel
    @State private var speechCount = 30
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Notes").font(.title.bold())
                Button("Active transcript") { model.jumpToActiveRecordingNote() }
                Button("Browse another note") {
                    if let other = try? model.viewContext.fetch(Note.fetchRequest()).first(where: { $0 != model.newNoteBeingRecorded }) {
                        model.toggleSelection(for: other)
                    }
                }
                Button("Append speech") {
                    speechCount += 1
                    var speech = LocalTranscript()
                    for index in 1...speechCount {
                        speech.accept(text: "Segment \(index). This synthetic passage checks that you can read earlier text without incoming words pulling your scroll position away.", start: Double(index * 15), end: Double(index * 15 + 8), final: true)
                    }
                    model.recorder.publishSimulatedLiveTranscript(speech)
                }
                Spacer()
            }.padding(20).frame(width: 200)
            Divider()
            if let id = model.selectedNoteIDs.first,
               let note = try? model.viewContext.existingObject(with: id) as? Note {
                NoteDetailPlaceholderView(note: note, selectedTab: $model.selectedDetailTab, viewModel: model)
                    .id(note.objectID)
                    .environmentObject(model.persistenceController)
                    .environment(\.managedObjectContext, model.viewContext)
                    .overlay(alignment: .bottom) {
                        if model.recorder.isRecording { MacCompactTranscriptionBar(viewModel: model).padding(12) }
                    }
            }
        }.frame(width: 1000, height: 760)
            .foregroundStyle(Color.themeTextPrimary).background(Color.themeBackground)
    }
}

private struct MacSupportPreviewRoot: View {
    @ObservedObject var engagement: JotleyEngagement
    @State private var showingSupport = false
    @State private var lastURL = "No external links opened."
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Jotley support preview").font(.largeTitle.bold())
            Text("Isolated preferences and synthetic summaries. Link clicks are intercepted; no browser or email is opened.")
            Text("\(engagement.completedActions) saved summaries · \(engagement.clickedActions.count) saved button clicks · automatic reminders \(engagement.automaticRemindersStopped ? "off" : "on")")
                .accessibilityIdentifier("supportPreviewCounts")
            Button("Save another summary") {
                engagement.completedSummary(result: "Synthetic saved summary")
                print("SUPPORT_PREVIEW pending=\(engagement.hasPendingSupportReminder) active=\(NSApp.isActive) main=\(NSApp.mainWindow != nil) key=\(NSApp.keyWindow != nil)")
            }
            Button("Open support from Settings") { showingSupport = true }
            Text(lastURL)
            Spacer()
        }.padding(30).frame(width: 840, height: 860)
            .foregroundStyle(Color.themeTextPrimary).background(Color.themeBackground)
            .modifier(JotleyEngagementPrompts(isIdle: !showingSupport, engagement: engagement))
            .modifier(JotleySupportCardPresentation(isPresented: $showingSupport, engagement: engagement))
            .environment(\.scenePhase, .active)
            .environment(\.openURL, OpenURLAction { url in
                lastURL = "Intercepted click: \(url.absoluteString)"
                return .handled
            })
    }
}

/// Compile this existing source against the built app with the harness flag to
/// exercise its actual view model without adding a second implementation.
@main private struct MacRoutingHarness {
    @MainActor static func main() {
        UserDefaults.standard.set(false, forKey: JotleySummaryNotifications.enabledKey)
        if CommandLine.arguments.contains("--layout-preview") {
            previewRecordingControls()
            return
        }
        if CommandLine.arguments.contains("--detail-fixes-preview") {
            previewCompletedTranscript()
            return
        }
        if CommandLine.arguments.contains("--summary-progress-preview") {
            previewSummaryProgress()
            return
        }
        if CommandLine.arguments.contains("--support-preview") {
            previewSupportCard()
            return
        }
        Task { @MainActor in
            await runChecks()
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor private static func runChecks() async {
        do {
            try await verifyLanguageChoices()
            if CommandLine.arguments.contains("--languages-only") { return }
            if CommandLine.arguments.contains("--compact-only") {
                guard let store = LocalAppModel.shared.store else { throw LocalError.message("Preview store unavailable") }
                try await verifyCompactTranscription(store: store)
            } else if CommandLine.arguments.contains("--summary-scroll-only") {
                guard let store = LocalAppModel.shared.store,
                      let note = try store.create(title: "Summary scroll fixture", text: "Maya reviews Friday.") as? Note else { throw LocalError.message("Summary scroll store unavailable") }
                defer { try? store.deleteNoteAndAudio(note) }
                let model = NotesListViewModel(viewContext: store.context, recorder: LocalAppModel.shared.recorder, persistenceController: store)
                try await verifySummaryFollowAndCancel(note: note, store: store, viewModel: model)
            } else { try await verifyRouting() }
        }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor private static func verifyLanguageChoices() async throws {
        let locales = ["en-US", "en-GB", "fr-FR", "fr-CA", "zh-CN", "zh-TW", "zh-HK", "ar-SA", "ru-RU", "hi-IN", "pl-PL"].map { Locale(identifier: $0) }
        let choices = LocalSpeech.languages(speechLocales: locales, preferredLocale: Locale(identifier: "en-GB"),
                                           supportsLocale: { $0.language.languageCode?.identifier != "fr" })
        guard Set(choices.map(\.id)) == ["en-GB", "zh-CN", "zh-TW"],
              LocalSpeech.selectedLanguage(locale: Locale(identifier: "en-AU"), in: choices)?.id == "en-GB",
              LocalSpeech.selectedLanguage(locale: Locale(identifier: "zh-HK"), in: choices)?.id == "zh-TW",
              LocalSpeech.selectedLanguage(locale: Locale(identifier: "ar-SA"), in: choices) == nil else {
            throw LocalError.message("Language intersection, regional deduplication or legacy selection failed")
        }
        let actual = await LocalSpeech.languages()
        guard !actual.isEmpty, actual.count <= 16,
              Set(actual.compactMap { LocalSpeech.languageKey(for: Locale(identifier: $0.id)) }).count == actual.count,
              actual.allSatisfy({ LocalSpeech.supportsIntelligence(locale: Locale(identifier: $0.id)) }) else {
            throw LocalError.message("The runtime picker offered an unsupported or duplicate language")
        }
        for id in ["ar-SA", "ru-RU", "hi-IN", "pl-PL"] {
            let ready = await LocalSpeech.readiness(locale: Locale(identifier: id))
            guard ready.status == .unsupported, ready.configuration == nil, !ready.needsSetup else {
                throw LocalError.message("A legacy unsupported language reached speech setup")
            }
            do { _ = try await LocalSpeech.configuration(locale: Locale(identifier: id)) }
            catch { continue }
            throw LocalError.message("A legacy unsupported language reached capture configuration")
        }
        print("PASS: speech/Intelligence intersection, regional deduplication, Chinese scripts, legacy language rejection; runtime choices (\(actual.count)): \(actual.map { "\($0.name) [\($0.id)]" }.joined(separator: ", ")).")
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
        let engagement = JotleyEngagement(defaults: engagementDefaults, usesCustomReminders: false)
        engagement.completedSummary(result: " ")
        for _ in 0..<5 { engagement.completedSummary(result: "Saved local result") }
        engagement.beginProcessing()
        guard engagement.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Prompt interrupted processing") }
        engagement.endProcessing()
        guard engagement.claimPrompt(isIdle: false) == nil,
              engagement.claimPrompt(isIdle: true) == .review,
              engagement.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Mac native review milestone is incorrect") }
        let relaunched = JotleyEngagement(defaults: engagementDefaults, usesCustomReminders: false)
        for _ in 0..<3 { relaunched.completedSummary(result: "Saved summary") }
        guard relaunched.claimPrompt(isIdle: true) == nil,
              JotleyEngagement(defaults: engagementDefaults, usesCustomReminders: false).claimPrompt(isIdle: true) == nil else { throw LocalError.message("Mac must not show a custom review prompt after the native request") }
        try verifySupportReminders()
        try await verifySupportCardLayout()
        guard JotleyWebsiteTipPolicy.allowsTips(countryCode: "USA"),
              !JotleyWebsiteTipPolicy.allowsTips(countryCode: nil),
              !JotleyWebsiteTipPolicy.allowsTips(countryCode: "GBR") else {
            throw LocalError.message("Website tip eligibility must fail closed")
        }
        print("PASS: Store review requests remain native and one-time; Store website tips respect storefront eligibility.")

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
        try verifySummaryStyleRendering()
        try await verifyMacAskPresentation(note: created, store: store)
        try verifySearchEditingAlignment()
        try verifyGeneratedTitlePersistence(note: created, store: store)
        try await verifyAutomaticTags(note: created, store: store, viewModel: viewModel)
        try await verifyPlusStartsCaptureImmediately(store: store)
        try await verifyRecordingControlLayout()
        try await verifyCompactTranscription(store: store)
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
        guard calls.count == 1, viewModel.newNoteBeingRecorded != nil else { throw LocalError.message("New transcription must immediately start capture without a modal.") }
        await viewModel.startNewNote()
        await start.value
        let created = try store.notes().filter { !before.contains($0.objectID) }
        guard calls.count == 1, created.count == 1, created.first?.localNoteID == calls.first,
              !recorder.starting, !recorder.isRecording, viewModel.newNoteBeingRecorded == nil else {
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
        note.transcription = String(repeating: "AI supports design and helps the team explore useful interface ideas. ", count: 5)
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
        guard !note.tagNames.isEmpty, note.tagNames.count <= 2, note.summary == "Finished design summary.", delivered == 2, !viewModel.showSyncError else {
            throw LocalError.message("Tagging failure must use local fallback tags and save the completed summary.")
        }
        viewModel.simulatedSummaryGeneration = { _ in throw LocalError.message("Injected summary failure") }
        await viewModel.generateSummary(note: note, templateKey: "Concise")
        guard delivered == 2, note.summary == "Finished design summary.", viewModel.showSyncError else { throw LocalError.message("Failed summaries must not notify.") }
        viewModel.showSyncError = false
        print("PASS: Mac summaries replace tags and deliver local notifications only after saved results, including silent fallback tags and genuine summary failures.")
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
            let content = LocalMacAskNoteView(note: note).environmentObject(store)
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 650),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host; window.orderFrontRegardless()
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            guard host.fittingSize.width >= 580, host.fittingSize.height >= 650 else {
                throw LocalError.message("Mac Ask AI did not mount at its intended readable size.")
            }
            let renderer = ImageRenderer(content: content.frame(width: 580, height: 650))
            renderer.proposedSize = ProposedViewSize(width: 580, height: 650)
            guard let rendered = renderer.cgImage else { throw LocalError.message("Mac Ask AI snapshot failed.") }
            let bitmap = NSBitmapImageRep(cgImage: rendered)
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
    @MainActor private static func verifySummaryStyleRendering() throws {
        let suite = "JotleySummaryStyle-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let theme = ThemeManager.shared
        let previousMode = theme.currentAppearanceMode
        let previousColor = theme.currentThemeColor
        defer {
            defaults.removePersistentDomain(forName: suite)
            theme.setAppearanceMode(previousMode); theme.setThemeColor(previousColor)
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Jotley-Summary-Style-Proof")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = "## Summary\nA clear plan for Friday.\n\n## Next Steps\n- **Maya:** Review the launch."
        theme.setThemeColor(.purple)
        for mode in [AppearanceMode.light, .dark] {
            theme.setAppearanceMode(mode)
            for style in SummaryDisplayStyle.allCases {
                defaults.set(style.rawValue, forKey: SummaryDisplayStyle.preferenceKey)
                let content = StructuredSummaryView(content: source).defaultAppStorage(defaults)
                    .frame(width: 520).padding(24).background(Color.themeBackground)
                let renderer = ImageRenderer(content: content)
                guard let image = renderer.cgImage else { throw LocalError.message("Summary style did not render.") }
                let bitmap = NSBitmapImageRep(cgImage: image)
                var accentPixels = 0
                for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if pixel.redComponent > pixel.greenComponent + 0.08,
                       pixel.blueComponent > pixel.greenComponent + 0.08 { accentPixels += 1 }
                } }
                guard style == .standard ? accentPixels == 0 : accentPixels > 100 else {
                    throw LocalError.message("Summary appearance preference was not reflected in the rendered content: \(style.title), \(accentPixels).")
                }
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: output.appendingPathComponent("Mac-\(style.rawValue)-\(mode.rawValue).png"))
                }
            }
        }
        print("PASS: actual shared Mac summaries honor the saved Cards/Standard Text preference in light and dark; Standard Text contains neutral text without colored cards.")
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
    @MainActor private static func verifyCompactTranscription(store: SharedPersistenceController) async throws {
        let recorder = ProcessTapRecorder()
        var speech = LocalTranscript()
        speech.accept(text: "Keep live transcription running while browsing other notes.", start: 0, end: 8, final: true)
        recorder.simulatedStart = { _, _, _ in recorder.beginSimulatedLiveTranscription(speech) }
        let model = NotesListViewModel(viewContext: store.context, recorder: recorder, persistenceController: store)
        await model.startNewNote()
        guard recorder.isRecording, let note = model.newNoteBeingRecorded else { throw LocalError.message("Capture did not start immediately.") }
        if CommandLine.arguments.contains("--compact-only") {
        let host = NSHostingView(rootView: MacTranscriptionPreviewRoot(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        guard let scroll = scrollViews(in: host).first(where: { $0.bounds.height > 300 }) else {
            throw LocalError.message("The actual transcript scroll view is missing.")
        }
        let frame = scroll.convert(scroll.bounds, to: host)
        let bottomGap = host.isFlipped ? host.bounds.maxY - frame.maxY : frame.minY - host.bounds.minY
        guard abs(bottomGap) < 2 else { throw LocalError.message("Scrollbar stops above the window bottom: \(bottomGap) points.") }
        print("PASS: actual transcript scroll view reaches the window bottom under the floating capsule.")
        }
        let other = try store.create(title: "Browse while transcribing", text: "Keep this note unchanged.") as! Note
        other.summary = "Existing summary"; try store.save()
        defer { recorder.simulatedStart = nil; try? store.deleteNoteAndAudio(note); try? store.deleteNoteAndAudio(other) }
        model.toggleSelection(for: other)
        var updated = speech
        updated.accept(text: "These words belong only to the active transcription.", start: 10, end: 18, final: true)
        recorder.publishSimulatedLiveTranscript(updated)
        guard recorder.isRecording, model.selectedNoteIDs == [other.objectID],
              note.transcription == updated.text, other.transcription == "Keep this note unchanged." else {
            throw LocalError.message("Browsing interrupted capture or sent speech to the wrong note.")
        }
        await model.resumeTranscription()
        guard model.isTranscriptionPaused, model.selectedNoteIDs == [other.objectID] else { throw LocalError.message("Pause changed the selected note.") }
        await model.resumeTranscription()
        guard !model.isTranscriptionPaused else { throw LocalError.message("Continue did not resume capture.") }
        await model.stopRecording()
        guard !recorder.isRecording, model.newNoteBeingRecorded == nil,
              model.selectedNoteIDs == [other.objectID], model.selectedDetailTab == DetailTab.summary.rawValue,
              note.transcription == updated.text else { throw LocalError.message("Stop failed to save or displaced the browsed note.") }
        let saved = note.transcription
        recorder.publishSimulatedLiveTranscript(speech)
        guard note.transcription == saved else { throw LocalError.message("Stopped transcript still accepts live words.") }
        recorder.simulatedStart = { _, _, _ in recorder.beginSimulatedLiveTranscription(speech) }
        await model.resumeTranscriptionOnNote(note: note)
        model.jumpToActiveRecordingNote()
        guard model.selectedNoteIDs == [note.objectID], model.selectedDetailTab == DetailTab.transcript.rawValue else { throw LocalError.message("Return to active transcript failed.") }
        await model.stopRecording()
        guard note.transcription == [updated.text, speech.text].joined(separator: " ") else { throw LocalError.message("Continuing replaced the saved transcript.") }
        var follow = MacTranscriptFollowState()
        guard follow.shouldFollow else { throw LocalError.message("Live transcript must initially follow.") }
        follow.bottomChanged(false)
        follow.scrollPhaseChanged(isUserScrolling: false)
        guard follow.shouldFollow else { throw LocalError.message("Layout/programmatic phases disabled initial following.") }
        follow.scrollPhaseChanged(isUserScrolling: true)
        follow.bottomChanged(false)
        guard !follow.shouldFollow else { throw LocalError.message("Follow interrupted an active user scroll.") }
        follow.scrollPhaseChanged(isUserScrolling: false)
        guard !follow.shouldFollow else { throw LocalError.message("Follow resumed while reading earlier text.") }
        follow.bottomChanged(true)
        guard follow.shouldFollow else { throw LocalError.message("Returning to bottom did not restore following.") }
        follow.scrollPhaseChanged(isUserScrolling: true); follow.bottomChanged(true)
        guard !follow.shouldFollow else { throw LocalError.message("Dragging at the bottom must still suspend following.") }
        follow.scrollPhaseChanged(isUserScrolling: false)
        guard follow.shouldFollow else { throw LocalError.message("Finishing a scroll at bottom must resume following.") }
        print("PASS: compact Mac controls allow browsing during capture; speech stays on its note; pause/continue/stop save correctly without changing the browsed note; manual scrolling suspends following until the bottom.")
    }
    @MainActor private static func verifyRecordingControlLayout() async throws {
        let original = ThemeManager.shared.currentAppearanceMode
        defer { ThemeManager.shared.setAppearanceMode(original) }
        for mode in [AppearanceMode.dark, .light] {
            ThemeManager.shared.setAppearanceMode(mode)
            var sizes: [NSSize] = []
            for timer in ["0m 28s", "180m 00s"] {
                let host = NSHostingView(rootView: MacTranscriptionControls(timerText: timer, isPaused: timer == "180m 00s", onPause: {}, onStop: {}))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(100))
                sizes.append(host.fittingSize)
                window.close()
            }
            guard sizes[0].height == 52, sizes[1].height == 52, sizes[0].width >= 200 && sizes[0].width < 400, sizes[1].width >= sizes[0].width else {
                throw LocalError.message("Recording controls compressed Stop or failed to grow for a longer timer: \(sizes)")
            }
        }
        print("PASS: actual recording controls retain 52-point height and fit long timers in light and dark mode.")
    }
    @MainActor private static func previewRecordingControls() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = RecordingLayoutDelegate(); app.delegate = delegate
        ThemeManager.shared.setAppearanceMode(.dark)
        app.appearance = NSAppearance(named: .darkAqua)
        let store = LocalAppModel.shared.store!
        let recorder = ProcessTapRecorder()
        var speech = LocalTranscript()
        for index in 1...30 {
            speech.accept(text: "Segment \(index). This synthetic passage checks that you can read earlier text without incoming words pulling your scroll position away.", start: Double(index * 15), end: Double(index * 15 + 8), final: true)
        }
        recorder.simulatedStart = { _, _, _ in recorder.beginSimulatedLiveTranscription(speech) }
        let model = NotesListViewModel(viewContext: store.context, recorder: recorder, persistenceController: store)
        _ = try! store.create(title: "Another note", text: "You can browse this note while transcription continues.")
        let host = NSHostingView(rootView: MacTranscriptionPreviewRoot(model: model))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 100, width: 840, height: 760),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Jotley Transcription Preview"; window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        Task { await model.startNewNote() }
        withExtendedLifetime(delegate) { app.run() }
    }
    @MainActor private static func verifySupportReminders() throws {
        let suite = "JotleySupportReminders-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: JotleyEngagement.reviewKey)
        defaults.set("keep-my-notes", forKey: "unrelated-notes-fixture")
        let state = JotleyEngagement(defaults: defaults, usesCustomReminders: true)
        state.completedSummary(result: " ")
        for _ in 0..<4 { state.completedSummary(result: "Saved result") }
        guard state.completedActions == 4, state.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Support appeared before five completed summaries.") }
        state.completedSummary(result: "Fifth saved result")
        state.beginProcessing()
        guard state.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Support interrupted model processing.") }
        state.endProcessing()
        guard state.claimPrompt(isIdle: false) == nil, state.claimPrompt(isIdle: true) == .support,
              state.claimPrompt(isIdle: true) == nil,
              JotleyEngagement(defaults: defaults, usesCustomReminders: true).claimPrompt(isIdle: true) == nil else {
            throw LocalError.message("Support must claim one idle presentation across windows and relaunch.")
        }
        for _ in 0..<4 {
            state.completedSummary(result: "Later saved result")
            guard state.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Support repeated before five more summaries.") }
        }
        state.completedSummary(result: "Tenth saved result")
        guard state.claimPrompt(isIdle: true) == .support else { throw LocalError.message("A dismissal must allow another reminder five summaries later.") }
        state.completedSummary(result: "Manual support result")
        state.supportCardOpened()
        guard JotleyEngagement(defaults: defaults, usesCustomReminders: true).claimPrompt(isIdle: true) == nil else { throw LocalError.message("Closing manual support reopened the same reminder.") }

        for action in JotleyEngagement.Action.allCases {
            defaults.removeObject(forKey: JotleyEngagement.clicksKey)
            defaults.removeObject(forKey: JotleyEngagement.stoppedKey)
            let clicked = JotleyEngagement(defaults: defaults, usesCustomReminders: true)
            clicked.recordClick(action); clicked.recordClick(action)
            guard clicked.clickedActions == [action], clicked.automaticRemindersStopped else { throw LocalError.message("Any single action must stop reminders and deduplicate its mark.") }
            let restored = JotleyEngagement(defaults: defaults, usesCustomReminders: true)
            for _ in 0..<15 { restored.completedSummary(result: "Saved after clicking") }
            guard restored.hasClicked(action), restored.automaticRemindersStopped,
                  restored.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Single-action dismissal did not survive relaunch.") }
            let count = restored.completedActions
            restored.resetClickedActions()
            guard restored.clickedActions.isEmpty, restored.automaticRemindersStopped,
                  defaults.integer(forKey: JotleyEngagement.countKey) == count,
                  defaults.bool(forKey: JotleyEngagement.reviewKey),
                  defaults.string(forKey: "unrelated-notes-fixture") == "keep-my-notes" else { throw LocalError.message("Reset changed notes, usage or the permanent reminder dismissal.") }
            let afterReset = JotleyEngagement(defaults: defaults, usesCustomReminders: true)
            for _ in 0..<10 { afterReset.completedSummary(result: "Saved after reset") }
            guard afterReset.claimPrompt(isIdle: true) == nil else { throw LocalError.message("Reset accidentally restarted automatic reminders.") }
        }
        // Previously stored marks are genuine clicks, unlike the old native request flag.
        defaults.removeObject(forKey: JotleyEngagement.stoppedKey)
        defaults.set(["feedback"], forKey: JotleyEngagement.clicksKey)
        let migrated = JotleyEngagement(defaults: defaults, usesCustomReminders: true)
        guard migrated.automaticRemindersStopped, defaults.bool(forKey: JotleyEngagement.stoppedKey) else { throw LocalError.message("Existing feedback click was not honored.") }
        print("PASS: direct Mac support waits five summaries between dismissals; any one Rate/Tip/Share/Feedback click permanently stops reminders; reset clears marks only; windows/relaunch and legacy marks are handled.")
    }
    @MainActor private static func verifySupportCardLayout() async throws {
        let suite = "JotleySupportLayout-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engagement = JotleyEngagement(defaults: defaults)
        let originalMode = ThemeManager.shared.currentAppearanceMode
        let originalColor = ThemeManager.shared.currentThemeColor
        defer {
            ThemeManager.shared.setAppearanceMode(originalMode)
            ThemeManager.shared.currentThemeColor = originalColor
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Jotley-Support-Proof")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for mode in [AppearanceMode.dark, .light] {
            ThemeManager.shared.setAppearanceMode(mode)
            for color in ThemeColor.allCases {
                ThemeManager.shared.currentThemeColor = color
                let content = JotleySupportView(engagement: engagement, isAutomatic: true, dismiss: {})
                let host = NSHostingView(rootView: content)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 780),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                guard host.frame.size == NSSize(width: 600, height: 780) else {
                    throw LocalError.message("Support card failed to fit its sheet.")
                }
                // cacheDisplay cannot capture a native glass compositing layer.
                // ImageRenderer checks SwiftUI content/background and text contrast;
                // the WindowServer glass itself needs a live-window visual check.
                let renderer = ImageRenderer(content: content.frame(width: 600, height: 780))
                renderer.proposedSize = ProposedViewSize(width: 600, height: 780)
                guard let rendered = renderer.cgImage else { throw LocalError.message("Support snapshot failed.") }
                let bitmap = NSBitmapImageRep(cgImage: rendered)
                guard let background = bitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB),
                      background.alphaComponent > 0.9,
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw LocalError.message("Support card rendering is transparent.")
                }
                var neutralGlyphs = 0
                for y in 30..<145 { for x in 115..<520 {
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let rgb = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
                    if (mode == .dark ? rgb.min()! > 0.7 : rgb.max()! < 0.3), rgb.max()! - rgb.min()! < 0.1 { neutralGlyphs += 1 }
                } }
                guard neutralGlyphs > 100 else { throw LocalError.message("Support header lacks readable neutral text.") }
                try png.write(to: output.appendingPathComponent("Support-\(mode.rawValue)-\(color.rawValue).png"))
                window.close()
            }
        }
        print("PASS: production support card renders at 600×780 with readable headings in five themes, Light and Dark.")
    }
    @MainActor private static func previewCompletedTranscript() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = RecordingLayoutDelegate(); app.delegate = delegate
        ThemeManager.shared.setAppearanceMode(.dark)
        ThemeManager.shared.currentThemeColor = .magenta
        app.appearance = NSAppearance(named: .darkAqua)
        let store = LocalAppModel.shared.store!
        let utterances: [TranscriptUtterance] = (1...30).map { index in
            let text = index == 30
                ? "Final passage: these completed words must remain fully readable above the footer gradient and Continue Transcription button."
                : "Passage \(index). Review the complete transcript at your own pace, then ask questions about the note or export its summary."
            return TranscriptUtterance(text: text, start: Double(index * 10), end: Double(index * 10 + 7))
        }
        let note = try! store.create(title: "Completed transcript layout", text: utterances.map(\.text).joined(separator: "\n\n")) as! Note
        note.setTranscriptUtterances(utterances)
        note.summary = "## Summary\n\n- Review the completed transcript.\n- Export a summary as PDF."
        // Historical metadata must not revive the retired saved-audio action.
        note.sourceURL = "Recordings/legacy-preview.m4a"
        try! store.save()
        defer { try? store.deleteNoteAndAudio(note) }
        let model = NotesListViewModel(viewContext: store.context, recorder: ProcessTapRecorder(), persistenceController: store)
        model.selectedNoteIDs = [note.objectID]; model.selectedDetailTab = DetailTab.transcript.rawValue
        let host = NSHostingView(rootView: NoteDetailPlaceholderView(note: note, selectedTab: Binding(get: { model.selectedDetailTab }, set: { model.selectedDetailTab = $0 }), viewModel: model)
            .environmentObject(store).environment(\.managedObjectContext, store.context))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 100, width: 760, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Jotley Detail Fixes Preview"; window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func previewSummaryProgress() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = RecordingLayoutDelegate(); app.delegate = delegate
        ThemeManager.shared.setAppearanceMode(.dark)
        ThemeManager.shared.currentThemeColor = .purple
        app.appearance = NSAppearance(named: .darkAqua)
        let store = LocalAppModel.shared.store!
        let note = try! store.create(title: "Weekly project review", text: "The team will review the design on Friday and prepare the next release together.") as! Note
        let model = NotesListViewModel(viewContext: store.context, recorder: ProcessTapRecorder(), persistenceController: store)
        model.selectedNoteIDs = [note.objectID]; model.selectedDetailTab = DetailTab.summary.rawValue
        model.simulatedSummaryGeneration = { _ in try await Task.sleep(for: .seconds(3600)); return "Unused preview result" }
        let host = NSHostingView(rootView: NoteDetailPlaceholderView(note: note, selectedTab: Binding(get: { model.selectedDetailTab }, set: { model.selectedDetailTab = $0 }), viewModel: model)
            .environmentObject(store).environment(\.managedObjectContext, store.context))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 100, width: 760, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Jotley Summary Progress Preview"; window.isReleasedWhenClosed = false
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        Task {
            let generation = Task { await model.generateSummary(note: note, templateKey: "Concise") }
            for _ in 0..<100 { if model.isGeneratingSummary { break }; try? await Task.sleep(for: .milliseconds(10)) }
            model.streamingSummaryViewModel.progress = .writing
            await generation.value
        }
        withExtendedLifetime(delegate) { app.run() }
    }
    @MainActor private static func previewSupportCard() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = RecordingLayoutDelegate(); app.delegate = delegate
        ThemeManager.shared.setAppearanceMode(.dark)
        ThemeManager.shared.currentThemeColor = .purple
        app.appearance = NSAppearance(named: .darkAqua)
        let suite = "JotleySupportPreview-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engagement = JotleyEngagement(defaults: defaults, usesCustomReminders: true)
        for _ in 0..<5 { engagement.completedSummary(result: "Synthetic saved summary") }
        let window = NSWindow(contentRect: NSRect(x: 200, y: 100, width: 840, height: 860),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Jotley Support Preview"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MacSupportPreviewRoot(engagement: engagement))
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
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
