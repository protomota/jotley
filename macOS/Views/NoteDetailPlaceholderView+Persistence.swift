import SwiftUI

extension NoteDetailPlaceholderView {
    func saveTranscriptChanges() {
        guard !isEditingTranscript, editableTranscriptNoteID == note.objectID,
              note.managedObjectContext != nil, !note.isDeleted,
              !Note.isTranscriptionLoadingPlaceholder(editableTranscript),
              editableTranscript != savedTranscript else { return }
        do {
            try note.saveEditedTranscript(editableTranscript, original: savedTranscript, in: persistenceController)
            savedTranscript = editableTranscript
        } catch { viewModel.report(error) }
    }

    func saveSummaryChanges() {
        guard editableTranscriptNoteID == note.objectID, note.managedObjectContext != nil,
              !note.isDeleted, editableSummary != savedSummary else { return }
        do {
            try note.saveEditedSummary(editableSummary, original: savedSummary, in: persistenceController)
            savedSummary = editableSummary
        } catch { viewModel.report(error) }
    }

    func scheduleSummarySave() {
        summarySaveTimer?.invalidate()
        summarySaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in self.saveSummaryChanges() }
    }

    func scheduleTranscriptSave() {
        transcriptSaveTimer?.invalidate()
        transcriptSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in self.saveTranscriptChanges() }
    }

    func saveContext() {
        guard viewContext.hasChanges else { return }
        do { try persistenceController.save() } catch { viewModel.report(error) }
    }
}
