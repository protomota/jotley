//
//  NoteDetailComponents.swift
//  Jotley
//
//  Small UI components extracted from NoteDetailPlaceholderView+Body.swift
//

import SwiftUI
import AppKit

// MARK: - Spinning Tab Icon


struct LocalMacAskNoteView: View {
    @ObservedObject var note: Note
    @ObservedObject private var themeManager = ThemeManager.shared
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
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Ask AI").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.themeTextPrimary)
                Spacer()
                Button("Copy Conversation", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(conversation, forType: .string)
                }
                    .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                    .help("Copy Conversation").accessibilityIdentifier("askAICopyConversationButton")
                ShareLink(item: conversation) { Label("Share Conversation", systemImage: "square.and.arrow.up") }
                    .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                    .help("Share Conversation").accessibilityIdentifier("askAIShareConversationButton")
                Button("Clear Chat History", systemImage: "arrow.counterclockwise") { showingClear = true }
                    .labelStyle(.iconOnly).disabled(messages.isEmpty || generation != nil)
                    .accessibilityIdentifier("askAIClearButton")
                Button("Done") { dismiss() }.accessibilityIdentifier("askAIDoneButton")
            }.buttonStyle(JotleyGlassButtonStyle()).padding(16)
            Divider()
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
                                    else { MacChatAnswerText(content: preview) }
                                    Button("Stop Answer") { cancel() }.buttonStyle(JotleyGlassButtonStyle())
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
                        Text(notice).font(.system(size: 13))
                        if error != nil { Button("Dismiss") { error = nil }.buttonStyle(JotleyGlassButtonStyle()) }
                    }.foregroundStyle(Color.themeTextSecondary).padding()
                        .accessibilityIdentifier("askAIStatus")
                }
                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask about this note…", text: $input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .tint(Color.themePrimaryAccent)
                        .accentColor(Color.themePrimaryAccent)
                        .lineLimit(1...5).padding(12)
                        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(inputFocused ? Color.themePrimaryAccent : .clear, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                        .focused($inputFocused).disabled(generation != nil)
                        .accessibilityIdentifier("askAIQuestionField")
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                            .frame(width: 44, height: 44)
                    }.keyboardShortcut(.return, modifiers: .command)
                        .disabled(generation != nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unavailable != nil)
                        .accessibilityLabel("Send Question").accessibilityIdentifier("askAISendButton")
                }.padding()
            }
            .background(Color.themeBackground)
            .alert("Clear Chat History?", isPresented: $showingClear) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    guard let id = note.id else { return }
                    do { try store.clearChat(noteID: id); messages = []; error = nil }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("Clear the conversation for this note? Its transcript and summary stay saved.") }
            .task {
                guard let id = note.id else { error = "This note is unavailable."; return }
                do { messages = try store.chatMessages(noteID: id) }
                catch { self.error = error.localizedDescription }
            }
            .onDisappear { cancel() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
            .onReceive(NotificationCenter.default.publisher(for: .processTapRecordingStateChanged)) { _ in cancel() }
            .tint(.themePrimaryAccent).observeThemeChanges()
            .font(.system(size: 15))
        }.frame(width: 580, height: 650)
            .foregroundStyle(Color.themeTextPrimary)
            .background(Color.themeBackground)
            .preferredColorScheme(themeManager.effectiveColorScheme)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 40)).foregroundStyle(Color.themePrimaryAccent)
            Text("Ask about your note").font(.system(size: 24, weight: .bold)).foregroundStyle(Color.themeTextPrimary)
            Text(note.title ?? "Untitled").font(.headline)
            Text("Questions and answers are processed on this device using Apple Intelligence. No note content is sent to an AI service. Conversation history is saved with your notes and follows your optional iCloud setting.")
                .font(.system(size: 15)).foregroundStyle(Color.themeTextSecondary)
            if source.utf8.count > 2400 {
                Text("For long notes, Ask AI selects relevant excerpts. Be specific about the topic you want to find.")
                    .font(.system(size: 13)).foregroundStyle(Color.themeTextSecondary)
            }
            ForEach(["Summarize the key points", "What are the main topics?", "List any action items"], id: \.self) { suggestion in
                Button(suggestion) { input = suggestion; inputFocused = true }
                    .frame(minHeight: 44).buttonStyle(JotleyGlassButtonStyle())
            }
        }.padding(.vertical, 16)
    }
    private func messageBubble(_ message: LocalChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.role == "user" ? "You" : "Jotley").font(.caption.weight(.semibold)).foregroundStyle(Color.themeTextSecondary)
                if message.role == "assistant" { MacChatAnswerText(content: message.content) }
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


private struct MacChatAnswerText: View {
    let content: String
    private var rendered: AttributedString {
        let plain = LocalSummary.markdownForDisplay(content)
            .replacingOccurrences(of: #"(?m)^#{1,6}\h+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^[-*]\h+"#, with: "• ", options: .regularExpression)
        return (try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(plain)
    }
    var body: some View {
        Text(rendered).font(.system(size: 15)).foregroundStyle(Color.themeTextPrimary)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}
