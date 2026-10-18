import SwiftUI
import AppKit
extension NotesListView {
    var body: some View {
        navigationView
            .modifier(AlertModifier(viewModel: viewModel))
            .onChange(of: summaryNotifications.noteToOpen, initial: true) { _, id in
                guard let id, let note = notes.first(where: { $0.id == id }) else { return }
                viewModel.selectedNoteIDs = [note.objectID]
                viewModel.selectedDetailTab = DetailTab.summary.rawValue
                focusMainWindow()
                summaryNotifications.noteToOpen = nil
            }
            .onDeleteCommand(perform: handleDeleteCommand)
            .onChange(of: viewModel.recorder.transcription) { _, _ in viewModel.updateNewNoteTranscription() }
            .onChange(of: filterState.selectedFolder) { _, value in viewModel.pendingFolderSelection = value }
            .onAppear {
                JotleyAppDelegate.shared?.activeNotesViewModel = viewModel
                viewModel.pendingFolderSelection = filterState.selectedFolder
                if viewModel.selectedNoteIDs.isEmpty, let note = notes.first { viewModel.toggleSelection(for: note) }
                if showRecordingWidget { recordingWidgetController.startMonitoring(recorder: viewModel.recorder, onWidgetTapped: focusMainWindow) }
            }
            .onDisappear { recordingWidgetController.stopMonitoring() }
            .onChange(of: showRecordingWidget) { _, enabled in
                if enabled { recordingWidgetController.startMonitoring(recorder: viewModel.recorder, onWidgetTapped: focusMainWindow) }
                else { recordingWidgetController.stopMonitoring() }
            }
    }
}
