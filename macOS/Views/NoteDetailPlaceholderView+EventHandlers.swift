import SwiftUI
import CoreData
import AppKit

extension NoteDetailPlaceholderView {
    // MARK: Event Handlers

    func handleOnAppear() {
        summaryGenerationError = nil
        editableSummary = note.summary ?? ""
        editableTranscript = note.transcription ?? ""
        editableTranscriptNoteID = note.objectID
        currentTags = note.tagNames  // Initialize tags from note







        // If this note is actively recording, always surface the transcript tab
        // so live transcription remains visible.
        if viewModel.recorder.isRecording && viewModel.newNoteBeingRecorded == note {
            selectedTab = DetailTab.transcript.rawValue
        }

        // Set per-tab markdown/rendered defaults
        showRawMarkdownSummary = false // Rendered

        viewRefreshID = UUID() // Force a refresh of child views like DetailTabPanel


        // Listen for save notification from view model
        NotificationCenter.default.addObserver(forName: Notification.Name("JotVibeSaveCurrentNote"), object: nil, queue: .main) { _ in

            self.saveTranscriptChanges()
            self.saveSummaryChanges()
        }

        // Listen for force save notification when app is terminating
        NotificationCenter.default.addObserver(forName: Notification.Name("JotleyForceAllEditorsSave"), object: nil, queue: .main) { _ in

            // Cancel any pending save timers and execute saves immediately
            self.summarySaveTimer?.invalidate()
            self.transcriptSaveTimer?.invalidate()

            // Force all editors to lose focus which will trigger their save handlers
            self.isTranscriptEditorFocused = false
            self.isSummaryEditorFocused = false

            // Give a brief moment for focus changes to propagate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // Explicitly save all content
                self.saveTranscriptChanges()
                self.saveSummaryChanges()
            }
        }

