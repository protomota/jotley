import SwiftUI
import StoreKit
import FoundationModels
import Combine
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Local alerts only: no APNs registration, network request or note content.
@MainActor final class JotleySummaryNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = JotleySummaryNotifications(defaults: .standard, center: .current())
    static let enabledKey = "jotleySummaryNotificationsEnabled"
    static let requestPrefix = "jotley.summary."
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deliveryError: String?
    @Published var noteToOpen: UUID?
    private let defaults: UserDefaults
    private let authorization: () async -> UNAuthorizationStatus
    private let requestAuthorization: () async throws -> Bool
    private let enqueue: (UNNotificationRequest) async throws -> Void
    private let isActive: () -> Bool
    private var center: UNUserNotificationCenter?
    private var permissionTask: Task<Void, Never>?
    private var pending = Set<UUID>()
    private var delivered = Set<UUID>()
    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    init(defaults: UserDefaults, authorization: @escaping () async -> UNAuthorizationStatus,
         requestAuthorization: @escaping () async throws -> Bool,
         enqueue: @escaping (UNNotificationRequest) async throws -> Void, isActive: @escaping () -> Bool) {
        self.defaults = defaults; self.authorization = authorization
        self.requestAuthorization = requestAuthorization; self.enqueue = enqueue; self.isActive = isActive
        super.init()
    }
    convenience init(defaults: UserDefaults, center: UNUserNotificationCenter) {
        self.init(defaults: defaults, authorization: { await center.notificationSettings().authorizationStatus },
            requestAuthorization: { try await center.requestAuthorization(options: [.alert, .sound]) },
            enqueue: { try await center.add($0) }, isActive: {
                #if os(iOS)
                return UIApplication.shared.applicationState == .active
                #else
                return NSApp?.isActive == true
                #endif
            })
        self.center = center
    }
    func install() { center?.delegate = self }
    func refreshAuthorization() async { authorizationStatus = await authorization() }
    // Start the system consent request alongside inference, never at app launch.
    func prepareForSummary() {
        guard isEnabled, permissionTask == nil else { return }
        permissionTask = Task {
            await refreshAuthorization()
            if authorizationStatus == .notDetermined, isActive(), isEnabled {
                do { _ = try await requestAuthorization(); await refreshAuthorization() }
                catch { deliveryError = "Notifications could not be enabled. Your summaries still work normally." }
            }
            permissionTask = nil
        }
    }
    static func request(noteID: UUID, generationID: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Summary ready"
        content.body = "Your summary is saved. Open Jotley to read it."
        content.sound = .default
        content.userInfo = ["noteID": noteID.uuidString]
        return UNNotificationRequest(identifier: requestPrefix + generationID.uuidString, content: content, trigger: nil)
    }
    // Call only after a completed summary has been committed to the note store.
    func summarySaved(noteID: UUID?, generationID: UUID = UUID()) async {
        guard let noteID, isEnabled, !pending.contains(generationID), !delivered.contains(generationID) else { return }
        pending.insert(generationID); defer { pending.remove(generationID) }
        if let permissionTask { await permissionTask.value }
        await refreshAuthorization()
        guard isEnabled, [.authorized, .provisional].contains(authorizationStatus) else { return }
        do {
            try await enqueue(Self.request(noteID: noteID, generationID: generationID))
            if delivered.count >= 128 { delivered.removeAll() }
            delivered.insert(generationID); deliveryError = nil
        } catch { deliveryError = "The summary was saved, but its notification could not be shown." }
    }
    @discardableResult func openSummary(from request: UNNotificationRequest) -> Bool {
        guard request.identifier.hasPrefix(Self.requestPrefix),
              let value = request.content.userInfo["noteID"] as? String, let id = UUID(uuidString: value) else { return false }
        noteToOpen = id
        #if os(macOS)
        NSApp?.activate(ignoringOtherApps: true)
        #endif
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler(isEnabled ? [.banner, .sound] : []) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier { openSummary(from: response.notification.request) }
            completionHandler()
        }
    }
}

