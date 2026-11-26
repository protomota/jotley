import SwiftUI
import CoreData
import AppKit
import Combine

// Refactored implementation of the detail tab view panel
struct DetailTabPanel: View {
    @ObservedObject var note: Note
    @Binding var selectedTab: Int // Raw value of DetailTab
    @Binding var isGeneratingSummary: Bool
    @Binding var summaryGenerationError: String?

    // Bindings for editable summary and transcript
    @Binding var editableSummary: String
    @FocusState.Binding var isSummaryEditorFocused: Bool
    @Binding var summaryInlineEditRequestCounter: Int
    @Binding var editableTranscript: String
    @FocusState.Binding var isTranscriptEditorFocused: Bool

    // Binding for raw markdown mode
    @Binding var showRawMarkdown: Bool

    // Optional view model to pass to the transcription tab view
    var viewModel: NotesListViewModel?

    // Per-note saved-audio loading flag, computed by the parent (which observes the
    // view model) and threaded down so SwiftUI re-renders the transcript tab when
    // it flips. Replaces the old persisted "Loading transcript..." placeholder.
    var isTranscriptLoading: Bool = false

    // Optional callback for generating summary from empty state
    var summaryLoadingStartedAt: Date?
    @ObservedObject var streamingSummaryViewModel: StreamingSummaryViewModel

    // Create a state property to force redraw when needed
    @State private var refreshID = UUID()
    // Flag to prevent responding to CoreData updates during local summary generation
    @State private var ignoreNoteChanges: Bool = false

    // Define an ID for the bottom anchor

    var body: some View {
        // Use Group to ensure proper view switching
        Group {
            if selectedTab == DetailTab.summary.rawValue {
                SummaryTabView(
                    note: note,
                    editableSummary: $editableSummary,
                    isSummaryEditorFocused: $isSummaryEditorFocused,
                    inlineEditRequestCounter: $summaryInlineEditRequestCounter,
                    isGeneratingSummary: $isGeneratingSummary,
                    summaryGenerationError: $summaryGenerationError,
                    showRawMarkdown: $showRawMarkdown,
                    summaryLoadingStartedAt: summaryLoadingStartedAt,
                    streamingSummaryViewModel: streamingSummaryViewModel
                )
                .transition(.opacity)
            } else if selectedTab == DetailTab.transcript.rawValue {
                TranscriptTabView(
                    note: note,
                    editableTranscript: $editableTranscript,
                    isTranscriptEditorFocused: $isTranscriptEditorFocused,
                    isLoading: isTranscriptLoading,
                    viewModel: viewModel
                )
                .transition(.opacity)
            } else {
                EmptyView()
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SummaryGenerationComplete"))
            .receive(on: RunLoop.main)) { notification in
                receiveSummaryCompletion(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SummaryGenerationFailed"))
            .receive(on: RunLoop.main)) { notification in
                receiveSummaryFailure(notification)
        }
        .onChange(of: note.summary) { oldValue, newValue in
            // Only process CoreData updates if we're not ignoring them during local summary generation
            if !ignoreNoteChanges {
                let trimmedSummary = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if trimmedSummary.isEmpty {
                    summaryGenerationError = nil
                }
                editableSummary = newValue ?? ""
                refreshID = UUID() // Force a refresh when summary changes
            }
        }
        .onChange(of: isGeneratingSummary) { oldValue, newValue in
            if oldValue && !newValue { // If we just finished generating
                // Let the notification handle updating the UI when data is truly ready
                // But still clear the ignore flag
                ignoreNoteChanges = false
            } else if !oldValue && newValue { // If we just started generating
                // Start ignoring CoreData updates until local summary generation completes
                ignoreNoteChanges = true
                summaryGenerationError = nil
            }
        }
    }

    // SwiftUI owns these subscriptions and cancels them when this panel is removed.
    private func receiveSummaryCompletion(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let noteID = userInfo["noteID"] as? NSManagedObjectID,
              noteID == note.objectID, !note.isDeleted else { return }

        summaryGenerationError = nil
        editableSummary = userInfo["summary"] as? String ?? note.summary ?? ""
        refreshID = UUID()
        ignoreNoteChanges = false
        // The generating task owns its loading state. A completion event must not
        // schedule a delayed reset that could stop a newer generation for this note.
    }

    private func receiveSummaryFailure(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let noteID = userInfo["noteID"] as? NSManagedObjectID,
              noteID == note.objectID, !note.isDeleted else { return }

        if let message = userInfo["message"] as? String, !message.isEmpty {
            summaryGenerationError = message
        } else if let error = userInfo["error"] as? Error {
            summaryGenerationError = error.localizedDescription
        } else {
            summaryGenerationError = "Couldn’t generate a summary right now. Please try again."
        }
        // Failed local generation leaves the previously saved summary intact.
        editableSummary = note.summary ?? ""
        refreshID = UUID()
        ignoreNoteChanges = false
    }
}
