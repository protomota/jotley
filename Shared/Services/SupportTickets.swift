import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import StoreKit
#if os(macOS)
import AppKit

@MainActor private final class SupportBrowserPresentation: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: NSWindow
    init(window: NSWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
#endif

struct JotleySupportPurchase: Decodable, Identifiable {
    let id: String
    let provider: String
    let status: String
    let used: Bool?
}
struct JotleySupportTicket: Decodable, Identifiable {
    let id: String
    let reference: String
    let subject: String
    let topic: String
    let status: String
    let purchase: JotleySupportPurchase
}
struct JotleySupportMessage: Decodable, Identifiable {
    let id: String
    let ticketId: String
    let senderRole: String
    let body: String
    let createdAt: String
}
struct JotleySupportAccount: Decodable {
    struct User: Decodable { let id: String; let email: String; let isStaff: Bool }
    let user: User
    let tickets: [JotleySupportTicket]
    let purchases: [JotleySupportPurchase]
    let nextOffset: Int?
}
private struct JotleySupportSession: Codable {
    let userID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}
private struct SupportAPIError: Decodable { let error: String }
private enum SupportFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
private enum SupportSessionKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.protomota.jotley") + ".support-session.v1",
         kSecAttrAccount as String: "apple-support-session"]
    }
    static func load() -> JotleySupportSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(JotleySupportSession.self, from: data)
    }
    static func save(_ session: JotleySupportSession) throws {
        let data = try JSONEncoder().encode(session)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SupportFailure.message("Your support sign-in could not be saved securely.") }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SupportFailure.message("Your support sign-in could not be saved securely.") }
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}

