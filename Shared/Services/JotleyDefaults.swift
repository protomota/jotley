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

/// Keep glass controls consistent across the Mac and mobile custom headers.
struct JotleyGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var circular = false
    private var controlHeight: CGFloat {
        #if os(macOS)
        36
        #else
        44
        #endif
    }
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if circular {
                configuration.label.frame(width: controlHeight, height: controlHeight)
                    .contentShape(Circle()).glassEffect(.regular.interactive(), in: Circle())
            } else {
                configuration.label.padding(.horizontal, 16).frame(minHeight: controlHeight)
                    .contentShape(Capsule()).glassEffect(.regular.interactive(), in: Capsule())
            }
        }
        .foregroundStyle(configuration.role == .destructive ? Color.red : Color.themeTextPrimary)
        .opacity(isEnabled ? 1 : 0.45)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Local, device-only milestones. Failed, canceled and empty results never count.
@MainActor final class JotleyEngagement: ObservableObject {
    static let shared = JotleyEngagement()
    static let countKey = "jotleyCompletedLocalSummaries"
    static let reviewKey = "jotleyNativeReviewRequested"
    static let clicksKey = "jotleySupportClickedActions.v1"
    static let presentedCountKey = "jotleySupportPresentedSummaryCount.v1"
    static let stoppedKey = "jotleySupportAutomaticRemindersStopped.v1"
    static let website = URL(string: "https://jotley.ai")!
    static let tipURL = URL(string: "https://jotley.ai/tips")!
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6746770199?action=write-review")!
    static let feedbackURL = URL(string: "mailto:jotly-support@protomota.com")!
    enum Action: String, CaseIterable { case review, tip, share, feedback }
    static let dismissingActions = Set(Action.allCases)
    enum Prompt { case review, support }
    @Published private(set) var completedActions: Int
    @Published private(set) var clickedActions: Set<Action>
    @Published private(set) var automaticRemindersStopped: Bool
    @Published private(set) var processingCount = 0
    let usesCustomReminders: Bool
    private let defaults: UserDefaults
    private var lastPromptActionCount = -1

    init(defaults: UserDefaults = .standard, usesCustomReminders: Bool? = nil) {
        self.defaults = defaults
        #if os(macOS) && !STORE_BUILD
        self.usesCustomReminders = usesCustomReminders ?? true
        #else
        self.usesCustomReminders = usesCustomReminders ?? false
        #endif
        completedActions = max(0, defaults.integer(forKey: Self.countKey))
        let storedClicks = Set((defaults.stringArray(forKey: Self.clicksKey) ?? []).compactMap(Action.init(rawValue:)))
        let stopped = defaults.bool(forKey: Self.stoppedKey) || !storedClicks.isDisjoint(with: Self.dismissingActions)
        clickedActions = storedClicks
        automaticRemindersStopped = stopped
        if stopped { defaults.set(true, forKey: Self.stoppedKey) }
    }
    func completedSummary(result: String) {
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        completedActions = min(max(completedActions, defaults.integer(forKey: Self.countKey)), 1_000_000_000) + 1
        defaults.set(completedActions, forKey: Self.countKey)
    }
    func beginProcessing() { processingCount += 1 }
    func endProcessing() { processingCount = max(0, processingCount - 1) }
    func hasClicked(_ action: Action) -> Bool {
        (defaults.stringArray(forKey: Self.clicksKey) ?? []).contains(action.rawValue)
    }
    func recordClick(_ action: Action) {
        var actions = Set((defaults.stringArray(forKey: Self.clicksKey) ?? []).compactMap(Action.init(rawValue:)))
        actions.insert(action)
        defaults.set(actions.map(\.rawValue).sorted(), forKey: Self.clicksKey)
        clickedActions = actions
        if Self.dismissingActions.contains(action) {
            automaticRemindersStopped = true
            defaults.set(true, forKey: Self.stoppedKey)
        }
    }
    func supportCardOpened() {
        guard usesCustomReminders else { return }
        defaults.set(completedActions, forKey: Self.presentedCountKey)
    }
    func resetClickedActions() {
        defaults.removeObject(forKey: Self.clicksKey)
        clickedActions = []
        // Reset the marks, never restart reminders retired by a support action.
        supportCardOpened()
    }
    var hasPendingSupportReminder: Bool {
        usesCustomReminders && completedActions >= 5
            && completedActions >= defaults.integer(forKey: Self.presentedCountKey) + 5
            && !defaults.bool(forKey: Self.stoppedKey)
            && Self.dismissingActions.allSatisfy { !hasClicked($0) }
    }
    // Claim before presentation so multiple windows cannot prompt twice.
    func claimPrompt(isIdle: Bool) -> Prompt? {
        guard isIdle, processingCount == 0, completedActions != lastPromptActionCount else { return nil }
        if usesCustomReminders {
            guard hasPendingSupportReminder else { return nil }
            supportCardOpened()
            lastPromptActionCount = completedActions
            return .support
        }
        if completedActions >= 5 && !defaults.bool(forKey: Self.reviewKey) && !hasClicked(.review) {
            defaults.set(true, forKey: Self.reviewKey)
            lastPromptActionCount = completedActions
            return .review
        }
        return nil
    }
}

