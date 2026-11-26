import SwiftUI

extension NotesListView {
    func handleCreateNewNoteTapped() {
        guard transcriptionManager.canStart else {
            if transcriptionManager.isTranscribing { showingTranscriptionModal = true }
            return
        }
        do {
            newTranscriptionNote = try transcriptionManager.createNote()
            // The transcription screen starts microphone capture as soon as it opens.
            showingTranscriptionModal = true
        } catch { transcriptionManager.errorMessage = error.localizedDescription }
    }
}
