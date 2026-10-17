import CoreData
//
//  iOSNoteDetailComponents.swift
//  Jotley
//
//  Supporting views extracted from iOSNoteDetailView.swift
//

import SwiftUI

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
        NavigationView {
            VStack(spacing: 20) {
                TextField("Enter tag name", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .onChange(of: newTagText) { _, newValue in
                        let formatted = getFormattedTag(newValue)
                        if newTagText != formatted {
                            newTagText = formatted
                        }
                    }
                    .padding(.horizontal)

                Button {
                    addTag()
                } label: {
                    Text("Add Tag")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(newTagText.isEmpty ? Color.gray : Color.themePrimaryAccent)
                        )
                }
                .disabled(newTagText.isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .tint(Color.themeActionText)
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }

    private func addTag() {
        guard !newTagText.isEmpty else { return }

        let formattedTag = getFormattedTag(newTagText)
        let canonicalNewTag = getCanonicalTag(formattedTag)

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
                        .font(.caption2)
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.themePrimaryAccent.opacity(0.1))
            )

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
    @FocusState private var inputFocused: Bool
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
        LocalSummary.readiness(locale: locale)?.replacingOccurrences(of: "summaries", with: "Ask AI")
    }
    private var conversation: String { LocalNoteChat.conversationMarkdown(title: note.title, messages: messages) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                                    else { MarkdownContentView(content: preview) }
                                    Button("Stop Answer") { cancel() }
                                        .accessibilityIdentifier("askAIStopButton")
                                }.id("answer").padding().background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 16))
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
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask about this note…", text: $input, axis: .vertical)
                        .lineLimit(1...5).padding(12)
                        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 20))
                        .focused($inputFocused).disabled(generation != nil)
                        .accessibilityIdentifier("askAIQuestionField")
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                            .frame(width: 44, height: 44)
                    }.disabled(generation != nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unavailable != nil)
                        .accessibilityLabel("Send Question").accessibilityIdentifier("askAISendButton")
                }.padding()
            }
            .background(Color.themeBackground)
            .navigationTitle("Ask AI").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { MobileDoneButton(inToolbar: true) { dismiss() }.accessibilityIdentifier("askAIDoneButton") }
                ToolbarItemGroup(placement: .cancellationAction) {
                    Button("Clear Chat History", systemImage: "arrow.counterclockwise") { showingClear = true }
                        .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                        .accessibilityIdentifier("askAIClearButton")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Copy Conversation", systemImage: "doc.on.doc") { UIPasteboard.general.string = conversation }
                        .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                        .accessibilityIdentifier("askAICopyConversationButton")
                    Button("Share Conversation", systemImage: "square.and.arrow.up") { share = LocalSharePayload(items: [conversation]) }
                        .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                        .accessibilityIdentifier("askAIShareConversationButton")
                }
            }
            .alert("Clear Chat History?", isPresented: $showingClear) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    guard let id = note.id else { return }
                    do { try store.clearChat(noteID: id); messages = []; error = nil }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("Clear the conversation for this note? Its transcript and summary stay saved.") }
            .sheet(item: $share) { ShareSheet(activityItems: $0.items) }
            .task {
                guard let id = note.id else { error = "This note is unavailable."; return }
                do { messages = try store.chatMessages(noteID: id) }
                catch { self.error = error.localizedDescription }
            }
            .onDisappear { cancel() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
            .onReceive(NotificationCenter.default.publisher(for: LiveTranscriptionManager.willBeginTranscription)) { _ in cancel() }
            .tint(.themeActionText).observeThemeChanges()
        }
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
                    .frame(minHeight: 44).buttonStyle(.bordered).tint(.themePrimaryAccent)
            }
        }.padding(.vertical, 16)
    }
    private func messageBubble(_ message: LocalChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.role == "user" ? "You" : "Jotley").font(.caption.weight(.semibold)).foregroundStyle(Color.themeTextSecondary)
                if message.role == "assistant" { MarkdownContentView(content: message.content) }
                else { Text(message.content).textSelection(.enabled).foregroundStyle(Color.themeTextPrimary) }
            }.padding().background(message.role == "user" ? Color.themePrimaryAccent.opacity(0.14) : Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 16))
            if message.role == "assistant" { Spacer(minLength: 32) }
        }
    }
    private func send() {
        guard generation == nil, let id = note.id, !note.isDeleted else { return }
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
