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
    @State private var draft: TranscriptEditDraft
    @State private var error: String?
    var onFinish: () -> Void

    init(note: Note, viewModel: NotesListViewModel, onFinish: @escaping () -> Void = {}) {
        self.note = note; self.viewModel = viewModel; self.onFinish = onFinish
        _draft = State(initialValue: TranscriptEditDraft(text: note.transcription ?? "", utterances: note.storedTranscriptUtterances))
    }
    private var canSave: Bool {
        let recordingThisNote = viewModel.newNoteBeingRecorded?.objectID == note.objectID &&
            (viewModel.recorder.isRecording || viewModel.isTranscriptionPaused || viewModel.recorder.isBusy || viewModel.operationInProgress)
        let generatingThisNote = viewModel.isGeneratingSummary && viewModel.generatingSummaryNoteID == note.objectID
        return !note.isDeleted && !recordingThisNote && !generatingThisNote && !LocalAppModel.shared.busy
    }
    @discardableResult private func save() -> Bool {
        guard draft.hasChanges else { return true }
        do {
            guard canSave else { throw LocalError.message("Finish transcription or processing before saving edits.") }
            try note.saveEditedTranscript(draft, in: store)
            draft = TranscriptEditDraft(text: note.transcription ?? "", utterances: note.storedTranscriptUtterances)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    private func finish() {
        guard save() else { return }
        onFinish()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button(action: finish) {
                    Label("Done", systemImage: "checkmark")
                }
                .jotleyDismissButtonStyle()
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave)
                .accessibilityIdentifier("transcriptEditorSaveButton")
            }
            TranscriptFindReplace(draft: $draft)
            if !draft.segments.contains(where: { $0.timestampLabel != nil }) {
                Text("Timing is unavailable for this transcript.").font(.caption).foregroundStyle(Color.themeTextSecondary)
            }
            ForEach($draft.segments) { $segment in
                LocalMacTranscriptParagraphEditor(segment: $segment)
            }
            if let error {
                HStack(alignment: .top) {
                    Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("transcriptEditorError")
                    Spacer()
                    Button("Discard Changes") {
                        draft = TranscriptEditDraft(text: note.transcription ?? "", utterances: note.storedTranscriptUtterances)
                        self.error = nil
                        onFinish()
                    }.buttonStyle(JotleyGlassButtonStyle())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 12))
        .tint(.themePrimaryAccent).observeThemeChanges()
        .onExitCommand(perform: finish)
        .task(id: draft.segments) {
            guard draft.hasChanges else { return }
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

private struct LocalMacTranscriptParagraphEditor: View {
    @Binding var segment: TranscriptUtterance
    @State private var height: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let timestamp = segment.timestampLabel {
                Text(timestamp).font(.caption.monospacedDigit()).foregroundStyle(Color.themeTextSecondary)
            }
            InlineEditableSummaryTextView(text: $segment.text, isFocused: $focused,
                accentColor: NSColor(Color.themePrimaryAccent), textColor: NSColor(Color.themeTextPrimary),
                measuredHeight: $height, fontSize: 15)
                .frame(height: max(height, 32), alignment: .topLeading)
                .accessibilityLabel(segment.timestampLabel.map { "Transcript at \($0)" } ?? "Transcript paragraph")
                .accessibilityIdentifier("transcriptEditorText")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(JotleyEditorField(isFocused: focused))
    }
}
