import SwiftUI

extension NoteDetailPlaceholderView {
    func requestSummaryInlineEdit() {
        selectedTab = DetailTab.summary.rawValue
        summaryInlineEditRequestCounter += 1
    }
}

/// Edits in the note's scroll view, using a separate draft so a concurrent
/// transcript update can never be overwritten by an older editor buffer.
struct LocalMacTranscriptEditor: View {
    @ObservedObject var note: Note
    @ObservedObject var viewModel: NotesListViewModel
    @EnvironmentObject var store: SharedPersistenceController
    @State private var text: String
    @State private var lastSaved: String
    @State private var error: String?
    @State private var editorHeight: CGFloat = ContentLayoutConstants.standardMinHeight
    @FocusState private var isFocused: Bool
    var onFinish: () -> Void

    init(note: Note, viewModel: NotesListViewModel, onFinish: @escaping () -> Void = {}) {
        self.note = note; self.viewModel = viewModel; self.onFinish = onFinish
        _text = State(initialValue: note.transcription ?? "")
        _lastSaved = State(initialValue: note.transcription ?? "")
    }
    private var canSave: Bool {
        let recordingThisNote = viewModel.newNoteBeingRecorded?.objectID == note.objectID &&
            (viewModel.recorder.isRecording || viewModel.isTranscriptionPaused || viewModel.recorder.isBusy || viewModel.operationInProgress)
        let generatingThisNote = viewModel.isGeneratingSummary && viewModel.generatingSummaryNoteID == note.objectID
        return !note.isDeleted && !recordingThisNote && !generatingThisNote && !LocalAppModel.shared.busy
    }
    @discardableResult private func save() -> Bool {
        guard text != lastSaved else { return true }
        do {
            guard canSave else { throw LocalError.message("Finish transcription or processing before saving edits.") }
            try note.saveEditedTranscript(text, original: lastSaved, in: store)
            lastSaved = text
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    private func finish() {
        guard save() else { return }
        isFocused = false
        onFinish()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button(action: finish) {
                    Label("Done", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.themePrimaryAccent)
                }
                .buttonStyle(JotleyGlassButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave)
                .accessibilityIdentifier("transcriptEditorSaveButton")
            }
            InlineEditableSummaryTextView(text: $text, isFocused: $isFocused,
                accentColor: NSColor(Color.themePrimaryAccent), textColor: NSColor(Color.themeTextPrimary),
                measuredHeight: $editorHeight)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: max(editorHeight, ContentLayoutConstants.standardMinHeight), alignment: .topLeading)
                .accessibilityIdentifier("transcriptEditorText")
            if let error {
                HStack(alignment: .top) {
                    Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("transcriptEditorError")
                    Spacer()
                    Button("Discard Changes") {
                        text = note.transcription ?? ""
                        lastSaved = text
                        self.error = nil
                        isFocused = false
                        onFinish()
                    }.buttonStyle(JotleyGlassButtonStyle())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 12))
        .tint(.themePrimaryAccent).observeThemeChanges()
        .onAppear { isFocused = true }
        .onExitCommand(perform: finish)
        .onChange(of: isFocused) { oldValue, newValue in
            if oldValue && !newValue { save() }
        }
        .task(id: text) {
            guard text != lastSaved else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            save()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("JotleyForceAllEditorsSave"))) { _ in
            if !save(), let error { viewModel.report(LocalError.message(error)) }
        }
        .onDisappear {
            if !save(), let error { viewModel.report(LocalError.message(error)) }
        }
    }
}
