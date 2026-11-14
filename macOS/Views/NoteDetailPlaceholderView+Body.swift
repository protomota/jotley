import SwiftUI
import AppKit

enum MacNoteHeaderLayout {
    static let topInset: CGFloat = 16
    static let controlHeight: CGFloat = 36
    static let menuTopInset = topInset + controlHeight + 8
}

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
                detailHeaderControls

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
                                .frame(maxWidth: .infinity,
                                       minHeight: isRecordingThisNote || isEditingTranscript ? 0 : max(400, geometry.size.height - 150),
                                       alignment: .topLeading)
                                .padding(.top, 8)
                        }
                        .padding(.bottom, detailBottomPadding)
                        .id(detailScrollTopAnchorID)

                        Color.clear
                            .frame(height: 1)
                            .id(detailScrollBottomAnchorID)
                    }
                    .coordinateSpace(name: "scroll")
                    .modifier(JotleyTranscriptEdgeFade(background: .themeContentBackground,
                        showsBottomFade: false, isEnabled: isRecordingThisNote && selectedTab == DetailTab.transcript.rawValue))
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
        .overlay(alignment: .bottom) {
            detailOverlay5.animation(.smooth(duration: 0.25), value: viewModel.recorder.isRecording)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRecordingThisNote)
        .onAppear {
            showActionsPopover = false
            // Load templates when view appears
            if availableTemplates.isEmpty {
                loadTemplates()
            }
        }
        .sheet(item: $templatePresentation) { presentation in
            VStack(alignment: .trailing, spacing: 0) {
                Button("Done") { templatePresentation = nil }
                    .jotleyDismissButtonStyle()
                    .padding()
                if presentation == .create {
                    NewSummaryTemplateView(onSaved: { templatePresentation = nil }, onUse: { definition in
                        templatePresentation = nil
                        selectSummaryTemplate(definition)
                    })
                } else {
                    SummaryTemplatesView(onUse: { definition in
                        templatePresentation = nil
                        selectSummaryTemplate(definition)
                    })
                }
            }
            .frame(width: 900, height: 720)
            .environment(\.managedObjectContext, viewModel.persistenceController.context)
        }
        .onChange(of: note.objectID) { _, _ in
            transcriptFollow = MacTranscriptFollowState()
            isEditingTranscript = false
            showActionsPopover = false
            showsSummaryTemplatePicker = false
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

    @ViewBuilder var detailHeaderControls: some View {

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
            .frame(minHeight: MacNoteHeaderLayout.controlHeight)
            .padding(.horizontal, 16)
            .padding(.top, MacNoteHeaderLayout.topInset)
            .padding(.bottom, 12)
            .background(Color.themeContentBackground)

    }

    @ViewBuilder var detailOverlay5: some View {
            if viewModel.recorder.isRecording {
                MacCompactTranscriptionBar(viewModel: viewModel)
                    .matchedGeometryEffect(id: "transcription-footer", in: transcriptionFooterNamespace)
                    .modifier(MacNoteFooterPlacement())
                    .transition(.opacity)
            }

            if selectedTab == DetailTab.summary.rawValue && note.hasMeaningfulSummaryText &&
                !viewModel.recorder.isRecording && !isGeneratingThisSummary && !viewModel.operationInProgress {
                MacSummaryActionsFooter(
                    isEnabled: !hasActiveRecordingSession && !viewModel.recorder.isBusy &&
                        !viewModel.isGeneratingSummary && !LocalAppModel.shared.busy,
                    onAsk: { showingAskAI = true }
                )
                .modifier(MacNoteFooterPlacement())

            }

            // Transcript actions remain on the Transcript tab.
            if selectedTab == DetailTab.transcript.rawValue && !isEditingTranscript && !viewModel.recorder.isRecording && !isGeneratingThisSummary && !viewModel.operationInProgress {
                let transcript = editableTranscript
                // Per-note saved-audio loading flag (not a persisted placeholder) so the
                // action footer stays hidden while saved audio is being transcribed.
                let isLoading = viewModel.isTranscriptLoading(for: note)
                let hasContent = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let isGenerating = viewModel.isGeneratingSummary && viewModel.generatingSummaryNoteID == note.objectID

                if !isLoading {
                    VStack(spacing: 10) {
                        if hasContent && !note.hasMeaningfulSummaryText {
                            HStack(spacing: 8) {
                                summaryTemplateButton
                                Button {
                                    Task { await handleSummarizeAction(templateKey: summaryTemplateKey) }
                                } label: {
                                    Text("Generate Summary")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
                                .disabled(isGenerating || (try? templateCatalog.resolve(summaryTemplateKey)) == nil)
                                .accessibilityIdentifier("noteDetailTranscriptSummarizeButton")
                            }
                        }

                        Button {
                            Task { @MainActor in
                                await viewModel.resumeTranscriptionOnNote(note: note)
                            }
                        } label: {
                            Label {
                                Text("Continue Transcription").modifier(JotleyNoteFooterTextStyle())
                            } icon: {
                                Image(systemName: "waveform")
                            }
                            .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
                        .matchedGeometryEffect(id: "transcription-footer", in: transcriptionFooterNamespace)
                        .accessibilityIdentifier("noteDetailTranscriptResumeButton")
                    }
                    .modifier(MacNoteFooterPlacement())

                }
            }

    }

    private var summaryTemplateKey: String { note.summaryType ?? LocalSummaryTemplate.auto.key }

    private var summaryTemplateButton: some View {
        let title = templateCatalog.title(for: summaryTemplateKey)
        return Button {
            showsSummaryTemplatePicker.toggle()
        } label: {
            Label {
                Text(title).modifier(JotleyNoteFooterTextStyle())
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: 160)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
        .accessibilityLabel("Templates: \(title)")
        .accessibilityIdentifier("noteDetailTemplatesButton")
        .popover(isPresented: $showsSummaryTemplatePicker, arrowEdge: .bottom) {
            TemplateSubmenu(
                note: note,
                availableTemplates: availableTemplates,
                onSelectTemplate: { key in
                    showsSummaryTemplatePicker = false
                    if let definition = try? templateCatalog.resolve(key) {
                        selectSummaryTemplate(definition)
                    }
                },
                onManageTemplates: { create in
                    showsSummaryTemplatePicker = false
                    templatePresentation = create ? .create : .manage
                }
            )
            .padding(6)
            .presentationBackground(Color.themeContentBackground)
        }
    }

    private func selectSummaryTemplate(_ template: SummaryTemplateDefinition) {
        guard summaryTemplateKey != template.key else { return }
        if note.hasMeaningfulSummaryText {
            Task { await handleSummarizeAction(templateKey: template.key) }
        } else {
            note.summaryType = template.key
            saveContext()
        }
    }
}


struct MacSummaryActionsFooter: View {
    let isEnabled: Bool
    let onAsk: () -> Void

    var body: some View {
        Button(action: onAsk) {
            Label {
                Text("Ask AI").modifier(JotleyNoteFooterTextStyle())
            } icon: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(Color.themePrimaryAccent)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .accessibilityIdentifier("noteDetailSummaryAskAIButton")
        .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
        .disabled(!isEnabled)
    }
}
