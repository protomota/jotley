import CoreData
//
//  iOSNoteDetailComponents.swift
//  Jotley
//
//  Supporting views extracted from iOSNoteDetailView.swift
//

import SwiftUI

struct NoteFooterContentKey: PreferenceKey {
    static var defaultValue: [UUID: AnyView] = [:]
    static func reduce(value: inout [UUID: AnyView], nextValue: () -> [UUID: AnyView]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Reserve readable primary-action text before assigning space to the template.
/// On very narrow windows the template moves above the primary action and +.
struct NoteSummaryActionsLayout: Layout {
    var spacing: CGFloat

    private func arrangement(width: CGFloat, subviews: Subviews) -> (templateWidth: CGFloat, stacked: Bool, rowHeight: CGFloat) {
        let primaryWidth = subviews[1].sizeThatFits(.unspecified).width
        let captureWidth = subviews.count > 2 ? subviews[2].sizeThatFits(.unspecified).width + spacing : 0
        let remaining = width - primaryWidth - captureWidth - spacing
        return (remaining >= 164 ? 164 : 112, remaining < 112, 44)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        let layout = arrangement(width: width, subviews: subviews)
        return CGSize(width: width, height: layout.stacked ? layout.rowHeight * 2 + 8 : layout.rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        let captureWidth = subviews.count > 2 ? subviews[2].sizeThatFits(.unspecified).width : 0
        let rowY = bounds.maxY - layout.rowHeight
        let primaryX = layout.stacked ? bounds.minX : bounds.minX + layout.templateWidth + spacing
        let primaryWidth = bounds.maxX - primaryX - (captureWidth > 0 ? captureWidth + spacing : 0)
        subviews[0].place(at: CGPoint(x: layout.stacked ? bounds.midX - 82 : bounds.minX,
                                     y: layout.stacked ? bounds.minY : rowY),
                          proposal: ProposedViewSize(width: layout.stacked ? 164 : layout.templateWidth, height: layout.rowHeight))
        subviews[1].place(at: CGPoint(x: primaryX, y: rowY), proposal: ProposedViewSize(width: primaryWidth, height: layout.rowHeight))
        if subviews.count > 2 {
            subviews[2].place(at: CGPoint(x: bounds.maxX - captureWidth, y: rowY),
                              proposal: ProposedViewSize(width: captureWidth, height: layout.rowHeight))
        }
    }
}

/// Glass belongs to each pill, leaving the space around the controls clear.
typealias FloatingNoteSecondaryButtonStyle = JotleyGlassButtonStyle

struct FloatingNoteControlShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .shadow(color: Color.themePrimaryAccent.opacity(colorScheme == .dark ? 0.30 : 0.18), radius: 10, y: 2)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 6, y: 3)
    }
}

struct NotesNewTranscriptionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.themePrimaryAccent)
        }
        .buttonStyle(JotleyGlassButtonStyle(circular: true))
        .modifier(FloatingNoteControlShadow())
        .accessibilityIdentifier("notesListNewNoteButton")
        .accessibilityLabel("New live transcription")
    }
}

// MARK: - iOS Tag View

struct iOSTagView: View {
    let tag: String
    var onRemove: (() -> Void)? = nil
    @State private var showRemoveButton = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .foregroundColor(Color(uiColor: .label))

            if showRemoveButton {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(Color.themeTextPrimary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.themePrimaryAccent.opacity(0.3))
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showRemoveButton.toggle()
            }
        }
    }
}

// MARK: - Add Tag Sheet View

struct AddTagSheetView: View {
    @ObservedObject var note: Note
    @Binding var isPresented: Bool
    @Binding var newTagText: String
    @Binding var currentTags: [String]
    var onSave: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @FocusState private var isTextFieldFocused: Bool

    private func getFormattedTag(_ tag: String) -> String {
        let spacesToDashes = tag.replacingOccurrences(of: " ", with: "-")
        let validCharacters = CharacterSet.letters.union(CharacterSet(charactersIn: "-0123456789"))
        return spacesToDashes.components(separatedBy: validCharacters.inverted).joined()
    }

