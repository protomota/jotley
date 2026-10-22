import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {
    var headerContent: some View {
        ThemedTextField(
            text: $manualTitle,
            placeholder: "Enter a title...",
            font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            textColor: NSColor(Color.themeTextPrimary),
            onCommit: {
                let trimmed = manualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && note.title != trimmed {
                    note.title = trimmed
                    do {
                        try persistenceController.save()
                    } catch {
                        viewModel.report(error)
                    }
                }
            },
            maxLines: 2
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("noteDetailTitle")
        .onAppear {
            manualTitle = note.titleOrUntitled
            // Load tags directly, they are already formatted and de-duplicated in CoreData
            currentTags = note.tagsAsString?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted() ?? []
            currentTags.sort()
            // When appearing, ensure we're showing original transcript if this note is being recorded
            let vm = viewModel
            if vm.recorder.isRecording &&
               vm.newNoteBeingRecorded == note {
                // REMOVED preferCleanedTranscript = false
            }
        }
        .onChange(of: note.title) { _, _ in
            manualTitle = note.titleOrUntitled
        }
        .onChange(of: note.objectID) { _, _ in
            manualTitle = note.titleOrUntitled
            editableSummary = note.summary ?? ""
            editableTranscript = note.transcription ?? ""
            // Load tags directly, they are already formatted and de-duplicated in CoreData
            currentTags = note.tagsAsString?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted() ?? []
            currentTags.sort()
            // Don't reset preferCleanedTranscript, since we want it to be sticky
        }
        .onChange(of: manualTitle) { _, newText in
            let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && note.title != trimmed {
                note.title = trimmed
                do { try persistenceController.save() } catch { viewModel.report(error) }
            }
        }
        .onChange(of: note.tagsAsString) { _, newTags in
            // Load tags directly, they are already formatted and de-duplicated in CoreData
            currentTags = newTags?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted() ?? []
        }
    }

    var dateAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: date + folder + collapsed tag summary
            HStack(alignment: .center, spacing: 12) {
                createdDateText

                folderChip

                if showTags {
                    collapsedTagHeader
                }

                Spacer()
            }

            // Expanded tag flow (shown below the top row when expanded)
            if showTags && isTagsExpanded {
                expandedTagsContent
            }
        }
        .padding(.bottom, 6)
    }

    /// Compact clickable tag summary: "🏷 N tags >" or "+ Add Tag"
    @ViewBuilder
    private var collapsedTagHeader: some View {
        if currentTags.isEmpty && !isEditingTags {
            Button {
                isEditingTags = true
                showAddTagPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Tag")
                        .font(.caption)
                }
                .foregroundColor(Color.themeTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAddTagPopover, arrowEdge: .bottom) {
                AddTagPopoverView(
                    note: note,
                    showPopover: $showAddTagPopover,
                    newTagText: $newTagText,
                    currentTags: $currentTags,
                    isEditingTags: $isEditingTags,
                    saveContext: { self.saveContext() }
                )
                .frame(idealWidth: 250)
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTagsExpanded.toggle()
                }
                if isTagsExpanded {
                    isEditingTags = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(currentTags.count) \(currentTags.count == 1 ? "tag" : "tags")")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isTagsExpanded ? 90 : 0))
                }
                .foregroundColor(Color.themeTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
        }
    }

    /// Full tag flow layout with edit/add controls.
    private var expandedTagsContent: some View {
        FlowLayout(spacing: 6) {
            ForEach(currentTags, id: \.self) { tag in
                TagView(tag: tag,
                        isEditing: isEditingTags,
                        onRemove: {
                            self.removeTag(tag)
                        })
            }

            if isEditingTags && currentTags.count < 10 {
                Button {
                    showAddTagPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color.themePrimaryAccent)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showAddTagPopover, arrowEdge: .bottom) {
                    AddTagPopoverView(
                        note: note,
                        showPopover: $showAddTagPopover,
                        newTagText: $newTagText,
                        currentTags: $currentTags,
                        isEditingTags: $isEditingTags,
                        saveContext: { self.saveContext() }
                    )
                    .frame(idealWidth: 250)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .onTapGesture {
            isEditingTags.toggle()
        }
    }

    var createdDateText: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .medium))

            HStack(spacing: 6) {
                Text(formatDatePart(note.timestampOrNow))
                    .font(.system(size: 11, weight: .medium))

                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1, height: 12)

                Text(formatTimePart(note.timestampOrNow))
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundColor(Color.gray)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            Capsule()
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        )
    }

    func formatDatePart(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    func formatTimePart(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    var contentArea: some View {
        // Note-scoped summary loading binding to prevent cross-note loader bleed.
        let isGeneratingSummaryBinding = Binding(
            get: {
                viewModel.isGeneratingSummary &&
                viewModel.generatingSummaryNoteID == note.objectID
            },
            set: { newValue in
                if newValue {
                    viewModel.beginSummaryGeneration(for: note.objectID)
                } else {
                    viewModel.endSummaryGeneration(for: note.objectID)
                }
            }
        )

        return Group {
            if isEditingTranscript && selectedTab == DetailTab.transcript.rawValue {
                LocalMacTranscriptEditor(note: note, viewModel: viewModel) {
                    isEditingTranscript = false
                }
                .environmentObject(persistenceController)
            } else {
                DetailTabPanel(
                    note: note,
                    selectedTab: $selectedTab,
                    isGeneratingSummary: isGeneratingSummaryBinding,
                    summaryGenerationError: $summaryGenerationError,
                    editableSummary: $editableSummary,
                    isSummaryEditorFocused: $isSummaryEditorFocused,
                    summaryInlineEditRequestCounter: $summaryInlineEditRequestCounter,
                    editableTranscript: $editableTranscript,
                    isTranscriptEditorFocused: $isTranscriptEditorFocused,
                    showRawMarkdown: bindingForCurrentTabShowRawMarkdown,
                    viewModel: viewModel,
                    // Note-scoped saved-audio loading flag — drives the transcript spinner without
                    // a persisted placeholder. Read here (where the VM is observed) so the
                    // value flips trigger a re-render down through DetailTabPanel.
                    isTranscriptLoading: viewModel.isTranscriptLoading(for: note),
                    summaryLoadingStartedAt: viewModel.summaryLoadingStartedAt(for: note.objectID),
                    streamingSummaryViewModel: viewModel.streamingSummaryViewModel
                )
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // Computed property to select the correct binding for the current tab
    var bindingForCurrentTabShowRawMarkdown: Binding<Bool> {
        switch DetailTab(rawValue: selectedTab) {
        case .summary:
            return $showRawMarkdownSummary
        case .transcript:
            return .constant(false) // Transcript is always in bubble view
        case .none:
            return .constant(false)
        }
    }
}
