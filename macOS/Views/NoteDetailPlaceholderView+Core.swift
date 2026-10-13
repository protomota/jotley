import SwiftUI

extension NoteDetailPlaceholderView {
    func requestSummaryInlineEdit() {
        selectedTab = DetailTab.summary.rawValue
        summaryInlineEditRequestCounter += 1
    }
}

struct LocalMacTranscriptEditor: View {
    @ObservedObject var note: Note
    @ObservedObject var viewModel: NotesListViewModel
    @EnvironmentObject var store: SharedPersistenceController
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: String?
    private let original: String
    init(note: Note, viewModel: NotesListViewModel) {
        self.note = note; self.viewModel = viewModel
        original = note.transcription ?? ""
        _text = State(initialValue: original)
    }
    private var canSave: Bool {
        !note.isDeleted && !viewModel.recorder.isRecording && !viewModel.isTranscriptionPaused && !viewModel.recorder.isBusy &&
            !viewModel.operationInProgress && !viewModel.isGeneratingSummary && !LocalAppModel.shared.busy
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Transcript").font(.title2.bold()).foregroundStyle(Color.themeTextPrimary)
            TextEditor(text: $text)
                .font(.body).foregroundStyle(Color.themeTextPrimary)
                .scrollContentBackground(.hidden)
                .padding(12).background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("transcriptEditorText")
            if let error { Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("transcriptEditorError") }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("transcriptEditorCancelButton")
                Button("Save") {
                    do {
                        guard canSave else { throw LocalError.message("Finish recording or processing before saving edits.") }
                        try note.saveEditedTranscript(text, original: original, in: store)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
                    .accessibilityIdentifier("transcriptEditorSaveButton")
            }
        }.padding(24).frame(width: 600, height: 440).background(Color.themeBackground)
            .tint(.themePrimaryAccent).observeThemeChanges()
    }
}