struct JotleyEngagementPrompts: ViewModifier {
    let isIdle: Bool
    @ObservedObject var engagement = JotleyEngagement.shared
    @State private var showingSupport = false
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
    @ViewBuilder private func supportPresentation(_ content: Content) -> some View {
        #if os(macOS)
        content
        .modifier(JotleySupportCardPresentation(isPresented: $showingSupport, engagement: engagement, isAutomatic: true))
        .onChange(of: isIdle) { _, idle in
            if !idle { showingSupport = false }
        }
        #else
        content
        #endif
    }
    func body(content: Content) -> some View {
        supportPresentation(content)
        .task(id: presentationKey) {
            guard isIdle, scenePhase == .active else { return }
            guard !engagement.usesCustomReminders || engagement.hasPendingSupportReminder else { return }
            // Show the completed result first; transcribing/backgrounding cancels this task.
            do { try await Task.sleep(for: .seconds(engagement.usesCustomReminders ? 11 : 2)) } catch { return }
            // A different sheet or inactive window must not consume a reminder.
            while engagement.usesCustomReminders && !canPresent {
                guard !Task.isCancelled, isIdle, scenePhase == .active, engagement.hasPendingSupportReminder else { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            guard !Task.isCancelled, isIdle, scenePhase == .active, canPresent else { return }
            switch engagement.claimPrompt(isIdle: isIdle) {
            case .review: requestReview()
            case .support: showingSupport = true
            case nil: break
            }
        }
    }
}

// Direct Mac downloads may repeat the styled card. Store editions keep automatic
// requests native; the styled card is opened explicitly from Settings.
struct JotleySupportCardPresentation: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject var engagement = JotleyEngagement.shared
    var isAutomatic = false
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
                JotleySupportView(engagement: engagement, isAutomatic: isAutomatic) { isPresented = false }
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
            JotleySupportView(engagement: engagement, isAutomatic: isAutomatic) { isPresented = false }
                .frame(width: 600, height: 780)
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
        #if os(macOS) && !STORE_BUILD
        return true
        #else
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["JOTLEY_SCREENSHOT_DATA"] != nil,
           let country = ProcessInfo.processInfo.environment["JOTLEY_TEST_STOREFRONT"] {
            return allowsTips(countryCode: country)
        }
        #endif
        return allowsTips(countryCode: await Storefront.current?.countryCode)
        #endif
    }
}

