import SwiftUI
import CoreData

struct NoteDetailByIdView: View {
    @FetchRequest private var notes: FetchedResults<Note>
    init(noteId: UUID) {
        _notes = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "id == %@", noteId as CVarArg))
    }
    var body: some View {
        if let note = notes.first { NoteDetailView(note: note) }
        else { ContentUnavailableView("Note Unavailable", systemImage: "note.text") }
    }
}

struct NoteDetailView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var note: Note
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
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
    @State var editingSummary = false
    @State var showingAskAI = false
    var selectedTemplate: LocalSummaryTemplate { .resolve(note.summaryType) }
    func selectTemplate(_ template: LocalSummaryTemplate) {
        guard selectedTemplate != template else { return }
        note.summaryType = template.key
        transcriptionManager.saveEdits()
    }

    func generateSummary() {
        editingSummary = false
        selectedTab = "Summary"
        transcriptionManager.summarize(note, template: selectedTemplate)
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
    func clearExport() {
        exportPayload = nil
        if let exportDirectory { try? FileManager.default.removeItem(at: exportDirectory) }
        exportDirectory = nil
    }
}

struct MobileTranscriptEditor: View {
    @ObservedObject var note: Note
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @EnvironmentObject var store: SharedPersistenceController
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: String?
    private let original: String
    init(note: Note) {
        self.note = note
        original = note.transcription ?? ""
        _text = State(initialValue: original)
    }
    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body).foregroundStyle(Color.themeTextPrimary)
                .scrollContentBackground(.hidden).padding()
                .background(Color.themeBackground)
                .accessibilityIdentifier("transcriptEditorText")
                .navigationTitle("Edit Transcript")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.accessibilityIdentifier("transcriptEditorCancelButton")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                guard transcriptionManager.canStart else { throw LocalError.message("Finish transcribing or processing before saving edits.") }
                                try note.saveEditedTranscript(text, original: original, in: store)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(!transcriptionManager.canStart || note.isDeleted)
                            .accessibilityIdentifier("transcriptEditorSaveButton")
                    }
                }
                .alert("Couldn’t Save Transcript", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
        .preferredColorScheme(ThemeManager.shared.effectiveColorScheme)
        .observeThemeChanges()
        .interactiveDismissDisabled(text != original)
    }
}