    private func getCanonicalTag(_ tag: String) -> String {
        return tag.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Enter tag name", text: $newTagText)
                        .font(.body).foregroundStyle(Color.themeTextPrimary)
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .tint(Color.themePrimaryAccent)
                        .padding(.horizontal, 16).frame(minHeight: 56)
                        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14).strokeBorder(
                                isTextFieldFocused ? Color.themePrimaryAccent : Color.themeTextSecondary.opacity(0.25), lineWidth: 1.5)
                        }
                        .submitLabel(.done).onSubmit(addTag)
                        .accessibilityIdentifier("addTagTextField")
                    Button(action: addTag) {
                        MobileActionLabel("Add Tag", systemImage: "plus")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(JotleyGlassButtonStyle())
                    .disabled(getCanonicalTag(newTagText).isEmpty)
                    .accessibilityIdentifier("addTagSaveButton")
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.themeBackground)
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { newTagText = ""; isPresented = false }
                        .accessibilityIdentifier("addTagCancelButton")
                }
            }
            .tint(Color.themeActionText)
            .onAppear { isTextFieldFocused = true }
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(Color.themeBackground)
        .observeThemeChanges()
    }

    private func addTag() {
        guard !newTagText.isEmpty else { return }

        let formattedTag = getFormattedTag(newTagText)
        let canonicalNewTag = getCanonicalTag(formattedTag)
        guard !canonicalNewTag.isEmpty else { return }

        // Check if a similar tag already exists (case-insensitive)
        let tagExists = currentTags.contains { existingTag in
            getCanonicalTag(existingTag) == canonicalNewTag
        }

        if !tagExists {
            do {
                try note.addTagByName(formattedTag, in: viewContext)
                currentTags = note.tagNames
                try viewContext.save()
                onSave()
            } catch {
                print("Failed to save tag: \(error)")
            }
        }

        newTagText = ""
        isPresented = false
    }
}

// MARK: - Markdown Content View (for Summary with rendered markdown)

struct TranscriptBubbleView: View {
    let text: String
    var timestampText: String? = nil
    var allowsTextSelection: Bool = false

    private var isLikelyMultiLine: Bool {
        text.count > 80
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let timestampText, !timestampText.isEmpty {
                    Text(timestampText)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Color.themeTextSecondary.opacity(0.9))
                }

                if allowsTextSelection {
                    Text(text)
                        .foregroundColor(Color(uiColor: .label))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                } else {
                    Text(text)
                        .foregroundColor(Color(uiColor: .label))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: isLikelyMultiLine ? .infinity : nil, alignment: .leading)
            .modifier(JotleyTranscriptCard())

            if !isLikelyMultiLine {
                Spacer(minLength: 0)
            }
        }
    }
}

