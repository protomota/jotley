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

    var detailScrollBottomAnchorID: String {
        "note-detail-live-bottom-anchor"
    }

    var liveFollowJumpButtonSize: CGFloat {
        32
    }

    var liveFollowControlSpacing: CGFloat {
        8
    }

    var shouldShowLiveFollowControls: Bool {
        isRecordingThisNote &&
        selectedTab == DetailTab.transcript.rawValue
    }

    var liveCaptionSourceText: String {
        let accumulated = viewModel.recorder.accumulatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let interim = viewModel.recorder.latestTranscriptDelta.trimmingCharacters(in: .whitespacesAndNewlines)

        if !accumulated.isEmpty && !interim.isEmpty {
            return "\(accumulated)\n\(interim)"
        }

        if !interim.isEmpty {
            return interim
        }

        return accumulated
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
                                .frame(maxWidth: .infinity, minHeight: max(400, geometry.size.height - 150))
                                .padding(.top, 8)
                        }
                        .padding(.bottom, isRecordingThisNote ? 92 : 16) // Extra padding for floating recording controls

                        Color.clear
                            .frame(height: 1)
                            .id(detailScrollBottomAnchorID)
                    }
                    .coordinateSpace(name: "scroll")
                    .onAppear {
                        detailScrollProxy = scrollProxy
                        scheduleDetailScrollStateUpdate()
                    }
                    .task(id: viewModel.streamingSummaryViewModel.summary) {
                        guard isGeneratingThisSummary, selectedTab == DetailTab.summary.rawValue else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scrollProxy.scrollTo(detailScrollBottomAnchorID, anchor: .bottom)
                    }
                    .onChange(of: viewModel.isGeneratingSummary) { _, running in
                        if running, isGeneratingThisSummary, selectedTab == DetailTab.summary.rawValue {
                            scrollProxy.scrollTo(detailScrollBottomAnchorID, anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.recorder.accumulatedTranscript) { _, _ in
                        scheduleDetailScrollStateUpdate()
                    }
                    .onChange(of: viewModel.recorder.latestTranscriptDelta) { _, _ in
                        scheduleDetailScrollStateUpdate()
                    }
                    .onChange(of: note.transcription) { _, _ in
                        scheduleDetailScrollStateUpdate()
                    }
                    .onChange(of: selectedTab) { _, _ in
                        scheduleDetailScrollStateUpdate()
                    }
                    .onChange(of: isRecordingThisNote) { _, _ in
                        scheduleDetailScrollStateUpdate()
                    }
                }
            .scrollIndicators(.visible) // Make scrollbars visible

            } // End of VStack
        } // End of GeometryReader
        .overlay( alignment: .top) { detailOverlay1 }
        .overlay( alignment: .bottom) { detailOverlay2 }
        .overlay( alignment: .bottom) { detailOverlay3 }
        .overlay( alignment: .bottom) { detailOverlay4 }
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
                        if (hasSummary || isGeneratingSummaryForThisNote) && !isRecordingThisNote {
                            summarizeFloatingButton
                        }

                        if hasContentToSummarize && !isRecordingThisNote {
                            transcriptTabButton
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

    @ViewBuilder var detailOverlay2: some View {

            // Gradient background for recording controls and captions
            if isRecordingThisNote {
                LinearGradient(
                    colors: [
                        Color.themeContentBackground.opacity(0),
                        Color.themeContentBackground.opacity(0.85),
                        Color.themeContentBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .padding(.trailing, 16) // Leave space for scrollbar
                .allowsHitTesting(false)
            }

    }

    @ViewBuilder var detailOverlay3: some View {

            // Recording controls - only visible when recording
            if isRecordingThisNote {
                NoteRecordingControls(
                    timerText: formatTimeInterval(viewModel.recorder.elapsedTime),
                    appIcon: viewModel.recorder.icon,
                    audioLevel: viewModel.recorder.currentAudioLevel,
                    isPaused: viewModel.isTranscriptionPaused,
                    onPause: { Task { await viewModel.resumeTranscription() } },
                    onStop: { Task { @MainActor in await stopRecordingAndShowTemplateSheet() } }
                )
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

    }

    @ViewBuilder var detailOverlay4: some View {

            if shouldShowLiveFollowControls {
                HStack(alignment: .center, spacing: liveFollowControlSpacing) {
                    if showLiveCaptions {
                        // Keep left and right side widths balanced so the caption bubble
                        // stays centered with the main recording controls.
                        Color.clear
                            .frame(width: liveFollowJumpButtonSize, height: liveFollowJumpButtonSize)

                        LiveTranscriptDeltaBubble(
                            latestWords: liveCaptionSourceText,
                            isVisible: shouldShowLiveFollowControls
                        )
                        .frame(maxWidth: 300)
                    }

                    Button {
                        scrollToLatestTranscription()
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: liveFollowJumpButtonSize, height: liveFollowJumpButtonSize)
                            .background(
                                Circle()
                                    .fill(Color.themePrimaryAccent)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .floatingTooltip("Jump to latest transcript")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, isRecordingThisNote ? 70 : 16)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

    }

    @ViewBuilder var detailOverlay5: some View {

            // Transcript action footer — pinned to bottom of window, outside the ScrollView
            if selectedTab == DetailTab.transcript.rawValue && !isRecordingThisNote && !isGeneratingThisSummary && !viewModel.operationInProgress {
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
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .frame(minWidth: 180)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.themePrimaryAccent)
                                    )
                            }
                            .buttonStyle(.plain)
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
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 13, weight: .semibold))
                                    }

                                    Text(isGenerating ? "Generating..." : "Generate Summary")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .frame(minWidth: 180)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.themePrimaryAccent)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isGenerating)
                            .accessibilityIdentifier("noteDetailTranscriptSummarizeButton")
                            if isGenerating { Button("Cancel") { viewModel.cancelInference() }.buttonStyle(.plain) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .padding(.trailing, 16) // Leave space for scrollbar
                    .background(
                        LinearGradient(
                            colors: [
                                Color.themeContentBackground.opacity(0),
                                Color.themeContentBackground.opacity(0.85),
                                Color.themeContentBackground
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .padding(.trailing, 16) // Leave space for scrollbar
                        .allowsHitTesting(false),
                        alignment: .bottom
                    )
                }
            }

    }
}

/// The note's live controls size to their content instead of compressing Stop
/// into a fixed-width container. Also used by hardware-free layout checks.
struct NoteRecordingControls: View {
    let timerText: String
    let appIcon: NSImage?
    let audioLevel: Float
    let isPaused: Bool
    let onPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Recording indicator with audio animation
            RecordingIndicator(
                appIcon: appIcon,
                isRecording: true,
                audioLevel: !isPaused ? audioLevel : 0,
                size: 22,
                isPaused: isPaused
            )
            .frame(width: 22, height: 32)

            Rectangle()
                .fill(Color.themeAccent.opacity(0.35))
                .frame(width: 1, height: 18)

            // Timer
            Text(timerText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(Color.themeTextPrimary)
                .lineLimit(1)
                .frame(minWidth: 50, minHeight: 32, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            Button(action: onPause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(Color.themeTextPrimary)
                    .frame(width: 28, height: 32)
            }.buttonStyle(.plain).help(isPaused ? "Resume transcription" : "Pause transcription")
            .accessibilityIdentifier("recordingPauseButton")
            // Stop button
            Button(action: onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(Color.themePrimaryAccent)
                )
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityIdentifier("recordingStopButton")
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.themeContentBackground.opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.themeAccent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
    }
}
