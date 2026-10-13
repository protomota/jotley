import SwiftUI

extension NoteDetailPlaceholderView {
    // MARK: Save Transcript Function
    func saveTranscriptChanges() {
        guard note.managedObjectContext != nil, !note.isDeleted else {

            return
        }

        // The editor's @State buffer can transiently hold a loading sentinel
        // ("Loading transcript...") if a CloudKit merge briefly resurfaced the
        // import placeholder. Never persist that over real content or re-export
        // it to CloudKit — doing so latches the bad state permanently and is the
        // root of the transcript persistence "transcript deleted, stuck importing" bug.
        guard !Note.isTranscriptionLoadingPlaceholder(editableTranscript) else {

            return
        }

        var changed = false
        let currentTranscript = note.transcription ?? ""

        if currentTranscript != editableTranscript {
            note.transcription = editableTranscript.isEmpty ? nil : editableTranscript
            if editableTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note.setTranscriptUtterances([])
            } else {
                note.setTranscriptUtterances(TranscriptUtterance.fallbackUtterances(from: editableTranscript))
            }
            changed = true



        }

        if changed {
            do {
                try persistenceController.save()

            } catch {
                viewModel.report(error)
            }
        } else {

        }
    }

    // MARK: Save Summary Function
    func saveSummaryChanges() {
        guard note.managedObjectContext != nil, !note.isDeleted else {

            return
        }

        var changed = false
        let currentSummary = note.summary ?? ""

        if currentSummary != editableSummary {
            note.summary = editableSummary.isEmpty ? nil : editableSummary
            changed = true



        }

        if changed {
            do {
                try persistenceController.save()

            } catch {
                viewModel.report(error)
            }
        } else {

        }
    }

    // MARK: Debounced Save Functions
    func scheduleSummarySave() {
        summarySaveTimer?.invalidate()
        summarySaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            guard self.note.managedObjectContext != nil, !self.note.isDeleted else { return }

            self.saveSummaryChanges()
        }
    }

    func scheduleTranscriptSave() {
        transcriptSaveTimer?.invalidate()
        transcriptSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            guard self.note.managedObjectContext != nil, !self.note.isDeleted else { return }

            self.saveTranscriptChanges()
        }
    }

    // Helper to save context
    func saveContext() {
        if viewContext.hasChanges {
            do {
                try persistenceController.save()
            } catch {
                viewModel.report(error)
            }
        }
    }
}
