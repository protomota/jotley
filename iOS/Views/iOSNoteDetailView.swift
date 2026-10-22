import SwiftUI
import CoreData

struct NoteDetailByIdView: View {
    @FetchRequest private var notes: FetchedResults<Note>
    private let newTranscriptionAction: (() -> Void)?
    private let showNotesAction: (() -> Void)?
    init(noteId: UUID, newTranscriptionAction: (() -> Void)? = nil, showNotesAction: (() -> Void)? = nil) {
        self.newTranscriptionAction = newTranscriptionAction
        self.showNotesAction = showNotesAction
        _notes = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "id == %@", noteId as CVarArg))
    }
    var body: some View {
        if let note = notes.first { NoteDetailView(note: note, newTranscriptionAction: newTranscriptionAction, showNotesAction: showNotesAction) }
        else { ContentUnavailableView("Note Unavailable", systemImage: "note.text") }
    }
}

struct NoteDetailView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var note: Note
    var newTranscriptionAction: (() -> Void)? = nil
    var showNotesAction: (() -> Void)? = nil
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
    var selectedTemplate: LocalSummaryTemplate { .resolve(note.summaryType) }
    func selectTemplate(_ template: LocalSummaryTemplate) {
        guard selectedTemplate != template, transcriptionManager.canStart else { return }
        if Note.isMeaningfulSummaryText(note.summary) && hasTranscript {
            selectedTab = "Summary"
            transcriptionManager.summarize(note, template: template)
        } else {
            note.summaryType = template.key
            transcriptionManager.saveEdits()
        }
    }

    func generateSummary() {
        selectedTab = "Summary"
        transcriptionManager.summarize(note, template: selectedTemplate)
    }
    var summaryIsRunning: Bool { transcriptionManager.summaryNoteID == note.id }
    var noteIsTranscribing: Bool { transcriptionManager.activeNoteID == note.id && transcriptionManager.isTranscribing }
    var hasTranscript: Bool { !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasSummary: Bool { Note.isMeaningfulSummaryText(note.summary) || summaryIsRunning }
    var transcript: String { note.transcription ?? "" }

    var noteSwipesEnabled: Bool {
        !isEditingTitle && !showingTranscriptEditor && !showingSummaryEditor && !showingAskAI &&
        !showingTranscription && !showingAddTag && !showingDelete && exportPayload == nil
    }
    func navigateNoteSwipe(_ direction: NoteContentSwipeDirection) {
        switch direction {
        case .right:
            if selectedTab == "Transcript", hasSummary { selectedTab = "Summary" }
            else if let showNotesAction { showNotesAction() }
            else { dismiss() }
        case .left:
            if selectedTab == "Summary", hasTranscript || noteIsTranscribing { selectedTab = "Transcript" }
        }
    }

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
    @State private var error: String?
    private let original: String
    init(note: Note, field: Field) {
        self.note = note
        self.field = field
        original = (field == .transcript ? note.transcription : note.summary) ?? ""
        _text = State(initialValue: original)
    }
    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body).foregroundStyle(Color.themeTextPrimary)
                .scrollContentBackground(.hidden).padding()
                .background(Color.themeBackground)
                .accessibilityLabel(field.title)
                .accessibilityIdentifier("\(field.key)EditorText")
                .navigationTitle("Edit \(field.title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.accessibilityIdentifier("\(field.key)EditorCancelButton")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                guard transcriptionManager.canStart else { throw LocalError.message("Finish transcribing or processing before saving edits.") }
                                switch field {
                                case .transcript: try note.saveEditedTranscript(text, original: original, in: store)
                                case .summary: try note.saveEditedSummary(text, original: original, in: store)
                                }
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(!transcriptionManager.canStart || note.isDeleted)
                            .accessibilityIdentifier("\(field.key)EditorSaveButton")
                    }
                }
                .alert("Couldn’t Save \(field.title)", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
        .tint(Color.themeActionText)
        .preferredColorScheme(ThemeManager.shared.effectiveColorScheme)
        .observeThemeChanges()
        .interactiveDismissDisabled(text != original)
    }
}