struct MarkdownContentView: View {
    // The shared color helpers return concrete colors, so this renderer must
    // observe appearance updates even when its note text has not changed.
    @ObservedObject private var themeManager = ThemeManager.shared
    let content: String
    var body: some View {
        // Capture the current color as a value outside ForEach. Cached line data
        // does not change with appearance, so each row needs this explicit input.
        let textColor = Color.themeTextPrimary
        return LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(ParsedNoteMarkdown.rendering(content).lines) { line in
                if let marker = line.marker {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).frame(minWidth: 16, alignment: .trailing)
                            .accessibilityHidden(true)
                        Text(line.text).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.body).foregroundColor(textColor)
                    .padding(.leading, CGFloat(line.indentation) * 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(marker) \(String(line.text.characters))")
                    .accessibilityIdentifier("markdownListItem-\(line.id)")
                } else {
                    Text(line.text)
                        .font(line.heading ? .headline : .body)
                        .foregroundColor(textColor)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Original note-specific Ask AI flow, backed entirely by Apple's local model.
struct LocalAskNoteView: View {
    @ObservedObject var note: Note
    @EnvironmentObject private var store: SharedPersistenceController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var inputFocused = false
    @State private var messages: [LocalChatMessage] = []
    @State private var input = ""
    @State private var preview = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var generation: UUID?
    @State private var showingClear = false
    @State private var share: LocalSharePayload?
    private var source: String {
        let transcript = (note.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? note.summary ?? "" : transcript
    }
    private var locale: Locale { Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US") }
    private var unavailable: String? {
        #if DEBUG && targetEnvironment(simulator)
        // Marketing fixtures show an already prepared local-model state.
        if ProcessInfo.processInfo.environment["JOTLEY_SCREENSHOT_CHAT_READY"] == "1" { return nil }
        #endif
        return LocalSummary.readiness(locale: locale)?.replacingOccurrences(of: "summaries", with: "Ask AI")
    }
    private var conversation: String { LocalNoteChat.conversationMarkdown(title: note.title, messages: messages) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if messages.isEmpty { welcome }
                            ForEach(messages) { message in
                                messageBubble(message).id(message.id)
                            }
                            if generation != nil {
                                VStack(alignment: .leading, spacing: 8) {
                                    if preview.isEmpty { ProgressView("Thinking on this device…") }
                                    else { JotleyChatAnswerText(content: preview) }
                                    Button("Stop Answer") { cancel() }
                                        .accessibilityIdentifier("askAIStopButton")
                                }.id("answer").padding().modifier(JotleyTranscriptCard(neutral: true))
                            }
                        }.padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                if let notice = error ?? unavailable {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text(notice).font(.footnote)
                        if error != nil { Button("Dismiss") { error = nil } }
                    }.foregroundStyle(Color.themeTextSecondary).padding()
                        .accessibilityIdentifier("askAIStatus")
                }
                Divider()
                HStack(alignment: .center, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if input.isEmpty {
                            Text("Ask about this note…").foregroundStyle(Color.themeTextSecondary)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        MobileAskQuestionInput(text: $input, focused: $inputFocused,
                                               isEnabled: generation == nil, onSend: send)
                    }
                    .padding(12).frame(minHeight: 44)
                    .modifier(JotleyTranscriptCard(cornerRadius: 20))
                    .contentShape(RoundedRectangle(cornerRadius: 20))
                    .onTapGesture { if generation == nil { inputFocused = true } }
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.themePrimaryAccent)
                            .frame(width: 44, height: 44)
                    }.buttonStyle(JotleyGlassButtonStyle(circular: true)).disabled(generation != nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unavailable != nil)
                        .accessibilityLabel("Send Question").accessibilityIdentifier("askAISendButton")
                }.padding()
            }

            .sheet(item: $share) { ShareSheet(activityItems: $0.items) }
            .task {
                guard let id = note.id else { error = "This note is unavailable."; return }
                do { messages = try store.chatMessages(noteID: id) }
                catch { self.error = error.localizedDescription }
            }
            .onDisappear { cancel() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
            .onReceive(NotificationCenter.default.publisher(for: LiveTranscriptionManager.willBeginTranscription)) { _ in cancel() }
            .tint(.themePrimaryAccent).observeThemeChanges()
            .modifier(JotleyGlassPanel())
            .presentationBackground(.clear)
        }
        .allowsHitTesting(!showingClear)
        .accessibilityHidden(showingClear)
        .overlay { clearConfirmation }
        .onChange(of: showingClear) { _, showing in if showing { inputFocused = false } }
    }
    @ViewBuilder private var clearConfirmation: some View {
        if showingClear {
            JotleyClearChatConfirmation(onCancel: { showingClear = false }, onClear: clearConversation)
        }
    }
    private func clearConversation() {
        showingClear = false
        guard let id = note.id else { return }
        do { try store.clearChat(noteID: id); messages = []; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Text("Ask AI").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.themeTextPrimary)
            Spacer(minLength: 8)
            Button("Copy Conversation", systemImage: "doc.on.doc") { UIPasteboard.general.string = conversation }
                .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                .accessibilityIdentifier("askAICopyConversationButton")
            Button("Share Conversation", systemImage: "square.and.arrow.up") { share = LocalSharePayload(items: [conversation]) }
                .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                .accessibilityIdentifier("askAIShareConversationButton")
            Button("Clear Chat History", systemImage: "arrow.counterclockwise") { showingClear = true }
                .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                .accessibilityIdentifier("askAIClearButton")
            Button("Done") { dismiss() }
                .accessibilityIdentifier("askAIDoneButton")
        }
        .font(.system(size: 15)).buttonStyle(JotleyGlassButtonStyle()).padding(16)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 40)).foregroundStyle(Color.themePrimaryAccent)
            Text("Ask about your note").font(.title2.bold()).foregroundStyle(Color.themeTextPrimary)
            Text(note.title ?? "Untitled").font(.headline)
            Text("Questions and answers are processed on this device using Apple Intelligence. No note content is sent to an AI service. Conversation history is saved with your notes and follows your optional iCloud setting.")
                .font(.subheadline).foregroundStyle(Color.themeTextSecondary)
            if source.utf8.count > 2400 {
                Text("For long notes, Ask AI selects relevant excerpts. Be specific about the topic you want to find.")
                    .font(.footnote).foregroundStyle(Color.themeTextSecondary)
            }
            ForEach(["Summarize the key points", "What are the main topics?", "List any action items"], id: \.self) { suggestion in
                Button { input = suggestion; inputFocused = true } label: {
                    Text(suggestion).foregroundStyle(Color.themeActionText)
                }
                    .frame(minHeight: 44).buttonStyle(JotleyGlassButtonStyle())
            }
        }.padding(.vertical, 16)
    }
    private func messageBubble(_ message: LocalChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(message.role == "user" ? "You" : "Jotley").font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(message.timestamp, format: .dateTime.hour().minute())
                        .font(.caption2.monospacedDigit())
                }.foregroundStyle(Color.themeTextSecondary)
                if message.role == "assistant" { JotleyChatAnswerText(content: message.content) }
                else { Text(message.content).textSelection(.enabled).foregroundStyle(Color.themeTextPrimary) }
            }.padding().modifier(JotleyTranscriptCard(emphasized: message.role == "user", neutral: message.role == "assistant"))
            if message.role == "assistant" { Spacer(minLength: 32) }
        }
    }
    private func send() {
        guard !showingClear, generation == nil, unavailable == nil,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let id = note.id, !note.isDeleted else { return }
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = source, history = messages
        do {
            if let unavailable { throw LocalError.message(unavailable) }
            _ = try LocalNoteChat.prompt(source: source, question: question, history: history)
            let message = LocalChatMessage(role: "user", content: question)
            try store.saveChatMessage(message, noteID: id); messages.append(message)
        } catch { self.error = error.localizedDescription; return }
        input = ""; inputFocused = false; preview = ""; error = nil
        let token = UUID(); generation = token
        let locale = locale
        JotleyEngagement.shared.beginProcessing()
        task = Task { @MainActor in
            defer { JotleyEngagement.shared.endProcessing() }
            defer { if generation == token { generation = nil; task = nil; preview = "" } }
            do {
                let answer = try await LocalNoteChat.answer(source: source, question: question, history: history, locale: locale) { value in
                    await MainActor.run { if generation == token { preview = value } }
                }
                try Task.checkCancellation()
                guard generation == token, !note.isDeleted else { return }
                let message = LocalChatMessage(role: "assistant", content: answer)
                try store.saveChatMessage(message, noteID: id); messages.append(message)
            } catch is CancellationError { }
            catch { if generation == token { self.error = error.localizedDescription; input = question } }
        }
    }
    private func cancel() {
        task?.cancel(); task = nil; generation = nil; preview = ""
    }
}


