import SwiftUI

extension NoteDetailView {
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                noteHeaderSection
                if hasTranscript || hasSummary { noteTabPickerSection }
                if selectedTab == "Summary", hasSummary {
                    if summaryIsRunning && transcriptionManager.summaryPreview.isEmpty {
                        Text("Long transcripts are reviewed in sections on this device. Your summary will appear here as it is written.")
                            .font(.body).foregroundColor(.themeTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    } else {
                        MarkdownContentView(content: summaryIsRunning ? transcriptionManager.summaryPreview : note.summary ?? "")
                            .padding(.horizontal).accessibilityIdentifier("noteDetailSummaryContent")
                    }
                } else if hasTranscript || noteIsTranscribing {
                    transcriptContent.padding(.horizontal)
                } else {
                    ContentUnavailableView("No Words Yet", systemImage: "text.bubble", description: Text("Tap Continue Transcription to add spoken words to this note."))
                }
            }
            .padding(.bottom, 16)
            Color.clear.frame(height: 1).id("summaryBottom")
        }
        .task(id: transcriptionManager.summaryPreview) {
            guard summaryIsRunning, selectedTab == "Summary", scenePhase == .active else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            proxy.scrollTo("summaryBottom", anchor: .bottom)
        }
        .onChange(of: summaryIsRunning) { _, running in
            if running { proxy.scrollTo("summaryBottom", anchor: .bottom) }
        }
        }
        .background(Color.themeBackground)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if summaryIsRunning {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ProgressView().tint(.themePrimaryAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(transcriptionManager.summaryProgress.title).font(.body.weight(.semibold))
                            if let detail = transcriptionManager.summaryProgress.detail {
                                Text(detail).font(.subheadline).foregroundColor(.themeTextSecondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("noteDetailSummaryProgress")
                    if let fraction = transcriptionManager.summaryProgress.fraction {
                        ProgressView(value: fraction).tint(.themePrimaryAccent)
                    }
                    Button { transcriptionManager.cancelProcessing() } label: {
                        Label("Cancel Generation", systemImage: "xmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered)
                        .accessibilityIdentifier("noteDetailCancelGenerationButton")
                }
                    .padding(.horizontal,16).padding(.vertical,8).background(Color.themeBackground)
            } else { transcriptionAndSummaryFooter }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = selectedTab == "Summary" ? note.summary : note.transcription }
                        .accessibilityIdentifier("copyCurrentTabButton")
                    Button("Share as Text", systemImage: "square.and.arrow.up", action: shareAsText)
                        .accessibilityIdentifier("shareNoteButton")
                    Divider()
                    Menu("More Export Options", systemImage: "ellipsis.circle") {
                        Button("Full Note (Plain Text)") { export(.plainText) }.accessibilityIdentifier("exportPlainTextButton")
                        Button("Full Note (Formatted)") { export(.markdown) }.accessibilityIdentifier("exportMarkdownButton")
                        if Note.isMeaningfulSummaryText(note.summary) {
                            Button("Summary Only") { export(.summary) }.accessibilityIdentifier("exportSummaryButton")
                        }
                        if !transcript.isEmpty {
                            Button("Transcript Only") { export(.transcript) }.accessibilityIdentifier("exportTranscriptButton")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 19)).foregroundColor(.themePrimaryAccent)
                }
                .accessibilityLabel("Share Actions").accessibilityIdentifier("noteDetailShareButton")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Ask AI", systemImage: "bubble.left.and.bubble.right") { showingAskAI = true }
                        .disabled((!hasTranscript && !hasSummary) || noteIsTranscribing || summaryIsRunning)
                        .accessibilityIdentifier("noteDetailAskAIButton")
                    if hasTranscript {
                        Button("Edit Transcript", systemImage: "pencil") { showingTranscriptEditor = true }
                            .disabled(!transcriptionManager.canStart)
                            .accessibilityIdentifier("noteDetailEditTranscriptButton")
                    }
                    if Note.isMeaningfulSummaryText(note.summary) {
                        Button("Edit Summary", systemImage: "pencil") { showingSummaryEditor = true }
                            .disabled(!transcriptionManager.canStart)
                            .accessibilityIdentifier("noteDetailEditSummaryButton")
                    }
                    Button("Continue Transcription", systemImage: "mic.fill") { showingTranscription = true }
                        .disabled(!transcriptionManager.canStart && !noteIsTranscribing)
                        .accessibilityIdentifier("noteDetailContinueTranscriptionMenuButton")
                    Divider()
                    Button("Delete Note", role: .destructive) { showingDelete = true }.disabled(!transcriptionManager.canStart)
                } label: { Image(systemName: "ellipsis.circle.fill").font(.system(size: 22)).foregroundColor(.themePrimaryAccent) }
                .accessibilityIdentifier("noteDetailMoreActionsButton")
            }
        }
        .sheet(isPresented: $showingTranscriptEditor, onDismiss: { selectedTab = "Transcript" }) { MobileNoteTextEditor(note: note, field: .transcript) }
        .sheet(isPresented: $showingSummaryEditor, onDismiss: { selectedTab = hasSummary ? "Summary" : "Transcript" }) { MobileNoteTextEditor(note: note, field: .summary) }
        .sheet(isPresented: $showingAskAI) { LocalAskNoteView(note: note) }
        .sheet(isPresented: $showingTranscription, onDismiss: { selectedTab = "Transcript" }) { LiveTranscriptionView(isPresented: $showingTranscription, existingNote: note) }
        .sheet(isPresented: $showingAddTag) {
            AddTagSheetView(note: note, isPresented: $showingAddTag, newTagText: $newTagText, currentTags: $currentTags, onSave: transcriptionManager.saveEdits)
        }
        .sheet(item: $exportPayload, onDismiss: clearExport) { payload in ShareSheet(activityItems: payload.items) }
        .alert("Delete Note", isPresented: $showingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                do { try transcriptionManager.delete(note); dismiss() } catch { transcriptionManager.errorMessage = error.localizedDescription }
            }
        } message: { Text("This permanently deletes the note.") }
        .onAppear { currentTags = note.tagNames; if hasSummary { selectedTab = "Summary" } }
        .onChange(of: isTitleFieldFocused) { _, focused in if !focused { isEditingTitle = false } }
        .onChange(of: hasSummary) { _, available in if !available { selectedTab = "Transcript" } }
        .onChange(of: summaryIsRunning) { _, running in if running { selectedTab = "Summary" } }
        .tint(.themePrimaryAccent)
        .observeThemeChanges()
    }
    private var noteHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if isEditingTitle {
                    TextField("Untitled", text: $editedTitle)
                        .focused($isTitleFieldFocused).submitLabel(.done)
                        .accessibilityIdentifier("noteDetailTitleEditor")
                        .onChange(of: editedTitle) { _, value in note.title = value; transcriptionManager.saveEdits() }
                        .onSubmit { isEditingTitle = false; isTitleFieldFocused = false }
                } else {
                    Text(note.title ?? "Untitled").accessibilityIdentifier("noteDetailTitle")
                        .onTapGesture { editedTitle = note.title ?? ""; isEditingTitle = true; isTitleFieldFocused = true }
                }
            }.font(.title2.bold()).foregroundColor(Color(uiColor: .label)).padding(.horizontal)
            if let timestamp = note.timestamp {
                Text(timestamp, format: .dateTime.weekday(.wide).month(.wide).day().year().hour(.defaultDigits(amPM: .abbreviated)).minute())
                    .font(.subheadline).foregroundColor(.themeTextSecondary).padding(.horizontal)
                    .accessibilityIdentifier("noteDetailTimestamp")
            }
            iOSNoteFolderRow(note: note, onChange: transcriptionManager.saveEdits).padding(.horizontal).padding(.top,8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(currentTags, id: \.self) { tag in
                        iOSTagView(tag: tag, onRemove: { note.removeTagByName(tag); currentTags = note.tagNames; transcriptionManager.saveEdits() })
                    }
                    Button("Add Tag", systemImage: "plus.circle.fill") { showingAddTag = true }.font(.caption)
                }.padding(.horizontal)
            }.padding(.top,8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top,8).padding(.bottom,16)
    }
    private var noteTabPickerSection: some View {
        HStack(spacing: 8) {
            ForEach(hasSummary ? ["Summary", "Transcript"] : ["Transcript"], id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    Text(tab).font(.subheadline.weight(.medium)).lineLimit(1)
                        .padding(.horizontal,16).padding(.vertical,8)
                        .background(Capsule().fill(selectedTab == tab ? Color.themePrimaryAccent : Color(.systemGray5)))
                        .foregroundColor(selectedTab == tab ? .white : Color.themeTextSecondary)
                }.buttonStyle(.plain).accessibilityIdentifier("noteDetail\(tab)Tab")
            }
            Spacer()
        }.padding(.horizontal).padding(.bottom,16)
    }
    @ViewBuilder private var transcriptContent: some View {
        if !note.transcriptUtterances.isEmpty {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(note.transcriptUtterances) { utterance in
                    TranscriptBubbleView(text: utterance.text, timestampText: utterance.start.map { String(format: "%02d:%02d", Int($0) / 60, Int($0) % 60) }, allowsTextSelection: true)
                }
            }.accessibilityIdentifier("noteDetailTranscriptContent")
        } else {
            TranscriptBubbleView(text: transcript, allowsTextSelection: true)
                .accessibilityIdentifier("noteDetailTranscriptContent")
        }
    }
    private var transcriptionAndSummaryFooter: some View {
        VStack(spacing: 8) {
            if selectedTab == "Summary" {
                Button("Ask AI", systemImage: "bubble.left.and.bubble.right") { showingAskAI = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .disabled((!hasTranscript && !hasSummary) || noteIsTranscribing || summaryIsRunning)
                    .accessibilityIdentifier("noteDetailSummaryAskAIButton")
            } else {
                Button("Continue Transcription", systemImage: "waveform") { showingTranscription = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.bordered)
                    .disabled(!transcriptionManager.canStart && !noteIsTranscribing)
                    .accessibilityIdentifier("noteDetailContinueTranscriptionButton")
            }
            if hasTranscript {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(LocalSummaryTemplate.allCases) { template in
                            Button { selectTemplate(template) } label: {
                                if selectedTemplate == template { Label(template.title, systemImage: "checkmark") }
                                else { Text(template.title) }
                            }.accessibilityIdentifier("noteTemplate-\(template.key)")
                        }
                    } label: {
                        Label(selectedTemplate.title, systemImage: "sparkles")
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(width: 136, height: 44)
                    }.buttonStyle(.bordered).disabled(!transcriptionManager.canStart)
                        .accessibilityLabel("Templates: \(selectedTemplate.title)")
                        .accessibilityIdentifier("noteDetailTemplatesButton")
                    Button {
                        generateSummary()
                    } label: {
                        Text(hasSummary ? "Regenerate Summary" : "Generate Summary")
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                        .disabled(!transcriptionManager.canStart || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("noteDetailGenerateSummaryButton")
                }
            }
        }.padding(.horizontal,16).padding(.vertical,8).background(Color.themeBackground)
    }
}