struct JotleySummaryNotificationSettings: View {
    @AppStorage(JotleySummaryNotifications.enabledKey) private var enabled = true
    @ObservedObject private var notifications = JotleySummaryNotifications.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Notify when a summary is ready", isOn: $enabled)
                .tint(.themePrimaryAccent).accessibilityIdentifier("settingsSummaryNotificationsToggle")
            Text("Local alerts contain no note text and work offline. A notification is sent only after a completed summary is saved.")
                .font(.caption).foregroundStyle(.secondary)
            if enabled && notifications.authorizationStatus == .notDetermined {
                Button("Allow Notifications") { notifications.prepareForSummary() }
                    .foregroundStyle(Color.themeActionText)
                    .accessibilityIdentifier("settingsAllowSummaryNotifications")
                Text("You can also allow notifications when you next generate a summary.").font(.caption).foregroundStyle(.secondary)
            } else if enabled && notifications.authorizationStatus == .denied {
                Text("Notifications are blocked in system Settings. Allow Jotley notifications there to receive alerts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = notifications.deliveryError { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .task { await notifications.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await notifications.refreshAuthorization() } } }
        .onChange(of: enabled) { _, value in if value { notifications.prepareForSummary() } }
    }
}

// Hardware eligibility is distinct from enabling Apple Intelligence or preparing
// its models. Apple's API supports all eligible devices without guessed model IDs.
enum JotleyAppleIntelligenceEligibility {
    static func supports(availability: SystemLanguageModel.Availability) -> Bool {
        switch availability {
        case .available: return true
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return false
            case .appleIntelligenceNotEnabled, .modelNotReady: return true
            @unknown default: return false
            }
        }
    }
    static var unsupportedReason: String? {
        guard !supports(availability: SystemLanguageModel.default.availability) else { return nil }
        #if os(iOS)
        return "Jotley requires Apple Intelligence-capable hardware and iOS or iPadOS 27 or later. Supported devices include iPhone 15 Pro/Pro Max, iPhone 16 or newer, iPhone Air, iPad with M1 or later, and iPad mini with A17 Pro. This device does not support Apple Intelligence."
        #else
        return "Jotley requires an Apple Intelligence-capable Mac running macOS 27 or later. This Mac does not support Apple Intelligence."
        #endif
    }
}

// Local, device-only milestones. Failed, canceled and empty results never count.
@MainActor final class JotleyEngagement: ObservableObject {
    static let shared = JotleyEngagement()
    static let countKey = "jotleyCompletedLocalSummaries"
    static let reviewKey = "jotleyNativeReviewRequested"
    static let website = URL(string: "https://jotley.ai")!
    static let tipURL = URL(string: "https://jotley.ai/tips")!
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6746770199?action=write-review")!
    static let feedbackURL = URL(string: "mailto:jotly-support@protomota.com")!
    enum Prompt { case review }
    @Published private(set) var completedActions: Int
    @Published private(set) var processingCount = 0
    private let defaults: UserDefaults
    private var lastPromptActionCount = -1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedActions = max(0, defaults.integer(forKey: Self.countKey))
    }
    func completedSummary(result: String) {
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        completedActions = min(completedActions, 1_000) + 1
        defaults.set(completedActions, forKey: Self.countKey)
    }
    func beginProcessing() { processingCount += 1 }
    func endProcessing() { processingCount = max(0, processingCount - 1) }
    // Claim before presentation so multiple windows cannot prompt twice.
    func claimPrompt(isIdle: Bool) -> Prompt? {
        guard isIdle, processingCount == 0, completedActions != lastPromptActionCount else { return nil }
        if completedActions >= 5 && !defaults.bool(forKey: Self.reviewKey) {
            defaults.set(true, forKey: Self.reviewKey)
            lastPromptActionCount = completedActions
            return .review
        }
        return nil
    }
}