// Apple's review page, with no custom stars, rating incentives or payment gates.
struct JotleySupportView: View {
    @ObservedObject var engagement = JotleyEngagement.shared
    var isAutomatic = false
    let dismiss: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @State private var allowsWebsiteTips = false
    @State private var contentHeight: CGFloat?
    #if os(macOS)
    @Environment(\.openURL) private var openURL
    @State private var shareAnchor = NSView()
    @State private var didReset = false
    #endif
    var body: some View {
        #if os(macOS)
        macCard
        #else
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
        #endif
    }
    #if os(macOS)
    private var macCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "star.bubble")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.themePrimaryAccent)
                    .frame(width: 66, height: 66)
                    .background(Color.themePrimaryAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 7) {
                    Text(isAutomatic ? "YOUR SUMMARY, SAVED" : "RATINGS & SUPPORT")
                        .font(.system(size: 12, weight: .bold)).tracking(1.4)
                        .foregroundStyle(Color.themeTextSecondary)
                    Text("Free software.\nSupported by people.")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.themeTextPrimary)
                }
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32).contentShape(Circle())
                }.buttonStyle(JotleyGlassButtonStyle(circular: true))
                    .accessibilityLabel("Close support message").accessibilityIdentifier("jotleySupportClose")
            }.padding(.bottom, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your rating and review make a difference.")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.themeTextPrimary)
                        Text("Protomota Software believes software should be free. We’re giving our apps away, including Jotley—with every feature included. Your ratings and reviews help more people discover Jotley. Sharing, feedback and optional tips help us keep building. Thank you for your support.")
                            .font(.system(size: 16)).foregroundStyle(Color.themeTextSecondary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 10) {
                        Button { visit(.review, url: JotleyEngagement.reviewURL) } label: {
                            macAction("Rate & Review Jotley", detail: "Leave a rating and share your experience",
                                      icon: "star.bubble", kind: .review, primary: true)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportReview")
                        if allowsWebsiteTips {
                            Button { visit(.tip, url: JotleyEngagement.tipURL) } label: {
                                macAction("Tip the Developer", detail: "Opens jotley.ai/tips in your browser",
                                          icon: "heart.circle", kind: .tip)
                            }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportTip")
                        }
                        Button {
                            engagement.recordClick(.share); didReset = false
                            JotleySupportSharing.shared.present(from: shareAnchor, dismiss: dismiss)
                        } label: {
                            macAction("Share Jotley", detail: "Help others discover private voice notes",
                                      icon: "square.and.arrow.up", kind: .share)
                        }.buttonStyle(.plain).background(JotleySupportShareAnchor(view: shareAnchor))
                            .accessibilityIdentifier("jotleySupportShare")
                        Button { visit(.feedback, url: JotleyEngagement.feedbackURL) } label: {
                            macAction("Send Feedback", detail: "Your ideas help shape what comes next",
                                      icon: "bubble.left.and.bubble.right", kind: .feedback)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportFeedback")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(didReset ? (engagement.automaticRemindersStopped
                             ? "Saved clicks reset. Automatic reminders stay off." : "Saved clicks reset.") :
                             (engagement.automaticRemindersStopped ? "Automatic reminders are off. " : "Any one action turns off automatic reminders. ")
                             + "Checkmarks remember clicks, not completed reviews, tips or shares.")
                            .font(.system(size: 12)).foregroundStyle(Color.themeTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Reset saved clicks") {
                            engagement.resetClickedActions(); didReset = true
                        }.buttonStyle(.plain).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.themeTextPrimary)
                            .padding(.vertical, 6).accessibilityIdentifier("jotleySupportReset")
                    }
                }.padding(.trailing, 2)
            }.scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 18) {
                Text("All features stay free.\nSupport is always optional.")
                    .font(.system(size: 12)).foregroundStyle(Color.themeTextSecondary)
                Spacer(minLength: 0)
                Button(isAutomatic ? "Back to Notes" : "Back to Settings", action: dismiss)
                    .font(.system(size: 15, weight: .semibold)).buttonStyle(JotleyGlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("jotleySupportDismiss")
            }.padding(.top, 22)
        }.padding(30)
            .background(Color.themeContentBackground)
            .accessibilityElement(children: .contain).accessibilityIdentifier("jotleyStyledSupportPrompt")
            .onAppear { engagement.supportCardOpened() }
            .task { allowsWebsiteTips = await JotleyWebsiteTipPolicy.currentPermission() }
    }
    private func visit(_ action: JotleyEngagement.Action, url: URL) {
        engagement.recordClick(action); didReset = false
        openURL(url)
        if JotleyEngagement.dismissingActions.contains(action) { dismiss() }
    }
    private func macAction(_ title: String, detail: String, icon: String,
                           kind: JotleyEngagement.Action, primary: Bool = false) -> some View {
        let onAccent: Color = theme.currentThemeColor == .purple ? .white : Color(white: 0.08)
        return HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 23))
                .foregroundStyle(primary ? onAccent : Color.themePrimaryAccent).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13))
                    .foregroundStyle(primary ? onAccent.opacity(0.9) : Color.themeTextSecondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: engagement.hasClicked(kind) ? "checkmark.circle.fill" : "arrow.up.right")
                .font(.system(size: 15)).foregroundStyle(primary ? onAccent : Color.themePrimaryAccent)
                .accessibilityLabel(engagement.hasClicked(kind) ? "Previously clicked" : "Open")
        }.foregroundStyle(primary ? onAccent : Color.themeTextPrimary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).contentShape(Rectangle())
            .background(primary ? Color.themePrimaryAccent : Color.themeBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.themeAccent.opacity(0.55), lineWidth: 1))
            .accessibilityValue(engagement.hasClicked(kind) ? "Clicked" : "Not clicked")
    }
    #endif
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

