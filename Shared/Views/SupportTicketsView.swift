import AuthenticationServices
import SwiftUI
import StoreKit

struct JotleyTechnicalSupportButton: View {
    @State private var showingSupport = false
    var body: some View {
        Button { showingSupport = true } label: {
            Label("Personal Technical Support", systemImage: "person.bubble.left.and.bubble.right")
        }
        .accessibilityIdentifier("settingsTechnicalSupport")
        .sheet(isPresented: $showingSupport) { JotleySupportTicketsView() }
    }
}

struct JotleySupportTicketsView: View {
    @StateObject private var store = JotleySupportStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var nonce = ""
    @State private var showingRequest = false
    @State private var confirmingDeletion = false
    var body: some View {
        NavigationStack {
            Group {
                if let ticket = store.selectedTicket {
                    conversation(ticket)
                } else {
                    accountView
                }
            }
            .navigationTitle("Jotley Support")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .jotleyDismissButtonStyle(inToolbar: true)
                        .accessibilityIdentifier("supportDone")
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(store.busy).accessibilityIdentifier("supportRefresh")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let notice = store.notice {
                    Text(notice).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.regularMaterial).accessibilityIdentifier("supportNotice")
                }
            }
        }
        .tint(Color.themePrimaryAccent)
        .jotleySupporterCelebration(.support)
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 840, minHeight: 650)
        .onDisappear { store.cancelBrowserSignIn() }
        #endif
        .sheet(isPresented: $showingRequest) { newRequest }
        .confirmationDialog("Delete your support account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete Support Account", role: .destructive) { Task { await store.deleteAccount() } }
            Button("Keep My Account", role: .cancel) { }
        } message: {
            Text("This permanently deletes your support profile, tickets and conversations. Unused tickets will no longer be available. Your local notes stay on your device. Deletion does not request a refund; unlinked transaction references are retained to reconcile purchases and prevent reuse.")
        }
        .onChange(of: store.requestUnlocked) { _, unlocked in if unlocked { showingRequest = true } }
        .onChange(of: store.selectedTicketID) { _, id in if id != nil { showingRequest = false } }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in store.signOut() }
        .task {
            await store.load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                if scenePhase == .active { await store.refresh() }
            }
        }
    }
    private var accountView: some View {
        Form {
            Section {
                Label("Personal help from a real person", systemImage: "person.bubble.left.and.bubble.right")
                    .font(.headline)
                JotleySupporterBadge()
                Text("Get help with one Jotley issue, including MCP setup. Each ticket has its own private conversation with Brad, the person behind Jotley.")
                Text("One-time purchase. Follow-up replies stay in the same ticket.").font(.callout).foregroundStyle(.secondary)
            }
            if let account = store.account {
                Section("Your Apple account") {
                    LabeledContent("Contact email", value: account.user.email).textSelection(.enabled)
                    Text("This verified contact address comes from Apple and cannot be edited in your support request.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Sign out") { store.signOut() }.disabled(store.busy)
                    Button("Delete support account", role: .destructive) { confirmingDeletion = true }
                        .disabled(store.busy).accessibilityIdentifier("supportDeleteAccount")
                }
                Section("Open a support request") {
                    if !store.unusedPurchases.isEmpty {
                        Button("Write your support request") { showingRequest = true }
                            .accessibilityIdentifier("supportWriteRequest")
                        Text("You have a purchased ticket available.").font(.caption).foregroundStyle(.secondary)
                    } else if JotleySupportStore.usesAppStore {
                        Button(store.product.map { "Buy one ticket · \($0.displayPrice)" } ?? "Support purchase unavailable") {
                            Task { await store.buyAppStoreTicket() }
                        }.disabled(!store.canBuy).accessibilityIdentifier("supportBuyAppStoreTicket")
                    } else {
                        Button("Buy one ticket · $9.99") {
                            Task { if let url = await store.macCheckout() { openURL(url) } }
                        }.disabled(!store.canBuy).accessibilityIdentifier("supportBuyMacTicket")
                    }
                    if store.busy { ProgressView("Working…") }
                }
                Section("Your support tickets") {
                    if account.tickets.isEmpty {
                        Text("Your requests and conversations will appear here.").foregroundStyle(.secondary)
                    }
                    ForEach(account.tickets) { ticket in
                        Button { Task { await store.open(ticket) } } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ticket.subject).font(.headline)
                                Text("\(ticket.reference) · \(status(ticket.status))").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("supportTicket-\(ticket.id)")
                    }
                    if account.nextOffset != nil {
                        Button("Load more tickets") { Task { await store.moreTickets() } }.disabled(store.busy)
                    }
                }
            } else {
                Section("Sign in to continue") {
                    Text("Use Sign in with Apple to purchase a ticket and keep your conversation available in the app and on the website. Hide My Email works too.")
                    #if os(macOS) && !STORE_BUILD
                    Button { Task { await store.signInInBrowser() } } label: {
                        Label(store.busy ? "Connecting…" : "Continue with Apple in Browser", systemImage: "apple.logo")
                    }
                    .buttonStyle(JotleyGlassButtonStyle())
                    .disabled(!store.available || store.busy)
                    .accessibilityIdentifier("supportSignInWithApple")
                    #else
                    SignInWithAppleButton(.signIn) { request in
                        nonce = JotleySupportStore.nonce()
                        request.requestedScopes = [.email]
                        request.nonce = JotleySupportStore.hashedNonce(nonce)
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
                                store.notice = "Apple sign-in could not finish. Please try again."; return
                            }
                            Task { await store.signIn(token: token, nonce: nonce) }
                        case .failure(let error):
                            if (error as? ASAuthorizationError)?.code != .canceled { store.notice = "Apple sign-in could not finish. Please try again." }
                        }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: 340).frame(height: 46)
                    .disabled(!store.available || store.busy)
                    .accessibilityIdentifier("supportSignInWithApple")
                    #endif
                    if !store.available { Text("Personal support is currently unavailable. Please try again later.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section {
                Text("All note-taking features are free. Personal support and tips are optional paid purchases. Bug reports and purchase help do not require a paid ticket.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Your notes stay on your device. Only the text you choose to submit is shared with support.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Support privacy", destination: URL(string: "https://jotley.ai/privacy")!)
            }
            Section("Apple authorization") {
                Link("Manage Sign in with Apple", destination: URL(string: "https://account.apple.com/account/manage/section/sign-in-and-security")!)
                Text("After deleting your support account, open Apple Account → Sign-In and Security → Sign in with Apple → Jotley → Stop Using Sign in with Apple to remove Apple’s authorization too.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func status(_ value: String) -> String {
        switch value {
        case "in_progress": return "In progress"
        case "waiting_for_customer": return "Your reply needed"
        case "resolved": return "Resolved"
        default: return "Waiting for support"
        }
    }
    private func conversation(_ ticket: JotleySupportTicket) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Button("All tickets", systemImage: "chevron.left") { store.selectedTicketID = nil }
                Text(ticket.subject).font(.title3.bold())
                Text("\(ticket.reference) · \(status(ticket.status))").font(.caption).foregroundStyle(.secondary)
                Label("Private conversation with Brad · Jotley Support", systemImage: "person.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.hasEarlierMessages {
                            Button("Load earlier messages") { Task { await store.earlierMessages() } }.disabled(store.busy)
                        }
                        ForEach(store.messages) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(message.senderRole == "support" ? "Brad · Jotley" : "You").font(.caption.bold())
                                Text(message.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(Color.themePrimaryAccent.opacity(message.senderRole == "support" ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.themePrimaryAccent.opacity(message.senderRole == "support" ? 0.3 : 0.1)))
                            .frame(maxWidth: .infinity, alignment: message.senderRole == "support" ? .leading : .trailing)
                            .id(message.id)
                        }
                    }.padding()
                }
                .onChange(of: store.messages.last?.id) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Reply in this ticket").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { store.replyDrafts[ticket.id] ?? "" }, set: { store.replyDrafts[ticket.id] = String($0.prefix(10000)) }))
                    .frame(minHeight: 70, maxHeight: 110).padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
                    .disabled(store.busy).accessibilityIdentifier("supportReplyText")
                HStack {
                    Text("Replies stay with this issue.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Send reply", systemImage: "paperplane.fill") { Task { await store.reply() } }
                        .buttonStyle(JotleyGlassButtonStyle())
                        .disabled(store.busy || (store.replyDrafts[ticket.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ticket.purchase.status != "paid")
                        .accessibilityIdentifier("supportSendReply")
                }
            }.padding()
        }
    }
    @State private var subject = ""
    @State private var topic = "MCP setup"
    @State private var requestBody = ""
    private var newRequest: some View {
        NavigationStack {
            Form {
                Section {
                    if let email = store.account?.user.email { LabeledContent("Apple contact email", value: email).textSelection(.enabled) }
                    Text("One ticket covers one Jotley issue and its follow-up conversation.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your request") {
                    TextField("Subject", text: $subject).onChange(of: subject) { _, value in subject = String(value.prefix(140)) }
                    Picker("Topic", selection: $topic) {
                        ForEach(["MCP setup", "Summaries and templates", "Sync and notes", "Another Jotley issue"], id: \.self) { Text($0) }
                    }
                    TextEditor(text: $requestBody).frame(minHeight: 180)
                        .onChange(of: requestBody) { _, value in requestBody = String(value.prefix(10000)) }
                        .accessibilityIdentifier("supportRequestText")
                    Text("Describe what you tried and what happened. Your device and Jotley version help too. Notes and transcripts are never attached automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Send support request") {
                        Task { await store.openRequest(subject: subject, topic: topic, message: requestBody) }
                    }
                    .disabled(store.busy || store.unusedPurchases.isEmpty || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || requestBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("supportSubmitRequest")
                }
                if let notice = store.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped).navigationTitle("New support request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRequest = false; store.requestUnlocked = false }
                        .jotleyDismissButtonStyle(inToolbar: true)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .jotleySupporterCelebration(.support)
        #if os(macOS)
        .frame(width: 600, height: 620)
        #endif
    }
}