struct JotleyEngagementPrompts: ViewModifier {
    let isIdle: Bool
    @ObservedObject private var engagement = JotleyEngagement.shared
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    private var presentationKey: String {
        "\(engagement.completedActions)-\(engagement.processingCount)-\(isIdle)-\(scenePhase == .active)"
    }
    private var canPresent: Bool {
        #if os(iOS)
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController == nil }
        #else
        return NSApp.isActive && NSApp.mainWindow?.attachedSheet == nil && NSApp.keyWindow?.isSheet == false
        #endif
    }
    func body(content: Content) -> some View {
        content.task(id: presentationKey) {
            guard isIdle, scenePhase == .active else { return }
            // Show the completed result first; recording/backgrounding cancels this task.
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled, isIdle, scenePhase == .active, canPresent else { return }
            if engagement.claimPrompt(isIdle: isIdle) == .review { requestReview() }
        }
    }
}

// The styled card is opened explicitly from Settings. Automatic review requests
// remain Apple's native StoreKit prompt, never a custom review solicitation.
struct JotleySupportCardPresentation: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var supportOverlay: some View {
        GeometryReader { geometry in
            #if os(iOS)
            let compact = geometry.size.width < 600
            #else
            let compact = false
            #endif
            let heightFraction = dynamicTypeSize.isAccessibilitySize || geometry.size.height < 800 ? 0.92 : 0.83
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .accessibilityHidden(true)
                JotleySupportView { isPresented = false }
                    .frame(maxWidth: max(0, min(geometry.size.width - (compact ? 24 : 48), 520)),
                           maxHeight: max(0, min(geometry.size.height - 24,
                                               compact ? geometry.size.height * heightFraction : 720)))
                    .padding(.horizontal, compact ? 12 : 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .bottom : .center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    @ViewBuilder private func presentedContent(_ content: Content) -> some View {
        #if os(iOS)
        // A transparent modal host blocks background UIKit navigation and
        // provides modal accessibility. All visible UI is our themed card.
        content.fullScreenCover(isPresented: $isPresented) {
            supportOverlay.presentationBackground(.clear)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            JotleySupportView { isPresented = false }
                .frame(width: 600, height: 760).padding(24)
                .background(Color.themeBackground)
        }
        #endif
    }
    func body(content: Content) -> some View {
        presentedContent(content)
            .animation(.easeOut(duration: 0.18), value: isPresented)
    }
}

// No geographic guesses: unknown or restricted storefronts do not advertise web tips.
// The individual-to-individual gift exception is not assumed for a company recipient.
enum JotleyWebsiteTipPolicy {
    static func allowsTips(countryCode: String?) -> Bool { countryCode == "USA" }
    static func currentPermission() async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["JOTLEY_SCREENSHOT_DATA"] != nil,
           let country = ProcessInfo.processInfo.environment["JOTLEY_TEST_STOREFRONT"] {
            return allowsTips(countryCode: country)
        }
        #endif
        return allowsTips(countryCode: await Storefront.current?.countryCode)
    }
}

// User-opened support menu: Apple's review page, no custom stars or rating incentives.
struct JotleySupportView: View {
    let dismiss: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @State private var allowsWebsiteTips = false
    @State private var contentHeight: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(cardFont(.title3.weight(.medium), macSize: 22, weight: .medium))
                    .foregroundColor(.themePrimaryAccent)
                    .frame(width: 40, height: 40)
                    .background(Color.themePrimaryAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Jotley").font(cardFont(.headline, macSize: 18, weight: .semibold)).foregroundColor(.themeTextPrimary)
                    Text("Completely free")
                        .font(cardFont(.caption, macSize: 14)).foregroundColor(.themeTextSecondary)
                }
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(cardFont(.subheadline.weight(.semibold), macSize: 16, weight: .semibold))
                        .foregroundColor(.themeTextSecondary).frame(width: 44, height: 44)
                        .background(Color.themeBackground, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close support message")
                .accessibilityIdentifier("jotleySupportClose")
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Free software.\nSupported by people.")
                        .font(cardFont(.title2.weight(.bold), macSize: 28, weight: .bold)).foregroundColor(.themeTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("jotleySupportTitle")
                        .accessibilityAddTraits(.isHeader)
                    Text("Your rating and review help others discover Jotley. Protomota Software makes Jotley free for personal and paid work.")
                        .font(cardFont(.subheadline, macSize: 16))
                        .foregroundColor(.themeTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                    VStack(spacing: 12) {
                        Link(destination: JotleyEngagement.reviewURL) {
                            actionLabel("Rate & Review Jotley", subtitle: "On the App Store", icon: "star", highlighted: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rate and review Jotley on the App Store")
                        .accessibilityIdentifier("jotleySupportReview")
                        if allowsWebsiteTips {
                            Link(destination: JotleyEngagement.tipURL) {
                                actionLabel("Tip the Developer", subtitle: "Optional · jotley.ai/tips", icon: "heart.circle")
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("jotleySupportTip")
                        }
                        ShareLink(item: JotleyEngagement.website) {
                            actionLabel("Share Jotley", subtitle: "Help others discover Jotley", icon: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("jotleySupportShare")
                        Link(destination: JotleyEngagement.feedbackURL) {
                            actionLabel("Send Feedback", subtitle: "Help shape what comes next", icon: "bubble.left.and.bubble.right")
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportFeedback")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.bottom, 20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(maxHeight: contentHeight)
            .scrollBounceBehavior(.basedOnSize)
            Rectangle().fill(Color.themeAccent.opacity(0.65)).frame(height: 1).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 14) {
                supportFooter.frame(maxWidth: .infinity, alignment: .leading)
                dismissButton
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 20)
        }
        .multilineTextAlignment(.leading)
        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.themeAccent.opacity(0.6), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jotleyStyledSupportPrompt")
        .task {
            let permitted = await JotleyWebsiteTipPolicy.currentPermission()
            guard !Task.isCancelled else { return }
            allowsWebsiteTips = permitted
        }
    }
    private func cardFont(_ mobile: Font, macSize: CGFloat, weight: Font.Weight = .regular) -> Font {
        #if os(macOS)
        // Native macOS semantic fonts are much smaller than the phone card's.
        return .system(size: macSize, weight: weight)
        #else
        return mobile
        #endif
    }
    private var supportFooter: some View {
        Text("Support is optional. All features stay free.")
            .font(cardFont(.caption, macSize: 14)).foregroundColor(.themeTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Back to Settings").font(cardFont(.body.weight(.medium), macSize: 16, weight: .medium))
                .foregroundColor(.themeTextPrimary)
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.themeBackground, in: Capsule())
        }
        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("jotleySupportDismiss")
    }
    private func actionLabel(_ title: String, subtitle: String, icon: String, highlighted: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(cardFont(.title3, macSize: 22))
                .foregroundColor(highlighted ? .white : .themePrimaryAccent)
                .frame(width: highlighted ? 40 : 32, height: highlighted ? 40 : 32)
                .background(highlighted ? Color.white.opacity(0.16) : Color.themePrimaryAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(cardFont(.body.weight(.semibold), macSize: 17, weight: .semibold)).foregroundColor(highlighted ? .white : .themeTextPrimary)
                Text(subtitle).font(cardFont(.caption, macSize: 14)).foregroundColor(highlighted ? .white.opacity(0.9) : .themeTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").font(cardFont(.caption, macSize: 14))
                .foregroundColor(highlighted ? .white.opacity(0.9) : .themeTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(highlighted ? 14 : 12)
        .frame(minHeight: highlighted ? 74 : 58)
        .background(highlighted ? Color.themePrimaryAccent : Color.themeBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(highlighted ? Color.themePrimaryAccent.opacity(0.35) : Color.themeAccent.opacity(0.55), lineWidth: 1))
    }
}

struct JotleySupportLinks: View {
    @State private var showingSupport = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Link(destination: JotleyEngagement.reviewURL) {
                Label("Rate & Review Jotley on the App Store", systemImage: "star")
                    .font(.body.weight(.semibold)).frame(minHeight: 44)
            }
            .accessibilityIdentifier("settingsRateJotley")
            Button("More Ways to Support Jotley") { showingSupport = true }
                .frame(minHeight: 44).accessibilityIdentifier("settingsSupportJotleyCard")
            Link("Jotley's Website", destination: JotleyEngagement.website)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .tint(Color.themeActionText)
        #endif
        .modifier(JotleySupportCardPresentation(isPresented: $showingSupport))
    }
}