#if os(macOS)
private struct JotleySupportShareAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Retain sharing outside the support view so its picker survives that sheet closing.
@MainActor private final class JotleySupportSharing: NSObject, NSSharingServicePickerDelegate {
    static let shared = JotleySupportSharing()
    private var picker: NSSharingServicePicker?
    private var presentation: Task<Void, Never>?
    func present(from anchor: NSView, dismiss: () -> Void) {
        let parent = anchor.window?.sheetParent ?? NSApp.mainWindow
        dismiss()
        presentation?.cancel()
        presentation = Task { @MainActor in
            guard let parent else { return }
            // Let SwiftUI detach the dismissed sheet before anchoring the share picker.
            for _ in 0..<30 where parent.attachedSheet != nil {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            guard !Task.isCancelled, parent.isVisible, parent.attachedSheet == nil,
                  let content = parent.contentView else { return }
            let picker = NSSharingServicePicker(items: [JotleyEngagement.website])
            self.picker = picker
            picker.delegate = self
            picker.show(relativeTo: NSRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1),
                        of: content, preferredEdge: .minY)
        }
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        picker = nil
    }
}
#endif

struct JotleySupportLinks: View {
    @State private var showingSupport = false
    @Environment(\.openURL) private var openURL
    @State private var allowsWebsiteTips = false
    var body: some View {
        #if os(iOS)
        mobileRows
        #else
        VStack(alignment: .leading, spacing: 16) {
            Group {
                #if os(macOS)
                Button {
                    JotleyEngagement.shared.recordClick(.review)
                    openURL(JotleyEngagement.reviewURL)
                } label: { reviewLabel }
                #else
                Link(destination: JotleyEngagement.reviewURL) { reviewLabel }
                #endif
            }
            .accessibilityIdentifier("settingsRateJotley")
            Button(supportTitle) { showingSupport = true }
                .frame(minHeight: 44).accessibilityIdentifier("settingsSupportJotleyCard")
            Link("Jotley's Website", destination: JotleyEngagement.website)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .tint(Color.themeActionText)
        #endif
        .modifier(JotleySupportCardPresentation(isPresented: $showingSupport))
        #endif
    }
    #if os(iOS)
    private var mobileRows: some View {
        Group {
            Button { visit(.review, url: JotleyEngagement.reviewURL) } label: {
                supportRow("Rate on the App Store", systemImage: "star")
            }
            .accessibilityIdentifier("settingsRateJotley")
            if allowsWebsiteTips {
                Button { visit(.tip, url: JotleyEngagement.tipURL) } label: {
                    supportRow("Tip the Developer", systemImage: "cup.and.saucer")
                }
                .accessibilityIdentifier("settingsTipJotley")
            }
            ShareLink(item: JotleyEngagement.website) {
                supportRow("Share Jotley", systemImage: "square.and.arrow.up")
            }
            .simultaneousGesture(TapGesture().onEnded { JotleyEngagement.shared.recordClick(.share) })
            .accessibilityIdentifier("settingsShareJotley")
            Button { visit(.feedback, url: JotleyEngagement.feedbackURL) } label: {
                supportRow("Send Feedback", systemImage: "bubble.left.and.bubble.right")
            }
            .accessibilityIdentifier("settingsFeedbackJotley")
            Link(destination: JotleyEngagement.website) {
                supportRow("Jotley's Website", systemImage: "globe")
            }
            .accessibilityIdentifier("settingsJotleyWebsite")
        }
        .buttonStyle(.plain)
        .task { allowsWebsiteTips = await JotleyWebsiteTipPolicy.currentPermission() }
    }
    private func supportRow(_ title: String, systemImage: String) -> some View {
        MobileActionLabel(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
    private func visit(_ action: JotleyEngagement.Action, url: URL) {
        JotleyEngagement.shared.recordClick(action)
        openURL(url)
    }
    #endif
    private var reviewLabel: some View {
        Label("Rate & Review Jotley on the App Store", systemImage: "star")
            .font(.body.weight(.semibold)).frame(minHeight: 44)
    }
    private var supportTitle: String {
        #if os(macOS)
        return "More Information & Support"
        #else
        return "More Ways to Support Jotley"
        #endif
    }
}
