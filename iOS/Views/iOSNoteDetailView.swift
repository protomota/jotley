import SwiftUI
import CoreData

struct NoteDetailByIdView: View {
    @FetchRequest private var notes: FetchedResults<Note>
    private let newTranscriptionAction: (() -> Void)?
    init(noteId: UUID, newTranscriptionAction: (() -> Void)? = nil) {
        self.newTranscriptionAction = newTranscriptionAction
        _notes = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "id == %@", noteId as CVarArg))
    }
    var body: some View {
        if let note = notes.first { NoteDetailView(note: note, newTranscriptionAction: newTranscriptionAction) }
        else { ContentUnavailableView("Note Unavailable", systemImage: "note.text") }
    }
}

struct NoteDetailView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var note: Note
    var newTranscriptionAction: (() -> Void)? = nil
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @State var actionsFooterHeight: CGFloat = 150
    @State var selectedTab = "Transcript"
    @State var isEditingTitle = false
    @State var editedTitle = ""
    @FocusState var isTitleFieldFocused: Bool
    @State var showingTranscription = false
    @State var showingDelete = false
    @State var exportPayload: LocalSharePayload?
    @State var exportDirectory: URL?
    @State var showingAddTag = false
    @State var newTagText = ""
    @State var currentTags: [String] = []
    @State var showingTranscriptEditor = false
    @State var showingSummaryEditor = false
    @State var showingAskAI = false
    @ObservedObject var templateCatalog = SummaryTemplateStore.shared
    @State var templatePresentation: SummaryTemplatePresentation?
    var selectedTemplateTitle: String { templateCatalog.title(for: note.summaryType) }
    func selectTemplate(_ template: SummaryTemplateDefinition) {
        guard note.summaryType != template.key, transcriptionManager.canStart else { return }
        if Note.isMeaningfulSummaryText(note.summary) && hasTranscript {
            selectedTab = "Summary"
            transcriptionManager.summarize(note, template: template)
        } else {
            note.summaryType = template.key
            transcriptionManager.saveEdits()
        }
    }

    func generateSummary() {
        guard let template = try? templateCatalog.resolve(note.summaryType) else {
            transcriptionManager.errorMessage = "This template is unavailable. Choose another template to regenerate the summary."
            return
        }
        selectedTab = "Summary"
        transcriptionManager.summarize(note, template: template)
    }
    var summaryIsRunning: Bool { transcriptionManager.summaryNoteID == note.id }
    var noteIsTranscribing: Bool { transcriptionManager.activeNoteID == note.id && transcriptionManager.isTranscribing }
    var hasTranscript: Bool { !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasSummary: Bool { Note.isMeaningfulSummaryText(note.summary) || summaryIsRunning }
    var transcript: String { note.transcription ?? "" }

    func shareAsText() {
        exportPayload = LocalSharePayload(items: [LocalNoteExport.content(note: note, format: .plainText)])
    }
    func export(_ format: LocalNoteExport.Format) {
        do {
            let file = try LocalNoteExport.file(note: note, format: format)
            exportDirectory = file.deletingLastPathComponent()
            exportPayload = LocalSharePayload(items: [file])
        } catch { transcriptionManager.errorMessage = "Export failed: \(error.localizedDescription). Your note remains saved in Jotley." }
    }
    func shareSummaryPDF() {
        do {
            let file = try LocalNoteExport.summaryPDF(note: note)
            exportDirectory = file.deletingLastPathComponent()
            exportPayload = LocalSharePayload(items: [file])
        } catch { transcriptionManager.errorMessage = "The PDF could not be created: \(error.localizedDescription). Your note remains saved in Jotley." }
    }
    func clearExport() {
        exportPayload = nil
        if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
        exportDirectory = nil
    }
}

struct MobileNoteTextEditor: View {
    enum Field {
        case transcript, summary
        var title: String { self == .transcript ? "Transcript" : "Summary" }
        var key: String { self == .transcript ? "transcript" : "summary" }
    }
    @ObservedObject var note: Note
    let field: Field
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @EnvironmentObject var store: SharedPersistenceController
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var transcriptDraft: TranscriptEditDraft
    @State private var error: String?
    @FocusState private var editorFocused: Bool
    private let original: String
    init(note: Note, field: Field) {
        self.note = note
        self.field = field
        original = (field == .transcript ? note.transcription : note.summary) ?? ""
        _text = State(initialValue: original)
        _transcriptDraft = State(initialValue: TranscriptEditDraft(text: note.transcription ?? "", utterances: note.storedTranscriptUtterances))
    }
    var body: some View {
        NavigationStack {
            Group {
                if field == .transcript {
                    VStack(alignment: .leading, spacing: 12) {
                        TranscriptFindReplace(draft: $transcriptDraft)
                        if !transcriptDraft.hasTimestamps {
                            Text("Timing is unavailable for this transcript.").font(.caption).foregroundStyle(Color.themeTextSecondary)
                        }
                        editor(text: $transcriptDraft.editorText)
                    }
                } else {
                    editor(text: $text)
                }
            }
                .font(.body).foregroundStyle(Color.themeTextPrimary)
                .scrollContentBackground(.hidden).padding()
                .background(Color.themeBackground)
                .navigationTitle("Edit \(field.title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .jotleyDismissButtonStyle(inToolbar: true)
                            .accessibilityIdentifier("\(field.key)EditorCancelButton")
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                guard transcriptionManager.canStart else { throw LocalError.message("Finish transcribing or processing before saving edits.") }
                                switch field {
                                case .transcript: try note.saveEditedTranscript(transcriptDraft, in: store)
                                case .summary: try note.saveEditedSummary(text, original: original, in: store)
                                }
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                            .jotleyDismissButtonStyle(inToolbar: true)
                            .disabled(!transcriptionManager.canStart || note.isDeleted)
                            .accessibilityIdentifier("\(field.key)EditorSaveButton")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .alert("Couldn’t Save \(field.title)", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
        .tint(Color.themeActionText)
        .preferredColorScheme(ThemeManager.shared.effectiveColorScheme)
        .observeThemeChanges()
        .interactiveDismissDisabled(field == .transcript ? transcriptDraft.hasChanges : text != original)
    }

    private func editor(text: Binding<String>) -> some View {
        TextEditor(text: text)
            .focused($editorFocused)
            .scrollContentBackground(.hidden)
            .padding(8)
            .modifier(JotleyEditorField(isFocused: editorFocused))
            .accessibilityLabel(field.title)
            .accessibilityIdentifier("\(field.key)EditorText")
    }
}
