import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {
    // Action popover content
    var actionPopoverContentView: some View {
        CustomMoreMenu(parent: self, viewModel: viewModel, note: note, isPresented: $showActionsPopover)
    }

    struct CustomMoreMenu: View {
        let parent: NoteDetailPlaceholderView
        @ObservedObject var viewModel: NotesListViewModel
        let note: Note
        @Binding var isPresented: Bool
        @State private var showTemplateSubmenu = false
        @State private var showExportSubmenu = false
        @State private var templateMenuFrame: CGRect = .zero
        private let mainMenuWidth: CGFloat = 260
        private let templateSubmenuWidth: CGFloat = 260
        private let submenuGap: CGFloat = 2

        // Get the current template name from note.summaryType
        private var currentTemplateName: String {
            let templateKey = LocalSummaryTemplate.resolve(note.summaryType).key
            if templateKey == "default-summary" {
                return "Auto"
            }
            return parent.availableTemplates.first { $0.key == templateKey }?.title ?? "Auto"
        }

        private var hasSummary: Bool {
            guard let summary = note.summary else { return false }
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSummary.isEmpty else { return false }

            return trimmedSummary != "Transcription in progress..." && trimmedSummary != "Generating summary..."
        }

        private var showsSummaryActions: Bool {
            parent.selectedTab == DetailTab.summary.rawValue && hasSummary && !isRecordingThisNote
        }

        private var isTranscriptTab: Bool {
            parent.selectedTab == DetailTab.transcript.rawValue
        }

        private var isRecordingThisNote: Bool {
            viewModel.recorder.isRecording &&
            viewModel.recorder.isRecordingNewNote &&
            viewModel.newNoteBeingRecorded == note
        }

        private var liveTranscriptForCopy: String {
            let finalized = viewModel.recorder.accumulatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            let interim = viewModel.recorder.latestTranscriptDelta.trimmingCharacters(in: .whitespacesAndNewlines)

            if !finalized.isEmpty && !interim.isEmpty {
                return "\(finalized)\n\n\(interim)"
            }

            if !finalized.isEmpty {
                return finalized
            }

            if !interim.isEmpty {
                return interim
            }

            return (note.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func applyTemplateAndRegenerate(_ templateKey: String) {
            isPresented = false
            guard LocalSummaryTemplate.resolve(note.summaryType).key != templateKey else { return }
            parent.selectedTemplateKeyForAction = templateKey
            parent.currentSelectedTemplate = parent.availableTemplates.first { $0.key == templateKey } ??
                Template(
                    key: "default-summary",
                    title: "Auto",
                    description: "General content with structured key points",
                    category: nil
                )

            Task {
                await parent.handleSummarizeAction(templateKey: templateKey)
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                if showsSummaryActions {
                    SummaryDisplayStylePicker()
                        .pickerStyle(.menu)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                if isRecordingThisNote {
                    MenuItemView(
                        icon: "doc.on.doc",
                        title: "Copy",
                        disabled: liveTranscriptForCopy.isEmpty
                    ) {
                        if !liveTranscriptForCopy.isEmpty {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(liveTranscriptForCopy, forType: .string)
                        }
                        isPresented = false
                    }
                } else {
                    if showsSummaryActions {
                        // Click to open/close template submenu.
                        MenuItemView(
                            icon: "sparkles",
                            title: "Template",
                            subtitle: currentTemplateName,
                            hasSubmenu: true,
                            submenuExpanded: showTemplateSubmenu
                        ) {
                            if showTemplateSubmenu {
                                showTemplateSubmenu = false
                            } else {
                                if parent.availableTemplates.isEmpty {
                                    parent.loadTemplates()
                                }
                                showTemplateSubmenu = true
                            }
                        }
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        templateMenuFrame = geometry.frame(in: .local)
                                    }
                            }
                        )
                    }

                    if showsSummaryActions {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    MenuItemView(icon: "bubble.left.and.bubble.right", title: "Ask AI",
                        disabled: (!parent.hasContentToSummarize && !hasSummary) || parent.hasActiveRecordingSession || viewModel.isGeneratingSummary) {
                        isPresented = false
                        parent.showingAskAI = true
                    }.accessibilityIdentifier("noteDetailAskAIMenuItem")

                    // Copy — context-aware, copies current tab content
                    MenuItemView(
                        icon: "doc.on.doc",
                        title: "Copy",
                        subtitle: DetailTab(rawValue: parent.selectedTab)?.title
                    ) {
                        parent.copyCurrentTabContent()
                        isPresented = false
                    }

                    // Save to File — inline-expanding submenu
                    MenuItemView(
                        icon: "square.and.arrow.up",
                        title: "Save to File...",
                        hasSubmenu: true,
                        submenuExpanded: showExportSubmenu
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showExportSubmenu.toggle()
                        }
                    }

                    if showExportSubmenu {
                        if showsSummaryActions {
                            MenuItemView(
                                icon: "doc.richtext",
                                title: "Summary as PDF"
                            ) {
                                parent.exportSummaryPDF()
                                isPresented = false
                            }
                            .accessibilityIdentifier("exportSummaryPDFButton")

                            MenuItemView(
                                icon: "text.badge.checkmark",
                                title: "Summary Only"
                            ) {
                                parent.exportSummary()
                                isPresented = false
                            }
                            .accessibilityIdentifier("exportSummaryButton")
                        }

                        if isTranscriptTab, let transcription = note.transcription,
                           !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            MenuItemView(
                                icon: "text.badge.checkmark",
                                title: "Transcript Only"
                            ) {
                                parent.exportTranscript()
                                isPresented = false
                            }
                            .accessibilityIdentifier("exportTranscriptButton")
                        }

                        MenuItemView(
                            icon: "doc.plaintext",
                            title: "Full Note (Plain Text)"
                        ) {
                            parent.exportAsPlainText()
                            isPresented = false
                        }

                        MenuItemView(
                            icon: "text.badge.checkmark",
                            title: "Full Note (Formatted)"
                        ) {
                            parent.exportAsMarkdown()
                            isPresented = false
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    if isTranscriptTab && parent.hasContentToSummarize {
                        MenuItemView(icon: "pencil", title: "Edit Transcript",
                            disabled: parent.hasActiveRecordingSession || viewModel.recorder.isBusy ||
                                viewModel.operationInProgress || viewModel.isGeneratingSummary || LocalAppModel.shared.busy) {
                            parent.selectedTab = DetailTab.transcript.rawValue
                            parent.isEditingTranscript = true
                            isPresented = false
                        }.accessibilityIdentifier("noteDetailEditTranscriptMenuItem")
                    }

                    if showsSummaryActions {
                        MenuItemView(
                            icon: "pencil",
                            title: "Edit Summary",
                            disabled: parent.hasActiveRecordingSession || viewModel.isGeneratingSummary
                        ) {
                            parent.requestSummaryInlineEdit()
                            isPresented = false
                        }
                        .accessibilityIdentifier("noteDetailEditSummaryMenuItem")
                    }

                    // Delete
                    MenuItemView(
                        icon: "trash",
                        title: "Delete",
                        isDestructive: true
                    ) {
                        isPresented = false
                        viewModel.performContextualDelete(for: note)
                    }
                }
            }
            .padding(6)
            .frame(width: mainMenuWidth)
            .modifier(MacNoteMenuSurface())
            .overlay(alignment: .topLeading) {
                if showTemplateSubmenu && showsSummaryActions {
                    TemplateSubmenu(
                        note: note,
                        availableTemplates: parent.availableTemplates,
                        onSelectTemplate: { templateKey in
                            applyTemplateAndRegenerate(templateKey)
                        }
                    )
                    .offset(
                        x: -(templateSubmenuWidth + submenuGap),
                        y: max(0, templateMenuFrame.minY - 8)
                    )
                }
            }
            .zIndex(1)
            .onChange(of: parent.selectedTab) { _, _ in
                showTemplateSubmenu = false
                showExportSubmenu = false
            }
            .onDisappear {
                showTemplateSubmenu = false
                showExportSubmenu = false
            }
        }
    }

}
