import SwiftUI

extension NoteDetailView {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                noteHeaderSection
                if hasTranscript || hasSummary { noteTabPickerSection }
                if selectedTab == "Summary", hasSummary {
                    if summaryIsRunning && transcriptionManager.summaryPreview.isEmpty {
                        Text("Long transcripts are reviewed in sections on this device. Your summary will appear here as it is written. You can leave this note or lock your phone; the summary keeps going and is saved when it finishes.")
                            .font(.body).foregroundColor(.themeTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    } else {
                        StructuredSummaryView(content: summaryIsRunning ? transcriptionManager.summaryPreview : note.summary ?? "", isStreaming: summaryIsRunning)
                            .padding(.horizontal).accessibilityIdentifier("noteDetailSummaryContent")
                    }
                } else if hasTranscript || noteIsTranscribing {
                    transcriptContent.padding(.horizontal)
                } else {
                    ContentUnavailableView("No Words Yet", systemImage: "text.bubble", description: Text("Tap Continue Transcription to add spoken words to this note."))
                }
            }
            .padding(.bottom, actionsFooterHeight + 16)
        }
        .scrollPosition($summaryScrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { previous, height in
            guard isWritingVisibleSummary, followsLiveSummary, previous != height else { return }
            // Move only after the new text has a measured height.
            summaryScrollPosition.scrollTo(edge: .bottom)
        }
        .onScrollPhaseChange { _, phase, context in
            guard isWritingVisibleSummary else { return }
            if phase == .interacting {
                followsLiveSummary = false
            } else if phase == .idle {
                let geometry = context.geometry
                followsLiveSummary = geometry.visibleRect.maxY >= geometry.contentSize.height - 40
            }
        }
        .onChange(of: isWritingVisibleSummary) { _, writing in
            if !writing { followsLiveSummary = true }
        }
        .background(Color.themeBackground)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if newTranscriptionAction == nil {
                noteActionsFooter
            }
        }
        .preference(key: NoteFooterContentKey.self,
                    value: newTranscriptionAction != nil ? note.id.map { [$0: AnyView(noteActionsFooter)] } ?? [:] : [:])
        .sheet(isPresented: $showingTranscriptEditor, onDismiss: { selectedTab = "Transcript" }) { MobileNoteTextEditor(note: note, field: .transcript) }
        .sheet(isPresented: $showingSummaryEditor, onDismiss: { selectedTab = hasSummary ? "Summary" : "Transcript" }) { MobileNoteTextEditor(note: note, field: .summary) }
        .sheet(item: $templatePresentation) { presentation in
            NavigationStack {
                Group {
                    if presentation == .create {
                        NewSummaryTemplateView(onSaved: { templatePresentation = nil }, onUse: { definition in
                            templatePresentation = nil; selectTemplate(definition)
                        })
                    } else {
                        SummaryTemplatesView(onUse: { definition in templatePresentation = nil; selectTemplate(definition) })
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { templatePresentation = nil }
                            .jotleyDismissButtonStyle(inToolbar: true)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
        .sheet(isPresented: $showingAskAI) { LocalAskNoteView(note: note) }
        .sheet(isPresented: $showingTranscription, onDismiss: { selectedTab = "Transcript" }) { LiveTranscriptionView(isPresented: $showingTranscription, existingNote: note, transcriptionManager: transcriptionManager) }
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
        .onChange(of: note.tagNames) { _, tags in currentTags = tags }
        .onChange(of: isTitleFieldFocused) { _, focused in if !focused { isEditingTitle = false } }
        .onChange(of: hasSummary) { _, available in if !available { selectedTab = "Transcript" } }
        .onChange(of: summaryIsRunning) { _, running in if running { selectedTab = "Summary" } }
        .tint(.themeActionText)
        .observeThemeChanges()
    }
    private var isWritingVisibleSummary: Bool { summaryIsRunning && selectedTab == "Summary" }

    private var noteHeaderActions: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = selectedTab == "Summary" ? note.summary : note.transcription }
                    .accessibilityIdentifier("copyCurrentTabButton")
                Button("Share as Text", systemImage: "square.and.arrow.up", action: shareAsText)
                    .accessibilityIdentifier("shareNoteButton")
                if Note.isMeaningfulSummaryText(note.summary) {
                    Button("Share Summary as PDF", systemImage: "doc.richtext", action: shareSummaryPDF)
                        .disabled(summaryIsRunning)
                        .accessibilityIdentifier("shareSummaryPDFButton")
                }
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
                noteHeaderMenuLabel
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .overlay { noteHeaderMenuIcon("square.and.arrow.up", verticalOffset: -1.5) }
            .accessibilityLabel("Share Actions").accessibilityIdentifier("noteDetailShareButton")
            Menu {
                Button { showingAskAI = true } label: {
                    MobileActionLabel("Ask AI", systemImage: "bubble.left.and.bubble.right")
                }
                    .disabled((!hasTranscript && !hasSummary) || noteIsTranscribing || summaryIsRunning)
                    .accessibilityIdentifier("noteDetailAskAIButton")
                Menu("Summary Style", systemImage: "text.alignleft") {
                    SummaryDisplayStylePicker().pickerStyle(.inline)
                }.accessibilityIdentifier("noteDetailSummaryStyleMenu")
                if hasTranscript {
                    Menu("Template", systemImage: "sparkles") {
                        summaryTemplateChoices
                    }
                    .disabled(!transcriptionManager.canStart)
                    .accessibilityIdentifier("noteDetailSummaryTemplateMenu")
                    if !hasSummary {
                        Button("Generate Summary", systemImage: "sparkles") { generateSummary() }
                            .disabled(!transcriptionManager.canStart || !hasTranscript)
                            .accessibilityIdentifier("noteDetailGenerateSummaryMenuButton")
                    }
                }
                if hasTranscript || Note.isMeaningfulSummaryText(note.summary) { Divider() }
                if Note.isMeaningfulSummaryText(note.summary) {
                    Button("Edit Summary", systemImage: "pencil") { showingSummaryEditor = true }
                        .disabled(!transcriptionManager.canStart)
                        .accessibilityIdentifier("noteDetailEditSummaryButton")
                }
                if hasTranscript {
                    Button("Edit Transcript", systemImage: "pencil") { showingTranscriptEditor = true }
                        .disabled(!transcriptionManager.canStart)
                        .accessibilityIdentifier("noteDetailEditTranscriptButton")
                }
                Button("Continue", systemImage: "mic.fill") { showingTranscription = true }
                    .disabled(!transcriptionManager.canStart && !noteIsTranscribing)
                    .accessibilityIdentifier("noteDetailContinueTranscriptionMenuButton")
                Divider()
                Button("Delete Note", role: .destructive) { showingDelete = true }.disabled(!transcriptionManager.canStart)
            } label: { noteHeaderMenuLabel }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .overlay { noteHeaderMenuIcon("ellipsis") }
            .accessibilityLabel("More Actions")
            .accessibilityIdentifier("noteDetailMoreActionsButton")
        }
        .menuIndicator(.hidden)
    }

    private var noteHeaderMenuLabel: some View {
        Color.clear.frame(width: 24, height: 24)
    }

    private func noteHeaderMenuIcon(_ systemImage: String, verticalOffset: CGFloat = 0) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(headerIconColor)
            .offset(y: verticalOffset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var noteHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if isEditingTitle {
                        TextField("Untitled", text: $editedTitle)
                            .tint(Color.themePrimaryAccent)
                            .focused($isTitleFieldFocused).submitLabel(.done)
                            .accessibilityIdentifier("noteDetailTitleEditor")
                            .onChange(of: editedTitle) { _, value in note.title = value; transcriptionManager.saveEdits() }
                            .onSubmit { isEditingTitle = false; isTitleFieldFocused = false }
                    } else {
                        Text(note.titleOrUntitled).accessibilityIdentifier("noteDetailTitle")
                            .onTapGesture { editedTitle = note.title ?? ""; isEditingTitle = true; isTitleFieldFocused = true }
                    }
                }
                .font(.title2.bold()).foregroundColor(Color(uiColor: .label))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                noteHeaderActions.fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal)
            if let timestamp = note.timestamp {
                Text(timestamp, format: .dateTime.weekday(.wide).month(.wide).day().year().hour(.defaultDigits(amPM: .abbreviated)).minute())
                    .font(.subheadline).foregroundColor(.themeTextSecondary).padding(.horizontal)
                    .accessibilityIdentifier("noteDetailTimestamp")
            }
            iOSNoteFolderRow(note: note, onChange: transcriptionManager.saveEdits).padding(.horizontal).padding(.top,8)
            FlowLayout(spacing: 8) {
                ForEach(note.tagNames, id: \.self) { tag in
                    iOSTagView(tag: tag, onRemove: { note.removeTagByName(tag); currentTags = note.tagNames; transcriptionManager.saveEdits() })
                        .accessibilityIdentifier("noteDetailTag-\(tag)")
                }
                Button { showingAddTag = true } label: {
                    JotleyAccentIconLabel(title: "Add Tag", systemImage: "plus.circle")
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .disabled(note.tagSet.count >= LocalNoteTags.maximumCount)
                .accessibilityHint(note.tagSet.count >= LocalNoteTags.maximumCount ? "Remove a tag to add another." : "")
                .accessibilityIdentifier("noteDetailAddTagButton")
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top,8).padding(.bottom,16)
    }
    private var noteTabPickerSection: some View {
        HStack {
            NoteContentSwitch(selection: $selectedTab, showsSummary: hasSummary)
            Spacer()
        }.padding(.horizontal).padding(.bottom,16)
    }
    @ViewBuilder private var transcriptContent: some View {
        if !note.transcriptUtterances.isEmpty {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(note.transcriptUtterances) { utterance in
                    TranscriptBubbleView(text: utterance.text, timestampText: utterance.timestampLabel, allowsTextSelection: true)
                }
            }.accessibilityIdentifier("noteDetailTranscriptContent")
        } else {
            TranscriptBubbleView(text: transcript, allowsTextSelection: true)
                .accessibilityIdentifier("noteDetailTranscriptContent")
        }
    }
    private var noteActionsFooter: some View {
        Group {
            if summaryIsRunning { summaryProgressFooter }
            else { transcriptionAndSummaryFooter }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsFooterHeight = $0 }
    }

    private var summaryProgressFooter: some View {
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
                    HStack(spacing: newTranscriptionAction == nil ? 8 : 12) {
                    Button { transcriptionManager.cancelProcessing() } label: {
                        Label {
                            Text("Cancel Generation").modifier(JotleyNoteFooterTextStyle())
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }.jotleyDismissButtonStyle()
                        .accessibilityIdentifier("noteDetailCancelGenerationButton")
                        .frame(maxWidth: .infinity)
                    if let newTranscriptionAction {
                        NotesNewTranscriptionButton(action: newTranscriptionAction)
                    }
                    }
                }
                    .padding(.horizontal, newTranscriptionAction == nil ? 16 : 24)
                    .padding(.top, 8).padding(.bottom, footerBottomInset)
                    .frame(maxWidth: .infinity)
                    .background(Color.themeBackground)
    }

    private var transcriptionAndSummaryFooter: some View {
        VStack(spacing: 12) {
            if hasTranscript && !hasSummary {
                NoteSummaryActionsLayout(spacing: 8) {
                    summaryTemplateButton
                    primarySummaryButton
                }
            }
            contextualActionsRow
        }
        .padding(.horizontal, newTranscriptionAction == nil ? 16 : 24)
        .padding(.top, 16).padding(.bottom, footerBottomInset)
        .frame(maxWidth: .infinity)
    }

    private var contextualActionsRow: some View {
        HStack {
            Spacer(minLength: 0)
            contextualNoteAction
            Spacer(minLength: 0)
        }
        // Reserve equal space on both sides so the quick action stays centered
        // on iPhone while the separate + remains tucked into its corner.
        .padding(.horizontal, newTranscriptionAction == nil ? 0 : 56)
        .frame(minHeight: 44)
        .overlay(alignment: .trailing) {
            if let newTranscriptionAction {
                NotesNewTranscriptionButton(action: newTranscriptionAction)
            }
        }
    }

    private var footerBottomInset: CGFloat {
        newTranscriptionAction == nil ? MobileNoteFooterInsets.splitBottom : MobileNoteFooterInsets.phoneBottom
    }

    @ViewBuilder private var contextualNoteAction: some View {
        if selectedTab == "Summary" {
            Button { showingAskAI = true } label: {
                Label {
                    Text("Ask AI").modifier(JotleyNoteFooterTextStyle())
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(Color.themePrimaryAccent)
                }
            }
            .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
            .disabled((!hasTranscript && !hasSummary) || noteIsTranscribing || summaryIsRunning)
            .accessibilityIdentifier("noteDetailSummaryAskAIButton")
        } else {
            Button { showingTranscription = true } label: {
                Label {
                    Text("Continue Transcription").modifier(JotleyNoteFooterTextStyle())
                } icon: {
                    Image(systemName: "waveform")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
            .disabled(!transcriptionManager.canStart && !noteIsTranscribing)
            .accessibilityIdentifier("noteDetailContinueTranscriptionButton")
        }
    }

    @ViewBuilder private var summaryTemplateChoices: some View {
        Button("New Template…") { templatePresentation = .create }
            .accessibilityIdentifier("noteNewTemplateButton")
        Button("Manage Templates…") { templatePresentation = .manage }
        Divider()
        if !templateCatalog.templates.isEmpty {
            Section("My Templates") {
                ForEach(templateCatalog.templates) { custom in
                    Button { selectTemplate(custom.definition) } label: {
                        if note.summaryType == custom.key { Label(custom.name, systemImage: "checkmark") }
                        else { Text(custom.name) }
                    }.accessibilityIdentifier("noteTemplate-\(custom.key)")
                }
            }
        }
        Section("Built-in Templates") {
        ForEach(LocalSummaryTemplate.allCases) { builtIn in
            let template = SummaryTemplateDefinition(builtIn)
            Button { selectTemplate(template) } label: {
                if note.summaryType == template.key { Label(template.title, systemImage: "checkmark") }
                else { Text(template.title) }
            }.accessibilityIdentifier("noteTemplate-\(template.key)")
        }
        }

    }

    private var summaryTemplateButton: some View {
        Menu {
            summaryTemplateChoices
        } label: {
            Label {
                Text(selectedTemplateTitle).modifier(JotleyNoteFooterTextStyle())
            } icon: {
                Image(systemName: "sparkles")
            }
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44)
                .modifier(JotleyGlassMenuLabel(shape: Capsule()))
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(!transcriptionManager.canStart)
        .accessibilityLabel("Templates: \(selectedTemplateTitle)")
        .accessibilityIdentifier("noteDetailTemplatesButton")
    }

    private var primarySummaryButton: some View {
        Button { generateSummary() } label: {
            Text("Generate Summary")
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
        .disabled(!transcriptionManager.canStart || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("noteDetailGenerateSummaryButton")
    }
}