/// Multiline chat entry with an actual Send return key. SwiftUI's vertical
/// TextField still inserts a newline with submitLabel(.send) on iPad/iPhone.
private struct MobileAskQuestionInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let isEnabled: Bool
    let onSend: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared

    final class TextView: UITextView {
        var insertingLineBreak = false
        override var keyCommands: [UIKeyCommand]? {
            let lineBreaks = [UIKeyModifierFlags.shift, .alternate].map { modifiers in
                let command = UIKeyCommand(input: "\r", modifierFlags: modifiers, action: #selector(insertQuestionLineBreak))
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
            return lineBreaks + (super.keyCommands ?? [])
        }
        @objc private func insertQuestionLineBreak() {
            insertingLineBreak = true
            insertText("\n")
            insertingLineBreak = false
        }
    }

    func makeUIView(context: Context) -> TextView {
        let view = TextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .send
        view.enablesReturnKeyAutomatically = true
        view.isScrollEnabled = false
        view.accessibilityIdentifier = "askAIQuestionField"
        view.accessibilityLabel = "Ask about this note"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: TextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text; view.invalidateIntrinsicContentSize() }
        view.textColor = UIColor(Color.themeTextPrimary)
        view.tintColor = UIColor(themeManager.currentThemeColor.color)
        view.isEditable = isEnabled
        if focused && isEnabled && !view.isFirstResponder { view.becomeFirstResponder() }
        else if !focused && view.isFirstResponder { view.resignFirstResponder() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let lineHeight = uiView.font?.lineHeight ?? 22
        let fullHeight = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let maximum = lineHeight * 5
        uiView.isScrollEnabled = fullHeight > maximum
        return CGSize(width: width, height: max(lineHeight, min(fullHeight, maximum)))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MobileAskQuestionInput
        init(_ parent: MobileAskQuestionInput) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.focused { parent.focused = true }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused { parent.focused = false }
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n", textView.markedTextRange == nil,
               (textView as? TextView)?.insertingLineBreak != true {
                parent.onSend()
                return false
            }
            return true
        }
    }
}
