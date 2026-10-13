import SwiftUI
import AppKit

extension NotesListView {
    var canCreateNewNote: Bool {
        !viewModel.recorder.isRecording && !viewModel.isTranscriptionPaused
    }

    var activeRecordingNote: Note? {
        viewModel.activeRecordingNote
    }

    func focusMainWindow() {
        if let appDelegate = NSApp.delegate as? JotleyAppDelegate {
            appDelegate.bringMainWindowToFrontAndEnsureSingle()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func handleDeleteCommand() {
        // Keep standard delete behavior when user is editing text fields/editors.
        if NSApp.keyWindow?.firstResponder is NSTextView {
            return
        }

        guard !viewModel.selectedNoteIDs.isEmpty else { return }
        Task { @MainActor in await viewModel.deleteSelectedNotes(fetchedNotes: notes) }
    }
}
