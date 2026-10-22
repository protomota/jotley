import SwiftUI
import AppKit

// MARK: - View Components

extension NoteDetailPlaceholderView {
    // Computed property to check if we're recording this specific note
    var isRecordingThisNote: Bool {
        viewModel.recorder.isRecording &&
        viewModel.recorder.isRecordingNewNote &&
        viewModel.newNoteBeingRecorded == note
    }

    var isRecordingOnAnotherNote: Bool {
        guard let activeRecordingNote = viewModel.activeRecordingNote else { return false }
        return activeRecordingNote.objectID != note.objectID
    }

    var hasActiveRecordingSession: Bool {
        viewModel.recorder.isRecording || viewModel.isTranscriptionPaused
    }

    // Check if there's content available to summarize (transcription)
    var hasContentToSummarize: Bool {
        let hasTranscription = note.transcription != nil && !note.transcription!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTranscription
    }

    var hasSummary: Bool {
        guard let summary = note.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return false
        }
        return true
    }

    var detailScrollTopAnchorID: String {
        "note-detail-summary-top-anchor"
    }

    var detailScrollBottomAnchorID: String {
        "note-detail-live-bottom-anchor"
    }

    // Keep the final transcript above the entire footer fade, while the scroll
    // view and its scrollbar continue to reach the bottom of the window.
    var detailFooterFadeHeight: CGFloat {
        selectedTab == DetailTab.summary.rawValue ? 160 : 120
    }

    var detailBottomPadding: CGFloat {
        if viewModel.recorder.isRecording { return 88 }
        if selectedTab == DetailTab.transcript.rawValue || note.hasMeaningfulSummaryText {
            return detailFooterFadeHeight + 16
        }
        return 16
    }

    var bodyContentView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add spacing for the fixed toolbar at top
                Color.clear
                    .frame(height: 44)

                // Main content wrapped in ScrollView
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            headerContent
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 12)
                            dateAndTagsContent
                                .padding(.horizontal, 16)

                            contentArea
                                // Follow the actual speech, not a viewport-sized
                                // empty area that pushes new notes off the top.
                                .frame(maxWidth: .infinity, minHeight: isRecordingThisNote ? 0 : max(400, geometry.size.height - 150))
                                .padding(.top, 8)
                        }
                        .padding(.bottom, detailBottomPadding)
                        .id(detailScrollTopAnchorID)

                        Color.clear
                            .frame(height: 1)
                            .id(detailScrollBottomAnchorID)
                    }
                    .coordinateSpace(name: "scroll")
                    .onScrollPhaseChange { _, phase in
                        transcriptFollow.scrollPhaseChanged(isUserScrolling: phase != .idle && phase != .animating)
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height >=
                            geometry.contentSize.height + geometry.contentInsets.bottom - 40
                    } action: { _, atBottom in
                        transcriptFollow.bottomChanged(atBottom)
                    }
                    .task(id: [viewModel.recorder.transcription, String(selectedTab), note.objectID.uriRepresentation().absoluteString, String(isRecordingThisNote)]) {
                        guard isRecordingThisNote, selectedTab == DetailTab.transcript.rawValue,
                              transcriptFollow.shouldFollow else { return }
                        await Task.yield()
                        guard !Task.isCancelled, transcriptFollow.shouldFollow else { return }
                        scrollProxy.scrollTo(detailScrollBottomAnchorID, anchor: .bottom)
                    }

                    // Reveal the beginning once when generation opens. Streaming
                    // updates must not pull the reader down to the growing end.
                    .task(id: [String(isGeneratingThisSummary), String(selectedTab), note.objectID.uriRepresentation().absoluteString]) {
                        guard isGeneratingThisSummary, selectedTab == DetailTab.summary.rawValue else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scrollProxy.scrollTo(detailScrollTopAnchorID, anchor: .top)
                    }
                }
            .scrollIndicators(.visible) // Make scrollbars visible

            } // End of VStack
        } // End of GeometryReader
        .overlay( alignment: .top) { detailOverlay1 }
        .overlay( alignment: .bottom) { detailOverlay5 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRecordingThisNote)
        .onAppear {
            showActionsPopover = false
            // Load templates when view appears
            if availableTemplates.isEmpty {
                loadTemplates()
            }
        }
        .onChange(of: note.objectID) { _, _ in
            transcriptFollow = MacTranscriptFollowState()
            showActionsPopover = false
        }
        .onChange(of: viewModel.recorder.isRecording) { _, isRecordingNow in

            if isRecordingNow {
                showActionsPopover = false
            }
        }
        .onChange(of: viewModel.isTranscriptionPaused) { _, isPaused in

            if isPaused {
                showActionsPopover = false
            }
        }
    }

    @ViewBuilder var detailOverlay1: some View {

            // Top toolbar with tab buttons
            HStack(spacing: 0) {
                    Spacer()

                    // Center - Tab buttons (hidden during recording)
                    HStack(spacing: 6) {
                        // Summary tab: show only when a real summary exists
                        // (or one is actively being generated). Recovery path
                        // for empty states lives on the Transcript tab via
                        // its "Generate Summary" footer button.
                        let isGeneratingSummaryForThisNote =
                            (viewModel.isGeneratingSummary && viewModel.generatingSummaryNoteID == note.objectID) ||
                            note.summary?.trimmingCharacters(in: .whitespacesAndNewlines) == "Generating summary..."
                        if !isRecordingThisNote && (hasSummary || isGeneratingSummaryForThisNote || hasContentToSummarize) {
                            NoteContentSwitch(selection: Binding(
                                get: { selectedTab == DetailTab.summary.rawValue ? "Summary" : "Transcript" },
                                set: { selectedTab = $0 == "Summary" ? DetailTab.summary.rawValue : DetailTab.transcript.rawValue }),
                                showsSummary: hasSummary || isGeneratingSummaryForThisNote,
                                showsTranscript: hasContentToSummarize, summaryIsGenerating: isGeneratingSummaryForThisNote)
                        }

                        if isRecordingOnAnotherNote {
                            jumpToRecordingTabButton
                        }
                    }
                    .fixedSize() // Prevent tabs from wrapping

                    Spacer()

                    // Right side - More menu
                    moreMenuButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 0)
            .background(Color.themeContentBackground)
            .zIndex(100) // Ensure toolbar is always on top

    }

    @ViewBuilder var detailOverlay5: some View {

            if selectedTab == DetailTab.summary.rawValue && note.hasMeaningfulSummaryText &&
                !viewModel.recorder.isRecording && !isGeneratingThisSummary && !viewModel.operationInProgress {
                MacSummaryActionsFooter(
                    isEnabled: !hasActiveRecordingSession && !viewModel.recorder.isBusy &&
                        !viewModel.isGeneratingSummary && !LocalAppModel.shared.busy,
                    onAsk: { showingAskAI = true }
                )
                .padding(.horizontal, 14).padding(.vertical, 14).padding(.trailing, 16)

            }

            // Transcript actions remain on the Transcript tab.
            if selectedTab == DetailTab.transcript.rawValue && !viewModel.recorder.isRecording && !isGeneratingThisSummary && !viewModel.operationInProgress {
                let transcript = editableTranscript
                // Per-note saved-audio loading flag (not a persisted placeholder) so the
                // action footer stays hidden while saved audio is being transcribed.
                let isLoading = viewModel.isTranscriptLoading(for: note)
                let supportsTranscription = true
                let hasContent = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let isGenerating = viewModel.isGeneratingSummary && viewModel.generatingSummaryNoteID == note.objectID

                if !isLoading && (supportsTranscription || hasContent) {
                    HStack(spacing: 12) {
                        if supportsTranscription {
                            Button {
                                Task { @MainActor in
                                    await viewModel.resumeTranscriptionOnNote(note: note)
                                }
                            } label: {
                                Label("Continue Transcription", systemImage: "mic.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.themePrimaryAccent)
                            }
                            .buttonStyle(JotleyGlassButtonStyle())
                            .accessibilityIdentifier("noteDetailTranscriptResumeButton")
                        }

                        if hasContent && !note.hasMeaningfulSummaryText {
                            Button {
                                // Always generate with Auto. A specific template is
                                // chosen from the template menu (actions popover),
                                // which appears once a summary exists.
                                Task { @MainActor in
                                    await handleSummarizeAction(templateKey: "default-summary")
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isGenerating {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.themePrimaryAccent)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 13, weight: .semibold))
                                    }

                                    Text(isGenerating ? "Generating..." : "Generate Summary")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Color.themePrimaryAccent)
                            }
                            .buttonStyle(JotleyGlassButtonStyle())
                            .disabled(isGenerating)
                            .accessibilityIdentifier("noteDetailTranscriptSummarizeButton")
                            if isGenerating { Button("Cancel") { viewModel.cancelInference() }.buttonStyle(.plain) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .padding(.trailing, 16) // Leave space for scrollbar

                }
            }

    }
}


struct MacSummaryActionsFooter: View {
    let isEnabled: Bool
    let onAsk: () -> Void

    var body: some View {
        Button(action: onAsk) {
            Label {
                Text("Ask AI").foregroundStyle(Color.themePrimaryAccent)
            } icon: {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(Color.themePrimaryAccent)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .accessibilityIdentifier("noteDetailSummaryAskAIButton")
        .buttonStyle(JotleyGlassButtonStyle()).disabled(!isEnabled)
    }
}