/// Public app client only. Credentials for the support backend never enter this app.
@MainActor
final class JotleySupportStore: ObservableObject {
    static let productID = "com.protomota.jotley.support.ticket"
    static var usesAppStore: Bool {
        #if os(macOS) && !STORE_BUILD
        return false
        #else
        return true
        #endif
    }
    static var usesBrowserSignIn: Bool { !usesAppStore }
    @Published private(set) var account: JotleySupportAccount?
    @Published private(set) var messages: [JotleySupportMessage] = []
    @Published private(set) var product: StoreKit.Product?
    @Published private(set) var busy = false
    @Published private(set) var available = false
    private var checkoutAvailable = false
    @Published var notice: String?
    @Published var selectedTicketID: String?
    @Published var requestUnlocked = false
    @Published var replyDrafts: [String: String] = [:]
    private var session = SupportSessionKeychain.load()
    private var refreshTask: Task<JotleySupportSession, Error>?
    private var authenticationGeneration = UUID()
    private var transactionsTask: Task<Void, Never>?
    private var pendingReply: (ticket: String, body: String, id: String)?
    private var messageBefore: String?
    private var pendingVerification = false
    #if os(macOS)
    private var browserAuthentication: ASWebAuthenticationSession?
    #endif
    private let network: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 25
        return URLSession(configuration: configuration)
    }()
    var unusedPurchases: [JotleySupportPurchase] {
        guard let account else { return [] }
        return account.purchases.filter { purchase in purchase.status == "paid" && purchase.used != true && !account.tickets.contains { $0.purchase.id == purchase.id } }
    }
    var canBuy: Bool { account != nil && available && !busy && !pendingVerification && (Self.usesAppStore ? product != nil : checkoutAvailable) }
    var ticketPrice: String? {
        #if DEBUG && targetEnvironment(simulator)
        if isDesignPreview { return "$9.99" }
        #endif
        return Self.usesAppStore ? product?.displayPrice : "$9.99"
    }

    #if DEBUG && targetEnvironment(simulator)
    var isDesignPreview: Bool { ProcessInfo.processInfo.environment["JOTLEY_SUPPORT_DESIGN_PREVIEW"] == "1" }
    private var previewsHistory: Bool { ProcessInfo.processInfo.environment["JOTLEY_SUPPORT_PREVIEW_HISTORY"] == "1" }

    private var sampleHistory: [JotleySupportTicket] {
        [
            .init(id: "preview-sync", reference: "JT-1043", subject: "Notes not syncing to iPad",
                  topic: "Sync and notes", status: "waiting_for_customer",
                  purchase: .init(id: "preview-sync-purchase", provider: "app_store", status: "paid", used: true)),
            .init(id: "preview-template", reference: "JT-1038", subject: "Customize my meeting summary",
                  topic: "Summaries and templates", status: "resolved",
                  purchase: .init(id: "preview-template-purchase", provider: "app_store", status: "paid", used: true)),
        ]
    }

    func previewPurchasedTicket() {
        guard isDesignPreview, let account else { return }
        let purchase = JotleySupportPurchase(id: UUID().uuidString, provider: "app_store", status: "paid", used: false)
        self.account = JotleySupportAccount(user: account.user, tickets: account.tickets, purchases: [purchase] + account.purchases, nextOffset: nil)
        requestUnlocked = true
    }

    func previewSubmittedRequest(subject: String, topic: String, body: String) {
        guard isDesignPreview, let account, let purchase = unusedPurchases.first else { return }
        let ticket = JotleySupportTicket(id: purchase.id, reference: "JT-\(1046 + account.purchases.count)", subject: subject,
                                         topic: topic, status: "open", purchase: purchase)
        let consumed = JotleySupportPurchase(id: purchase.id, provider: purchase.provider, status: purchase.status, used: true)
        self.account = JotleySupportAccount(user: account.user, tickets: [ticket] + account.tickets,
                                           purchases: account.purchases.map { $0.id == consumed.id ? consumed : $0 }, nextOffset: nil)
        messages = [.init(id: "preview-request-message", ticketId: ticket.id, senderRole: "customer", body: body, createdAt: "2026-11-13T09:00:00Z")]
        selectedTicketID = ticket.id
        requestUnlocked = false
    }
    #endif
    var hasEarlierMessages: Bool { messageBefore != nil }
    var selectedTicket: JotleySupportTicket? { account?.tickets.first { $0.id == selectedTicketID } }
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if isDesignPreview { return }
        #endif
        guard Self.usesAppStore else { return }
        transactionsTask = Task { [weak self] in
            for await verification in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { break }
                guard let self, self.session != nil else { continue }
                do { try await self.claim(verification) }
                catch { self.notice = "Your purchase is waiting for verification. Refresh this account before buying another ticket." }
            }
        }
    }
    deinit { transactionsTask?.cancel() }
    static func nonce() -> String {
        (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
    }
    static func hashedNonce(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    func signIn(token: String, nonce: String) async {
        await perform {
            let generation = self.authenticationGeneration
            let signed: JotleySupportSession = try await self.api("auth/native", body: ["identityToken": token, "nonce": nonce], authenticated: false)
            try await self.installSession(signed, generation: generation)
        }
    }

    #if os(macOS)
    func signInInBrowser() async {
        await perform {
            let generation = self.authenticationGeneration
            let verifier = Self.nonce()
            let state = Self.nonce()
            var components = URLComponents(string: "https://jotley.ai/support/mac")!
            components.fragment = "challenge=\(Self.hashedNonce(verifier))&state=\(state)"
            let callback = try await self.openAuthentication(components.url!)
            let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            guard result?.scheme == "jotley-support-auth", result?.host == "complete",
                  result?.queryItems?.filter({ $0.name == "state" }).map(\.value) == [state],
                  let codes = result?.queryItems?.filter({ $0.name == "code" }), codes.count == 1,
                  let code = codes.first?.value, code.wholeMatch(of: /[a-f0-9]{64}/) != nil else {
                throw SupportFailure.message("The browser could not verify this sign-in. Try again from Jotley.")
            }
            let signed: JotleySupportSession = try await self.api("auth/mac/exchange", body: ["code": code, "verifier": verifier], authenticated: false)
            try await self.installSession(signed, generation: generation)
        }
    }

    private func openAuthentication(_ url: URL) async throws -> URL {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            throw SupportFailure.message("Open the Jotley Support window and try again.")
        }
        let presentation = SupportBrowserPresentation(window: window)
        defer { browserAuthentication = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "jotley-support-auth") { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: CancellationError()) }
                else { continuation.resume(throwing: SupportFailure.message("Apple sign-in could not open. Try again from Jotley.")) }
            }
            session.presentationContextProvider = presentation
            browserAuthentication = session
            if !session.start() { continuation.resume(throwing: SupportFailure.message("Your browser could not start sign-in.")) }
        }
    }

    func cancelBrowserSignIn() {
        if browserAuthentication != nil { authenticationGeneration = UUID(); browserAuthentication?.cancel() }
    }
    #endif

    private func installSession(_ signed: JotleySupportSession, generation: UUID) async throws {
        guard authenticationGeneration == generation else { throw CancellationError() }
        try SupportSessionKeychain.save(signed)
        session = signed
        try await refreshAccount()
        try await reconcilePurchases()
    }
    func signOut() {
        authenticationGeneration = UUID()
        refreshTask?.cancel(); refreshTask = nil
        SupportSessionKeychain.remove()
        session = nil; account = nil; messages = []; selectedTicketID = nil
        replyDrafts = [:]; pendingReply = nil; notice = nil; requestUnlocked = false; pendingVerification = false
    }
    func deleteAccount() async {
        await perform {
            struct Result: Decodable { let deleted: Bool }
            let result: Result = try await self.api("account/delete", body: ["confirmation": "delete-my-support-account"])
            guard result.deleted else { throw SupportFailure.message("Your support account could not be deleted.") }
            self.signOut()
            self.notice = "Your support account and conversations were deleted. You can also remove Jotley under Sign in with Apple in your Apple Account. Your local notes are unchanged."
        }
    }
    func load() async {
        #if DEBUG && targetEnvironment(simulator)
        if isDesignPreview {
            available = true
            let tickets = previewsHistory ? sampleHistory : []
            account = JotleySupportAccount(user: .init(id: "preview", email: "customer@example.com", isStaff: false),
                                           tickets: tickets, purchases: tickets.map(\.purchase), nextOffset: nil)
            return
        }
        #endif
        await perform {
            struct Configuration: Decodable { let configured: Bool; let nativeConfigured: Bool?; let macBrowserConfigured: Bool?; let checkoutConfigured: Bool? }
            let configuration: Configuration = try await self.api("configuration", authenticated: false)
            self.available = Self.usesBrowserSignIn ? configuration.macBrowserConfigured == true : (configuration.nativeConfigured ?? configuration.configured)
            self.checkoutAvailable = configuration.checkoutConfigured ?? false
            if Self.usesAppStore {
                self.product = try? await StoreKit.Product.products(for: [Self.productID]).first { $0.id == Self.productID && $0.type == .consumable }
            }
            if self.session != nil { try await self.refreshAccount(); try await self.reconcilePurchases() }
        }
    }
    func refresh() async {
        #if DEBUG && targetEnvironment(simulator)
        if isDesignPreview { return }
        #endif
        guard !busy else { return }
        if !available || (Self.usesAppStore && product == nil) { await load(); return }
        guard session != nil else { return }
        do {
            try await refreshAccount()
            if let id = selectedTicketID { try await loadMessages(id, reset: false) }
            if pendingVerification {
                try await reconcilePurchases()
                if !unusedPurchases.isEmpty { pendingVerification = false; requestUnlocked = true }
            }
        } catch { notice = "Support could not refresh. Your drafts and purchase are kept." }
    }
    func open(_ ticket: JotleySupportTicket) async {
        selectedTicketID = ticket.id; messages = []; messageBefore = nil
        #if DEBUG && targetEnvironment(simulator)
        if isDesignPreview {
            let request = ticket.id == "preview-template"
                ? "How can I make my meeting notes end with next steps?"
                : "My notes show up on my iPhone but not on my iPad."
            let reply = ticket.id == "preview-template"
                ? "Create a meeting template in Settings and add an Action Items section. Then select it before generating your next summary."
                : "Is iCloud sync turned on in Jotley on both devices?"
            messages = [
                .init(id: "preview-question", ticketId: ticket.id, senderRole: "customer", body: request, createdAt: "2026-11-12T09:00:00Z"),
                .init(id: "preview-answer", ticketId: ticket.id, senderRole: "support", body: reply, createdAt: "2026-11-12T11:00:00Z"),
            ]
            return
        }
        #endif
        await perform { try await self.loadMessages(ticket.id, reset: true) }
    }
    func resolveTicket(_ ticket: JotleySupportTicket) async {
        await changeTicket(ticket, deleting: false)
    }
    func deleteConversation(_ ticket: JotleySupportTicket) async {
        await changeTicket(ticket, deleting: true)
    }
    private func changeTicket(_ ticket: JotleySupportTicket, deleting: Bool) async {
        await perform {
            #if DEBUG && targetEnvironment(simulator)
            if !self.isDesignPreview {
                try await self.sendTicketChange(ticket.id, deleting: deleting)
            }
            #else
            try await self.sendTicketChange(ticket.id, deleting: deleting)
            #endif
            guard let current = self.account, current.tickets.contains(where: { $0.id == ticket.id }) else { return }
            let otherTickets = current.tickets.filter { $0.id != ticket.id }
            let tickets = deleting ? otherTickets : [
                JotleySupportTicket(id: ticket.id, reference: ticket.reference, subject: ticket.subject,
                                    topic: ticket.topic, status: "resolved", purchase: ticket.purchase)
            ] + otherTickets
            self.account = JotleySupportAccount(user: current.user, tickets: tickets, purchases: current.purchases,
                                               nextOffset: deleting ? current.nextOffset.map { max(0, $0 - 1) } : current.nextOffset)
            if deleting {
                self.replyDrafts[ticket.id] = nil
                if self.pendingReply?.ticket == ticket.id { self.pendingReply = nil }
                if self.selectedTicketID == ticket.id {
                    self.selectedTicketID = nil; self.messages = []; self.messageBefore = nil
                }
                self.notice = "Conversation deleted."
            }
        }
    }
    private func sendTicketChange(_ ticketID: String, deleting: Bool) async throws {
        struct Result: Decodable { let updated: Bool }
        let input = deleting ? ["ticketID": ticketID, "confirmation": "delete-conversation"] : ["ticketID": ticketID]
        let result: Result = try await api(deleting ? "tickets/delete" : "tickets/resolve", body: input)
        guard result.updated else { throw SupportFailure.message("The ticket could not be updated. Please try again.") }
    }
    func buyAppStoreTicket() async {
        guard let product, product.id == Self.productID, canBuy else { return }
        if !unusedPurchases.isEmpty { requestUnlocked = true; return }
        await perform {
            guard let owner = self.session.flatMap({ UUID(uuidString: $0.userID) }) else { throw SupportFailure.message("Sign in with Apple first.") }
            switch try await product.purchase(options: [.appAccountToken(owner)]) {
            case .success(let verification):
                self.pendingVerification = true
                try await self.claim(verification)
            case .pending: self.notice = "Apple is waiting for purchase approval. Your request unlocks after the purchase is confirmed."
            case .userCancelled: break
            @unknown default: self.notice = "Apple could not confirm this purchase."
            }
        }
    }
    func macCheckout() async -> URL? {
        guard !Self.usesAppStore, canBuy else { return nil }
        var checkout: URL?
        await perform {
            struct Result: Decodable { let url: String }
            let result: Result = try await self.api("checkout", body: [:])
            guard let url = URL(string: result.url), url.scheme == "https", url.host == "checkout.stripe.com" else { throw SupportFailure.message("Checkout could not open.") }
            checkout = url
        }
        return checkout
    }
    func openRequest(subject: String, topic: String, message: String) async {
        guard let purchase = unusedPurchases.first else { notice = "Purchase a ticket before opening a new request."; return }
        await perform {
            struct Result: Decodable { let ticketID: String }
            let result: Result = try await self.api("tickets", body: ["purchaseID": purchase.id, "subject": subject, "topic": topic, "message": message])
            try await self.refreshAccount()
            self.selectedTicketID = result.ticketID; self.requestUnlocked = false
            try await self.loadMessages(result.ticketID, reset: true)
        }
    }
    func reply() async {
        guard let ticket = selectedTicket, ticket.status != "resolved",
              let body = replyDrafts[ticket.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return }
        let id = ticket.id
        if pendingReply?.ticket != id || pendingReply?.body != body { pendingReply = (id, body, UUID().uuidString) }
        guard let attempt = pendingReply else { return }
        await perform {
            struct Result: Decodable { let messageID: String }
            let _: Result = try await self.api("reply", body: ["ticketID": id, "message": body, "messageID": attempt.id])
            self.replyDrafts[id] = ""; self.pendingReply = nil
            try await self.loadMessages(id, reset: false); try await self.refreshAccount()
        }
    }
    func earlierMessages() async {
        guard let id = selectedTicketID, let before = messageBefore else { return }
        await perform { try await self.loadMessages(id, reset: false, before: before) }
    }
    private func loadMessages(_ ticket: String, reset: Bool, before: String? = nil) async throws {
        struct Page: Decodable { let messages: [JotleySupportMessage]; let before: String? }
        let path = "messages?ticket=\(ticket)" + (before.map { "&before=\($0)" } ?? "")
        let page: Page = try await api(path)
        guard selectedTicketID == ticket else { return }
        let existing = reset ? [] : messages
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for message in page.messages { byID[message.id] = message }
        messages = byID.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        if reset || before != nil { messageBefore = page.before }
    }
    private func refreshAccount() async throws {
        let owner = session?.userID
        let refreshed: JotleySupportAccount = try await api("me")
        guard session?.userID == owner, refreshed.user.id.lowercased() == owner?.lowercased() else { return }
        // Keep older pages and an open conversation visible when polling page one.
        let previous = account?.tickets ?? []
        let keepOlderPages = previous.count > 50 && refreshed.nextOffset != nil
        let merged = refreshed.tickets + (keepOlderPages ? previous.filter { old in !refreshed.tickets.contains { $0.id == old.id } } : [])
        account = JotleySupportAccount(user: refreshed.user, tickets: merged, purchases: refreshed.purchases,
                                       nextOffset: keepOlderPages ? account?.nextOffset : refreshed.nextOffset)
        JotleySupporterStore.shared.recognizeSupportPurchases(refreshed.purchases)
    }
    func moreTickets() async {
        guard let offset = account?.nextOffset else { return }
        await perform {
            let page: JotleySupportAccount = try await self.api("me?offset=\(offset)")
            guard let current = self.account, current.user.id == page.user.id else { return }
            self.account = JotleySupportAccount(user: page.user, tickets: current.tickets + page.tickets.filter { new in !current.tickets.contains { $0.id == new.id } }, purchases: page.purchases, nextOffset: page.nextOffset)
        }
    }
    private func reconcilePurchases() async throws {
        guard Self.usesAppStore else { return }
        for await verification in StoreKit.Transaction.unfinished { try await claim(verification) }
    }
    private func claim(_ verification: VerificationResult<StoreKit.Transaction>) async throws {
        let transaction: StoreKit.Transaction
        switch verification {
        case .verified(let value): transaction = value
        case .unverified(let value, _):
            if value.productID == Self.productID { throw SupportFailure.message("Apple could not verify the purchase. No support credit has been granted.") }
            return
        }
        guard transaction.productID == Self.productID else { return }
        guard let owner = session.flatMap({ UUID(uuidString: $0.userID) }), transaction.appAccountToken == owner,
              transaction.productType == .consumable, transaction.revocationDate == nil else {
            throw SupportFailure.message("Sign in to the Apple support account used for this purchase.")
        }
        pendingVerification = true
        struct Result: Decodable { let purchaseID: String }
        let _: Result = try await api("apple/claim", body: ["signedTransaction": verification.jwsRepresentation])
        // Do not finish a consumable until the server has durably saved its credit.
        await transaction.finish()
        if session?.userID.lowercased() == owner.uuidString.lowercased() {
            try await refreshAccount()
            pendingVerification = false
            requestUnlocked = !unusedPurchases.isEmpty
        }
    }
    private func perform(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; notice = nil
        defer { busy = false }
        do { try await work() }
        catch is CancellationError { }
        catch { notice = (error as? SupportFailure)?.errorDescription ?? "Jotley Support could not connect. Your purchase and drafts are kept; please try again." }
    }
    private func renewSession() async throws {
        if let refreshTask { session = try await refreshTask.value; return }
        guard let current = session else { throw SupportFailure.message("Sign in with Apple to continue.") }
        let generation = authenticationGeneration
        let task = Task { () throws -> JotleySupportSession in
            let next: JotleySupportSession = try await self.api("auth/refresh", body: ["refreshToken": current.refreshToken], authenticated: false)
            guard !Task.isCancelled, self.authenticationGeneration == generation else { throw CancellationError() }
            guard next.userID == current.userID else { throw SupportFailure.message("Sign in with Apple again.") }
            try SupportSessionKeychain.save(next)
            return next
        }
        refreshTask = task
        defer { refreshTask = nil }
        session = try await task.value
    }
    private func api<Response: Decodable>(_ path: String, body: [String: String]? = nil, authenticated: Bool = true, retry: Bool = true) async throws -> Response {
        if authenticated {
            guard session != nil else { throw SupportFailure.message("Sign in with Apple to continue.") }
            if (session?.expiresAt ?? 0) < Date().timeIntervalSince1970 + 45 { try await renewSession() }
        }
        guard let url = URL(string: "https://jotley.ai/api/support/" + path) else { throw SupportFailure.message("Support is unavailable.") }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if authenticated, let session { request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupportFailure.message("Support could not respond.") }
        if http.statusCode == 401, authenticated, retry {
            try await renewSession()
            return try await api(path, body: body, authenticated: true, retry: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupportFailure.message((try? JSONDecoder().decode(SupportAPIError.self, from: data).error) ?? "Support is temporarily unavailable. Please try again later.")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }
}