        // Commented out periodic focus checker as it was causing focus loss while typing
        // focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        //     // Check if any text field has focus by examining the first responder
        //     guard let window = NSApp.keyWindow,
        //           let firstResponder = window.firstResponder else {
        //         // No window or first responder, ensure all fields are marked as unfocused
        //         if self.isNotesEditorFocused || self.isSummaryEditorFocused || self.isTranscriptEditorFocused {
        //             self.isNotesEditorFocused = false
        //             self.isSummaryEditorFocused = false
        //             self.isTranscriptEditorFocused = false
        //         }
        //         return
        //     }
        //
        //     // If first responder is not a text view, ensure our fields are unfocused
        //     if !(firstResponder is NSTextView) {
        //         if self.isNotesEditorFocused {
        //             self.isNotesEditorFocused = false
        //         }
        //         if self.isSummaryEditorFocused {
        //             self.isSummaryEditorFocused = false
        //         }
        //         if self.isTranscriptEditorFocused {
        //             self.isTranscriptEditorFocused = false
        //         }
        //     }
        // }
    }

    @MainActor


    func handleTranscriptionPausedChanged(_ oldValue: Bool?, _ isPausedNewValue: Bool?) {
        let vm = viewModel
        guard vm.newNoteBeingRecorded == self.note, // Change is for the current note
              isPausedNewValue == false,             // Transcription is now active (not paused)
              vm.recorder.isRecording == true else {   // Recorder is actually running
            return
        }

        if selectedTab != DetailTab.transcript.rawValue {
            selectedTab = DetailTab.transcript.rawValue
        }
    }

    func handleRecordingChanged(_ oldValue: Bool?, _ isRecordingNow: Bool?) {
        let vm = viewModel
        guard vm.newNoteBeingRecorded == self.note, // Change is for the current note
              isRecordingNow == true else {         // Recorder just started
            return
        }

        if selectedTab != DetailTab.transcript.rawValue {
            selectedTab = DetailTab.transcript.rawValue
        }
    }

    func handleTranscriptFocusChanged(_ oldIsFocused: Bool, _ newIsFocused: Bool) {
        if oldIsFocused == true && newIsFocused == false {
            // Transcript editor lost focus, save changes

            saveTranscriptChanges()
        }
    }

    func handleNoteChanged(_ oldObjectID: NSManagedObjectID, _ newObjectID: NSManagedObjectID) {
        // Before switching notes, save any pending changes
        if isSummaryEditorFocused {

            saveSummaryChanges()
        }
        if isTranscriptEditorFocused {

            saveTranscriptChanges()
        }

        // Ensure editors lose focus so their state is updated before saving
        isTranscriptEditorFocused = false
        isSummaryEditorFocused = false

        guard oldObjectID != newObjectID else {
            // This block handles the case where the new and old IDs are the same.
            // This might be a refresh or no actual change.
            // We'll ensure the current note's editable fields are synced if not focused.
            manualTitle = note.titleOrUntitled // 'note' is the current (and effectively new) note
            summaryGenerationError = nil
            editableSummary = note.summary ?? ""
            if !isTranscriptEditorFocused { // Sync transcript if editor not focused
                editableTranscript = note.transcription ?? ""
                editableTranscriptNoteID = note.objectID
            }
            return
        }

        // If we are here, oldObjectID != newObjectID. A true switch has occurred.
        // 'note' @ObservedObject has already been updated by SwiftUI to reflect the new note (associated with newObjectID).
        // We need to save the state of 'editableTranscript' (which holds content from the old note)
        // against the 'oldObjectID'.

        let context = viewContext
        if let actualOldNote = try? context.existingObject(with: oldObjectID) as? Note {
            var oldNoteMadeChanges = false

            // Save transcript of the old note. 'editableTranscript' currently holds (potentially edited) content from actualOldNote.
            // 'preferCleanedTranscript' reflects the global setting at the moment of switch.
            // Saving to raw transcript for the old note
            if actualOldNote.transcription ?? "" != editableTranscript {
                actualOldNote.transcription = editableTranscript.isEmpty ? nil : editableTranscript
                oldNoteMadeChanges = true

            }

            if oldNoteMadeChanges && context.hasChanges {
                do {
                    try persistenceController.save()

                } catch {

                }
            }
        } else {

        }

        // Now, load content for the NEW note (the 'note' object itself is already the new note)
        manualTitle = note.titleOrUntitled
        summaryGenerationError = nil
        editableSummary = note.summary ?? ""

        // Load transcript for the new note.
        editableTranscript = note.transcription ?? ""
        editableTranscriptNoteID = note.objectID



        viewRefreshID = UUID() // Force a refresh of child views like DetailTabPanel
    }

    func handleTabChanged(_ oldValue: Int, _ newTabRawValue: Int) {

        // Cancel any pending save timers for the old tab
        if oldValue == DetailTab.summary.rawValue {
            summarySaveTimer?.invalidate()
            summarySaveTimer = nil
        } else if oldValue == DetailTab.transcript.rawValue {
            transcriptSaveTimer?.invalidate()
            transcriptSaveTimer = nil
        }

        // Flush in-progress edits from the previous tab, but only when the
        // editor was actually focused. A blind save here can race the
        // SwiftUI binding update for editableSummary/editableTranscript and
        // clobber freshly-imported content (e.g. a transcript +
        // auto-summary) with an empty @State buffer.
        if oldValue == DetailTab.summary.rawValue, isSummaryEditorFocused {

            isSummaryEditorFocused = false
            saveSummaryChanges()
        } else if oldValue == DetailTab.transcript.rawValue, isTranscriptEditorFocused {

            isTranscriptEditorFocused = false
            saveTranscriptChanges()
        }

        // When switching to summary tab, ensure editableSummary is synced with the current note content
        if newTabRawValue == DetailTab.summary.rawValue {
            // Sync summary when switching to summary tab
            if !isSummaryEditorFocused {
                let currentSummaryValue = note.summary ?? ""
                if editableSummary != currentSummaryValue {

                    editableSummary = currentSummaryValue
                }
            }
        } else if newTabRawValue == DetailTab.transcript.rawValue {
            // Sync transcript when switching to transcript tab
            if !isTranscriptEditorFocused {
                let currentTranscriptValue = note.transcription ?? ""
                if editableTranscript != currentTranscriptValue {



                    editableTranscript = currentTranscriptValue
                }





            }
        }
    }

    func handleSummaryChanged(_ oldValue: String?, _ newSummary: String?) {
        if !isSummaryEditorFocused {
            editableSummary = newSummary ?? ""

        } else {

        }

        // If the Summary tab is selected but no longer has a summary to show
        // (and we're not actively generating one), fall back to a visible tab
        // so the user isn't stranded on a hidden tab.
        if selectedTab == DetailTab.summary.rawValue && !hasSummary {
            let isGeneratingSummaryForThisNote =
                (viewModel.isGeneratingSummary && viewModel.generatingSummaryNoteID == note.objectID) ||
                newSummary?.trimmingCharacters(in: .whitespacesAndNewlines) == "Generating summary..."
            if !isGeneratingSummaryForThisNote {
                selectedTab = DetailTab.transcript.rawValue
            }
        }
    }

    func handleTitleChanged(_ oldValue: String?, _ newTitle: String?) {
        manualTitle = newTitle ?? note.titleOrUntitled

    }

    func handleSummaryFocusChanged(_ oldIsFocused: Bool, _ newIsFocused: Bool) {
        if oldIsFocused == true && newIsFocused == false {
            // Summary editor lost focus, save changes

            saveSummaryChanges()
        }
    }
}
