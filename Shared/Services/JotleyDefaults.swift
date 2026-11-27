import SwiftUI
import StoreKit
import FoundationModels
import Combine
import UserNotifications
import AVFoundation
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Local alerts only: no APNs registration, network request or note content.
@MainActor final class JotleySummaryNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = JotleySummaryNotifications(defaults: .standard, center: .current())
    static let enabledKey = "jotleySummaryNotificationsEnabled"
    static let enabledByDefault = true
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
    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? Self.enabledByDefault }

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
    // Ask during onboarding, from Settings, or when a summary is requested.
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

struct JotleyNoteOrganizationSettings: View {
    @AppStorage(LocalNoteOrganizationSettings.autoTagsKey) private var autoTags = true
    @AppStorage(LocalNoteOrganizationSettings.autoFoldersKey) private var autoFolders = true

    var body: some View {
        Toggle("Auto Tags", isOn: $autoTags)
            .tint(.themePrimaryAccent)
            .accessibilityIdentifier("settingsAutoTags")
        Toggle("Auto File Notes", isOn: $autoFolders)
            .tint(.themePrimaryAccent)
            .accessibilityIdentifier("settingsAutoFolders")
    }
}

struct JotleySummaryNotificationSettings: View {
    @AppStorage(JotleySummaryNotifications.enabledKey) private var enabled = JotleySummaryNotifications.enabledByDefault
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

/// Neutral glass for transcript and Ask AI bubbles.
struct JotleyTranscriptCard: ViewModifier {
    var accentOutline = false
    var cornerRadius: CGFloat = 12
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let accent = theme.currentThemeColor.color(in: colorScheme)
        return content.background {
            shape.fill(Color(white: colorScheme == .dark ? 0.18 : 0.95))
                .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.08), radius: 3, y: 1)
        }
        .overlay {
            shape.strokeBorder(
                accentOutline ? accent : Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.16),
                lineWidth: 1
            )
                .allowsHitTesting(false)
        }
    }
}

/// Feather only the edges with more transcript offscreen. Keep the first and
/// newest lines fully visible when the scroll view is at either end.
struct JotleyTranscriptEdgeFade: ViewModifier {
    private struct Edges: Equatable { var top = false; var bottom = false }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var edges = Edges()
    var topFadeHeight: CGFloat = 64
    var showsBottomFade = true
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Edges.self) { geometry in
                let offset = geometry.contentOffset.y
                return Edges(top: offset + geometry.contentInsets.top > 1,
                             // A remaining safe-area inset alone shouldn't dim the newest line.
                             bottom: offset + geometry.containerSize.height <
                                geometry.contentSize.height - 12)
            } action: { _, newEdges in
                edges = newEdges
            }
            .mask {
                if isEnabled {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            fade(toward: .bottom, height: min(topFadeHeight, geometry.size.height * 0.44),
                                 visible: edges.top)
                            Color.black
                            if showsBottomFade {
                                fade(toward: .top, height: min(18, geometry.size.height * 0.1),
                                     visible: edges.bottom)
                            }
                        }
                    }
                } else {
                    Color.black
                }
            }
    }

    private static let smoothStops: [Gradient.Stop] = (0...12).map { step in
        let position = CGFloat(step) / 12
        let opacity = position * position * position * (position * (6 * position - 15) + 10)
        return .init(color: .black.opacity(Double(opacity)), location: position)
    }

    private func fade(toward endPoint: UnitPoint, height: CGFloat, visible: Bool) -> some View {
        LinearGradient(stops: Self.smoothStops,
                       startPoint: endPoint == .bottom ? .top : .bottom, endPoint: endPoint)
            .overlay { Color.black.opacity(visible ? 0 : 1) }
            .frame(height: height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: visible)
    }
}

struct JotleyAskComposerSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var isFocused: Bool

    func body(content: Content) -> some View {
        let outline = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content.background(Color(white: colorScheme == .dark ? 0.17 : 0.96), in: outline)
            .overlay {
                outline.strokeBorder(
                    isFocused ? Color.themePrimaryAccent : Color.themeTextSecondary.opacity(0.24),
                    lineWidth: isFocused ? 2 : 1
                ).allowsHitTesting(false)
            }
    }
}

/// Let the presentation own the corners and shadow so the background follows
/// the sheet's outline as its size, safe area, and platform change.
struct JotleyGlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.presentationBackground {
            if reduceTransparency {
                Color.themeBackground
            } else {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay { Color.themeBackground.opacity(colorScheme == .dark ? 0.92 : 0.80) }
            }
        }
    }
}

/// A neutral drop shadow for brand marks and other standalone artwork.
struct JotleyControlShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(colorScheme == .dark ? 0.40 : 0.17), radius: 4, y: 2)
    }
}

/// Keep glass controls consistent across the Mac and mobile custom headers.
struct JotleyGlassButtonStyle: ButtonStyle {
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    var circular = false
    var diameter: CGFloat? = nil
    var keepsDisabledSurfaceVisible = false
    var floatsOverContent = false
    var usesTranslucentMaterial = false
    var usesAccentForeground = false

    private var theme: ThemeColor { themeManager.currentThemeColor }
    private var glassInk: Color {
        if circular || usesAccentForeground { return theme.color(in: colorScheme) }
        return .primary
    }

    private var controlHeight: CGFloat {
        if let diameter { return diameter }
        #if os(macOS)
        return 36
        #else
        return 44
        #endif
    }
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if circular {
                configuration.label.frame(width: controlHeight, height: controlHeight)
                    .contentShape(Circle()).background { background(in: Circle()) }
            } else {
                configuration.label.padding(.horizontal, 16).frame(minHeight: controlHeight)
                    .contentShape(Capsule()).background { background(in: Capsule()) }
            }
        }
        .foregroundStyle((configuration.role == .destructive ? Color.red : glassInk)
            .opacity(isEnabled ? 1 : keepsDisabledSurfaceVisible ? 0.82 : floatsOverContent ? 0.55 : 1))
        .opacity(isEnabled || keepsDisabledSurfaceVisible || floatsOverContent ? 1 : 0.45)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background<S: InsettableShape>(in shape: S) -> some View {
        JotleyFloatingGlassSurface(
            shape: shape,
            usesTranslucentMaterial: usesTranslucentMaterial
        )
    }
}

/// Draw Auto's soft backdrop from the outline alone. Menus and buttons
/// composite their labels differently, so neither the label nor the material
/// should be used as the source of the shadow.
struct JotleyFloatingGlassSurface<Outline: InsettableShape>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Outline
    var usesTranslucentMaterial = false

    var body: some View {
        let dark = colorScheme == .dark
        let surface = Color(white: dark ? 0.18 : 0.96)
        ZStack {
            if reduceTransparency {
                shape.fill(surface)
            } else if usesTranslucentMaterial {
                Color.clear.glassEffect(.regular.interactive(), in: shape)
            } else {
                Color.clear.glassEffect(.clear, in: shape)
                    .overlay { shape.fill(surface.opacity(0.85)) }
            }
        }
        .overlay { shape.strokeBorder(.white.opacity(dark ? 0.16 : 0.70), lineWidth: 1) }
        .background {
            ZStack {
                shape.fill(.black)
                    .shadow(color: .black.opacity(dark ? 0.28 : 0.14), radius: 4, y: 2)
                shape.fill(.black).blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Menus render their own surface so native menu styles can't replace it.
struct JotleyGlassMenuLabel<Outline: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @ObservedObject private var theme = ThemeManager.shared
    let shape: Outline

    func body(content: Content) -> some View {
        let color = theme.currentThemeColor
        let ink = color.color(in: colorScheme)
        content
            .foregroundStyle(ink.opacity(isEnabled ? 1 : 0.55))
            .background { JotleyFloatingGlassSurface(shape: shape) }
    }
}

#if os(iOS)
struct JotleyFloatingMenuIcon: View {
    let systemImage: String
    var verticalIconOffset: CGFloat = 0

    var body: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .fontWeight(.semibold)
            .offset(y: verticalIconOffset)
            .frame(width: 32, height: 32)
            .modifier(JotleyGlassMenuLabel(shape: Circle()))
            // Reserve space inside the native toolbar for the shadow and touch target.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
#endif

struct JotleyAboutLogo: View {
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("jotley-brand-mark")
            .renderingMode(.original)
            .resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.16), radius: 2, y: 1)
            .accessibilityLabel("Jotley")
    }
}

/// The in-app credit: "A Project ATOM project" with the atom lockup, linking to projectatom.ai.
struct AtomProductPill: View {
    var body: some View {
        Link(destination: URL(string: "https://projectatom.ai/")!) {
            HStack(spacing: 8) {
                Image("AtomCredit")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 20)
                    .accessibilityHidden(true)
                Text("A Project ATOM project")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .accessibilityHidden(true)
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(minHeight: 44)
            .foregroundStyle(.white)
            .background(.black, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.14)) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Visit projectatom.ai")
        .accessibilityIdentifier("settingsAtomProduct")
    }
}

struct JotleyLibraryWelcome: View {
    var hasNotes = false
    var canStart = true
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if hasNotes {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.themeTextSecondary)
                    .accessibilityHidden(true)
            } else {
                JotleyAboutLogo()
                    .accessibilityHidden(true)
            }
            VStack(spacing: 10) {
                Text(hasNotes ? LocalizedStringKey("Select a note") : LocalizedStringKey("Your words. Your device."))
                    .font(.custom("Comfortaa-Bold", size: 27, relativeTo: .title))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("libraryWelcomeHeading")
                Text(hasNotes
                     ? LocalizedStringKey("Choose a note to read or edit the transcript, see the summary, or ask a question.")
                     : LocalizedStringKey("Capture thoughts and meetings. Edit transcripts and get key points with Apple Intelligence on your device."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            Button(action: onStart) {
                Label("Start Transcription", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true))
            .disabled(!canStart)
            .accessibilityIdentifier("libraryWelcomeStartButton")
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

struct NoteFindReplace: View {
    private enum Field { case find, replacement }
    private enum Target {
        case transcript(Binding<TranscriptEditDraft>)
        case summary(Binding<String>)
    }
    private let target: Target
    @State private var query = TranscriptFindQuery()
    @State private var replacement = ""
    @State private var replacedCount: Int?
    @State private var isExpanded = false
    @FocusState private var focus: Field?

    init(transcript: Binding<TranscriptEditDraft>) {
        target = .transcript(transcript)
    }

    init(summary: Binding<String>) {
        target = .summary(summary)
    }

    private var identifierPrefix: String {
        if case .summary = target { return "summary" }
        return "transcript"
    }

    private var matchCount: Int {
        switch target {
        case .transcript(let draft): draft.wrappedValue.matchCount(for: query)
        case .summary(let text): query.matchCount(in: text.wrappedValue)
        }
    }

    private func replaceAll() {
        switch target {
        case .transcript(let draft): draft.wrappedValue.replaceAll(query, with: replacement)
        case .summary(let text): text.wrappedValue = query.replacingMatches(in: text.wrappedValue, with: replacement)
        }
    }

    var body: some View {
        let matches = matchCount
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Label("Find and Replace", systemImage: "magnifyingglass")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifierPrefix)FindReplace")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            findField.frame(minWidth: 200)
                            replacementField.frame(minWidth: 200)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            findField
                            replacementField
                        }
                    }
                    #if os(macOS)
                    HStack(spacing: 18) { matchOptions }
                        .toggleStyle(.checkbox)
                    #else
                    VStack(alignment: .leading, spacing: 6) { matchOptions }
                    #endif
                    HStack(spacing: 12) {
                        if let replacedCount {
                            Text("Replaced \(replacedCount) \(replacedCount == 1 ? "match" : "matches").")
                        } else if case .summary = target {
                            Text("\(matches) \(matches == 1 ? "match" : "matches") in this summary")
                        } else {
                            Text("\(matches) \(matches == 1 ? "match" : "matches") in this transcript")
                        }
                        Spacer()
                        Button("Replace All") {
                            replaceAll()
                            replacedCount = matches
                            focus = nil
                        }
                        .buttonStyle(JotleyGlassButtonStyle())
                        .disabled(matches == 0)
                        .accessibilityIdentifier("\(identifierPrefix)ReplaceAllButton")
                    }
                    .font(.callout)
                    .foregroundStyle(Color.themeTextSecondary)
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.themeTextSecondary.opacity(0.22))
                .allowsHitTesting(false)
        }
        .onChange(of: query.text) { replacedCount = nil }
        .onChange(of: query.matchCase) { replacedCount = nil }
        .onChange(of: query.wholeWords) { replacedCount = nil }
        .onChange(of: replacement) { replacedCount = nil }
    }

    private var findField: some View {
        field("Find", prompt: "Text to find", text: $query.text, target: .find, id: "\(identifierPrefix)FindField")
    }

    private var replacementField: some View {
        field("Replace with", prompt: "Replacement text", text: $replacement, target: .replacement, id: "\(identifierPrefix)ReplaceField")
    }

    private func field(_ title: String, prompt: String, text: Binding<String>, target: Field, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityHidden(true)
            TextField(title, text: text, prompt: Text(prompt))
                .font(.body)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focus, equals: target)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .modifier(JotleyEditorField(isFocused: focus == target))
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focus = target })
                .accessibilityIdentifier(id)
        }
    }

    @ViewBuilder private var matchOptions: some View {
        Toggle("Whole words", isOn: $query.wholeWords)
        Toggle("Match case", isOn: $query.matchCase)
    }
}

struct CustomSpeechWordsButton: View {
    @AppStorage(CustomSpeechWords.defaultsKey) private var savedWords = ""
    @State private var showingEditor = false

    var body: some View {
        Button { showingEditor = true } label: {
            Label("Custom Words", systemImage: "character.book.closed")
        }
        .accessibilityIdentifier("settingsCustomWordsButton")
        .sheet(isPresented: $showingEditor) {
            CustomSpeechWordsEditor(words: $savedWords)
                .preferredColorScheme(ThemeManager.shared.effectiveColorScheme)
        }
    }
}

private struct CustomSpeechWordsEditor: View {
    @Binding var words: String
    @State private var draft: String
    @State private var original: String
    @State private var showingConflict = false
    @State private var showingImport = false
    @State private var importStatus: String?
    @Environment(\.dismiss) private var dismiss

    init(words: Binding<String>) {
        _words = words
        _draft = State(initialValue: words.wrappedValue)
        _original = State(initialValue: words.wrappedValue)
    }

    var body: some View {
        let entries = CustomSpeechWords.entries(in: draft)
        let hasLongEntry = entries.contains { $0.count > CustomSpeechWords.entryLengthLimit }
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Words").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("Add names, brands, and short phrases you say often, one per line. For example, add Jason if it keeps coming out as JSON.")
                .font(.callout)
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 160)
                .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Custom words, one per line")
                .accessibilityIdentifier("customWordsEditor")
            HStack {
                Button { showingImport = true } label: {
                    Label("Import Word List", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(JotleyGlassButtonStyle())
                .accessibilityIdentifier("customWordsImportButton")
                Spacer()
                Text("\(entries.count) of \(CustomSpeechWords.limit) entries")
                    .font(.caption)
                    .foregroundStyle(entries.count > CustomSpeechWords.limit ? .red : Color.themeTextSecondary)
            }
            if let importStatus { Text(importStatus).font(.caption).foregroundStyle(Color.themeTextSecondary) }
            if hasLongEntry {
                Text("Keep each entry to \(CustomSpeechWords.entryLengthLimit) characters or fewer.")
                    .font(.caption).foregroundStyle(.red)
            }
            Text("Saved on this device. Custom words guide new transcriptions and don’t change existing notes.")
                .font(.caption).foregroundStyle(Color.themeTextSecondary)
            HStack {
                Button("Cancel") { dismiss() }
                    .jotleyDismissButtonStyle()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("customWordsCancelButton")
                Spacer()
                Button("Save") {
                    guard words == original else { showingConflict = true; return }
                    words = entries.joined(separator: "\n")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.count > CustomSpeechWords.limit || hasLongEntry)
                .accessibilityIdentifier("customWordsSaveButton")
            }.buttonStyle(JotleyGlassButtonStyle())
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 490, height: 460)
        #endif
        .background(Color.themeBackground)
        .interactiveDismissDisabled(draft != original)
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText]) { result in
            do { try importWords(from: result.get()) }
            catch { importStatus = "Couldn’t import the list. \(error.localizedDescription)" }
        }
        .alert("Custom Words changed", isPresented: $showingConflict) {
            Button("Reload List") { original = words; draft = words }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Another edit was saved while this editor was open. Reload the list before saving your changes.")
        }
    }

    private func importWords(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let sizeLimit = 64 * 1024
        let data = try file.read(upToCount: sizeLimit + 1) ?? Data()
        guard data.count <= sizeLimit else { throw LocalError.message("Choose a word list smaller than 64 KB.") }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw LocalError.message("Save the list as UTF-8 text, CSV, or TSV and try again.")
        }
        let imported = try CustomSpeechWords.importedEntries(in: text, fileExtension: url.pathExtension)
        guard !imported.isEmpty else { throw LocalError.message("The file has no words or phrases.") }
        let current = CustomSpeechWords.entries(in: draft)
        let merged = CustomSpeechWords.entries(in: (current + imported).joined(separator: "\n"))
        draft = merged.joined(separator: "\n")
        let added = merged.count - current.count
        importStatus = added == 0 ? "Those words are already on the list." : "Added \(added) \(added == 1 ? "entry" : "entries"). Review the list, then tap Save."
    }
}

/// In-app confirmation keeps chat controls consistent without changing what
/// clearing removes. Escape preserves the conversation.
struct JotleyClearChatConfirmation: View {
    let onCancel: () -> Void
    let onClear: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.12).contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "trash")
                    .font(.system(size: 22, weight: .medium)).foregroundStyle(Color.themePrimaryAccent)
                    .frame(width: 44, height: 44).glassEffect(.clear, in: Circle())
                    .accessibilityHidden(true)
                Text("Clear chat history?")
                    .font(.system(size: 21, weight: .semibold)).foregroundStyle(Color.themeTextPrimary)
                Text("This clears only this conversation. Your note, transcript and summary stay saved.")
                    .font(.system(size: 14)).foregroundStyle(Color.themeTextSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                HStack(spacing: 12) {
                    Button(action: onCancel) { Text("Cancel").frame(maxWidth: .infinity) }
                        .jotleyDismissButtonStyle(expandsHorizontally: true)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("askAIClearCancelButton")
                    Button(role: .destructive, action: onClear) { Text("Clear Chat").frame(maxWidth: .infinity) }
                        .accessibilityIdentifier("askAIClearConfirmButton")
                }
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(JotleyGlassButtonStyle())
                .padding(.top, 4)
            }
            .padding(24).frame(maxWidth: 350)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("askAIClearConfirmation")
        }
    }
}

// Local, device-only milestones. Failed, canceled and empty results never count.
@MainActor final class JotleyEngagement: ObservableObject {
    static let shared = JotleyEngagement()
    static let countKey = "jotleyCompletedLocalSummaries"
    static let reviewKey = "jotleyNativeReviewRequested"
    static let clicksKey = "jotleySupportClickedActions.v1"
    static let presentedAtKey = "jotleySupportReminderPresentedAt.v2"
    /// Set by the card's "Don't show again" button. The card never opens on its own again.
    static let dontShowAgainKey = "jotleySupportReminderDontShowAgain.v1"
    // Retired keys from earlier reminder rules; cleared on launch.
    static let legacyOptedOutKey = "jotleySupportRemindersOptedOut.v2"
    static let legacyStoppedKey = "jotleySupportAutomaticRemindersStopped.v1"
    static let legacyPresentedCountKey = "jotleySupportPresentedSummaryCount.v1"
    static let website = URL(string: "https://jotley.ai")!
    static let atomAppsURL = URL(string: "https://projectatom.ai/apps")!
    static let feedbackURL = URL(string: "https://projectatom.ai/apps?app=jotley#feedback")!
    enum Action: String, CaseIterable { case review, share, feedback, support, apps }
    /// Every one of these needs a checkmark before the weekly reminder stops.
    static let reminderActions: [Action] = [.feedback, .share, .support, .apps]
    enum Prompt { case review, support }
    @Published private(set) var completedActions: Int
    @Published private(set) var clickedActions: Set<Action>
    @Published private(set) var processingCount = 0
    let usesCustomReminders: Bool
    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, usesCustomReminders: Bool? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        #if os(macOS) && !STORE_BUILD
        self.usesCustomReminders = usesCustomReminders ?? true
        #else
        self.usesCustomReminders = usesCustomReminders ?? false
        #endif
        defaults.removeObject(forKey: Self.legacyOptedOutKey)
        defaults.removeObject(forKey: Self.legacyStoppedKey)
        defaults.removeObject(forKey: Self.legacyPresentedCountKey)
        completedActions = max(0, defaults.integer(forKey: Self.countKey))
        clickedActions = Set((defaults.stringArray(forKey: Self.clicksKey) ?? []).compactMap(Action.init(rawValue:)))
    }
    func completedSummary(result: String) {
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        completedActions = min(max(completedActions, defaults.integer(forKey: Self.countKey)), 1_000_000_000) + 1
        defaults.set(completedActions, forKey: Self.countKey)
    }
    func beginProcessing() { processingCount += 1 }
    func endProcessing() { processingCount = max(0, processingCount - 1) }
    private var storedClicks: Set<String> { Set(defaults.stringArray(forKey: Self.clicksKey) ?? []) }
    func hasClicked(_ action: Action) -> Bool { storedClicks.contains(action.rawValue) }
    var allReminderActionsClicked: Bool { JotleySupportReminderRules.allClicked(storedClicks) }
    /// Returns true when this click checks the last of the four reminder actions.
    @discardableResult func recordClick(_ action: Action) -> Bool {
        var actions = storedClicks
        actions.insert(action.rawValue)
        defaults.set(actions.sorted(), forKey: Self.clicksKey)
        clickedActions = Set(actions.compactMap(Action.init(rawValue:)))
        return JotleySupportReminderRules.allClicked(actions)
    }
    /// Clears the checkmarks, so the weekly reminder returns until all four are checked again.
    func resetClickedActions() {
        defaults.removeObject(forKey: Self.clicksKey)
        clickedActions = []
    }
    private var lastPresented: Date? {
        let seconds = defaults.double(forKey: Self.presentedAtKey)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }
    var supportReminderDismissedForever: Bool { defaults.bool(forKey: Self.dontShowAgainKey) }
    /// "Don't show again": the support card stops opening on its own. Settings still opens it.
    func dontShowSupportReminderAgain() {
        defaults.set(true, forKey: Self.dontShowAgainKey)
        objectWillChange.send()
    }
    var hasPendingSupportReminder: Bool {
        usesCustomReminders && JotleySupportReminderRules.isDue(
            completed: completedActions, clicked: storedClicks, lastPresented: lastPresented, now: now(),
            dontShowAgain: supportReminderDismissedForever)
    }
    // Claim before presentation so multiple windows cannot prompt twice.
    func claimPrompt(isIdle: Bool, isProductionAppStore: Bool = false) -> Prompt? {
        guard isIdle, processingCount == 0 else { return nil }
        if usesCustomReminders {
            guard hasPendingSupportReminder else { return nil }
            defaults.set(now().timeIntervalSince1970, forKey: Self.presentedAtKey)
            return .support
        }
        guard JotleySupportReminderRules.allowsNativeReview(
            completed: completedActions, alreadyRequested: defaults.bool(forKey: Self.reviewKey),
            clickedReview: hasClicked(.review), isProductionAppStore: isProductionAppStore) else { return nil }
        defaults.set(true, forKey: Self.reviewKey)
        return .review
    }
}

enum JotleyReviewEnvironment {
    /// Only a verified App Store install may show the native rating sheet.
    static func isProductionAppStore() async -> Bool {
        guard case .verified(let transaction) = try? await AppTransaction.shared else { return false }
        return transaction.environment == .production
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
            let production = engagement.usesCustomReminders ? false : await JotleyReviewEnvironment.isProductionAppStore()
            guard !Task.isCancelled, isIdle, scenePhase == .active, canPresent else { return }
            switch engagement.claimPrompt(isIdle: isIdle, isProductionAppStore: production) {
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
                .frame(width: 600, height: 696)
                .background(Color.themeBackground)
        }
        #endif
    }
    func body(content: Content) -> some View {
        presentedContent(content)
            .animation(.easeOut(duration: 0.18), value: isPresented)
            #if DEBUG
            // Screenshot hook: open the support card on launch.
            .onAppear {
                if ProcessInfo.processInfo.environment["JOTLEY_SHOW_SUPPORT_CARD"] == "1" { isPresented = true }
            }
            #endif
    }
}

// Free ways to help: feedback, sharing, app help and more free apps.
struct JotleySupportView: View {
    @ObservedObject var engagement = JotleyEngagement.shared
    var isAutomatic = false
    let dismiss: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @State private var contentHeight: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @State private var shareAnchor = NSView()
    @State private var didReset = false
    #endif
    var body: some View {
        supportCard
            .environment(\.colorScheme, theme.effectiveColorScheme ?? colorScheme)
    }
    @ViewBuilder private var supportCard: some View {
        #if os(macOS)
        macCard
        #else
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                JotleyAboutLogo(size: 44)
                Text("Free software.\nSupported by people.")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.themeTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("jotleySupportTitle")
                    .accessibilityAddTraits(.isHeader)
                if !isAutomatic { closeButton(diameter: 44) }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 8) {
                        Button { visit(.feedback, url: JotleyEngagement.feedbackURL) } label: {
                            actionLabel("Send Feedback", subtitle: "Help shape what comes next", icon: "bubble.left.and.bubble.right", kind: .feedback)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportFeedback")
                        ShareLink(item: JotleyEngagement.website) {
                            actionLabel("Share Jotley", subtitle: "Help others discover Jotley", icon: "square.and.arrow.up", kind: .share)
                        }
                        .simultaneousGesture(TapGesture().onEnded { engagement.recordClick(.share) })
                        .buttonStyle(.plain).accessibilityIdentifier("jotleySupportShare")
                        Button { visit(.support, url: JotleySupportURLs.community) } label: {
                            actionLabel("Community Coming Soon", subtitle: "Check back at projectatom.ai", icon: "person.2", kind: .support)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportHelp")
                        Button { visit(.apps, url: JotleyEngagement.atomAppsURL) } label: {
                            actionLabel("More Free Apps from Project ATOM", subtitle: "Explore more free apps from our studio", icon: "square.grid.2x2", kind: .apps)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportApps")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(maxHeight: contentHeight)
            .scrollBounceBehavior(.basedOnSize)
            Rectangle().fill(Color.themeAccent.opacity(0.65)).frame(height: 1).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 8) {
                supportFooter.frame(maxWidth: .infinity, alignment: .leading)
                if isAutomatic { automaticDismissButtons } else { dismissButton(expandsHorizontally: true) }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
        }
        .multilineTextAlignment(.leading)
        .background(Color.themeContentBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.themeAccent.opacity(0.6), lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jotleyStyledSupportPrompt")
        #endif
    }
    #if os(macOS)
    private var macCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                JotleyAboutLogo()
                VStack(alignment: .leading, spacing: 7) {
                    Text(isAutomatic ? "YOUR SUMMARY, SAVED" : "RATINGS & SUPPORT")
                        .font(.system(size: 12, weight: .bold)).tracking(1.4)
                        .foregroundStyle(Color.themeTextSecondary)
                    Text("Free software.\nSupported by people.")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.themeTextPrimary)
                }
                Spacer(minLength: 0)
                if !isAutomatic { closeButton(diameter: 36) }
            }.padding(.bottom, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Button { visit(.feedback, url: JotleyEngagement.feedbackURL) } label: {
                            macAction("Send Feedback", detail: "Help shape what comes next",
                                      icon: "bubble.left.and.bubble.right", kind: .feedback)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportFeedback")
                        Button {
                            engagement.recordClick(.share); didReset = false
                            JotleySupportSharing.shared.present(from: shareAnchor, dismiss: dismiss)
                        } label: {
                            macAction("Share Jotley", detail: "Help others discover private voice notes",
                                      icon: "square.and.arrow.up", kind: .share)
                        }.buttonStyle(.plain).background(JotleySupportShareAnchor(view: shareAnchor))
                            .accessibilityIdentifier("jotleySupportShare")
                        Button { visit(.support, url: JotleySupportURLs.community) } label: {
                            macAction("Community Coming Soon", detail: "Check back at projectatom.ai",
                                      icon: "person.2", kind: .support)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportHelp")
                        Button { visit(.apps, url: JotleyEngagement.atomAppsURL) } label: {
                            macAction("More Free Apps from Project ATOM", detail: "Explore more free apps from our studio",
                                      icon: "square.grid.2x2", kind: .apps)
                        }.buttonStyle(.plain).accessibilityIdentifier("jotleySupportApps")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reminderStatus)
                            .font(.system(size: 12)).foregroundStyle(Color.themeTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("jotleySupportReminderStatus")
                        Button("Reset saved clicks") {
                            engagement.resetClickedActions(); didReset = true
                        }.buttonStyle(.plain).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.themeTextPrimary)
                            .padding(.vertical, 6).accessibilityIdentifier("jotleySupportReset")
                    }
                }.padding(.trailing, 2)
            }.scrollBounceBehavior(.basedOnSize)
            Text("Every Jotley feature is free. Sharing and feedback help it grow.")
                .font(.system(size: 12)).foregroundStyle(Color.themeTextSecondary)
                .padding(.top, 18)
            if isAutomatic {
                automaticDismissButtons.padding(.top, 14)
            } else {
                HStack(spacing: 18) {
                    Spacer(minLength: 0)
                    dismissButton()
                }.padding(.top, 12)
            }
        }.padding(30)
            .background(Color.themeContentBackground)
            .accessibilityElement(children: .contain).accessibilityIdentifier("jotleyStyledSupportPrompt")
    }
    private var reminderStatus: String {
        let marks = "Checkmarks show which buttons you’ve opened."
        if didReset { return "Saved clicks reset. " + marks }
        guard engagement.usesCustomReminders else { return marks }
        if engagement.allReminderActionsClicked { return "All four are checked. Thank you! Reminders are done." }
        return marks + " Later brings this card back in a week. Don’t show again stops it."
    }
    private func visit(_ action: JotleyEngagement.Action, url: URL) {
        let finished = engagement.recordClick(action); didReset = false
        openURL(url)
        if finished && isAutomatic { dismiss() }
    }
    private func macAction(_ title: LocalizedStringKey, detail: LocalizedStringKey, icon: String,
                           kind: JotleyEngagement.Action? = nil) -> some View {
        let clicked = kind.map { engagement.hasClicked($0) } ?? false
        return HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 23))
                .foregroundStyle(Color.themePrimaryAccent).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13))
                    .foregroundStyle(Color.themeTextSecondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: clicked ? "checkmark.circle.fill" : "arrow.up.right")
                .font(.system(size: 15)).foregroundStyle(Color.themePrimaryAccent)
                .accessibilityHidden(true)
        }.foregroundStyle(Color.themeTextPrimary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
            .overlay { supportActionOutline }
            .accessibilityValue(clicked ? Text("Previously clicked") : Text(""))
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
        Text("Every Jotley feature is free. Sharing and feedback help it grow.")
            .font(cardFont(.caption, macSize: 14)).foregroundColor(.themeTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func closeButton(diameter: CGFloat) -> some View {
        #if os(macOS)
        let usesTranslucentMaterial = true
        #else
        let usesTranslucentMaterial = false
        #endif
        return Button(action: dismiss) {
            Image(systemName: "xmark").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(JotleyGlassButtonStyle(circular: true, diameter: diameter,
                                           usesTranslucentMaterial: usesTranslucentMaterial))
        .accessibilityLabel("Close support message")
        .accessibilityIdentifier("jotleySupportClose")
    }
    /// An automatic card offers exactly two ways out: a quiet "Don't show again" on the far
    /// leading edge, which stops it for good, and the prominent "Later" pill on the trailing
    /// edge, which brings the card back after a week.
    private var automaticDismissButtons: some View {
        HStack(spacing: 16) {
            Button {
                engagement.dontShowSupportReminderAgain()
                dismiss()
            } label: {
                Text("Don’t show again")
                    .font(cardFont(.subheadline, macSize: 13, weight: .medium))
                    .foregroundStyle(Color.themeTextSecondary)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jotleySupportDontShowAgain")
            Spacer(minLength: 24)
            Button(action: dismiss) {
                Text("Later")
                    .font(cardFont(.body.weight(.semibold), macSize: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .frame(minHeight: 44)
                    .background(Color.themePrimaryAccent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("jotleySupportLater")
        }
        .frame(maxWidth: .infinity)
    }
    private func dismissButton(expandsHorizontally: Bool = false) -> some View {
        let button = Button(action: dismiss) {
            Text(isAutomatic ? "Back to Notes" : "Back to Settings")
                .frame(maxWidth: expandsHorizontally ? .infinity : nil)
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("jotleySupportDismiss")
        #if os(macOS)
        return button
            .font(.subheadline.weight(.semibold))
            .buttonStyle(JotleyGlassButtonStyle(floatsOverContent: true, usesTranslucentMaterial: true))
            .fixedSize(horizontal: true, vertical: false)
        #else
        return button
        .jotleyDismissButtonStyle(expandsHorizontally: expandsHorizontally)
        .overlay {
            Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
    }
    #if os(iOS)
    private func visit(_ action: JotleyEngagement.Action, url: URL) {
        engagement.recordClick(action)
        openURL(url)
    }
    #endif
    private func actionLabel(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String,
                             kind: JotleyEngagement.Action) -> some View {
        let clicked = engagement.hasClicked(kind)
        return HStack(spacing: 14) {
            Image(systemName: icon).font(cardFont(.title3, macSize: 22))
                .foregroundStyle(Color.themePrimaryAccent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(cardFont(.body.weight(.semibold), macSize: 17, weight: .semibold)).foregroundStyle(Color.themeTextPrimary)
                Text(subtitle).font(cardFont(.caption, macSize: 14)).foregroundStyle(Color.themeTextSecondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: clicked ? "checkmark.circle.fill" : "arrow.up.right")
                .font(cardFont(.caption, macSize: 14))
                .foregroundStyle(clicked ? Color.themePrimaryAccent : Color.themeTextSecondary)
                .accessibilityHidden(true)
        }
        .accessibilityValue(clicked ? Text("Previously clicked") : Text(""))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 52)
        .contentShape(Rectangle())
        .overlay { supportActionOutline }
    }
    private var supportActionOutline: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(theme.currentThemeColor.color(in: colorScheme), lineWidth: 1)
            .allowsHitTesting(false)
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

enum JotleySupportURLs {
    static let help = URL(string: "https://projectatom.ai/apps?app=jotley#feedback")!
    static let community = URL(string: "https://projectatom.ai/")!
}

struct JotleyAppHelpLink: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button {
            JotleyEngagement.shared.recordClick(.support)
            openURL(JotleySupportURLs.help)
        } label: {
            JotleyAccentIconLabel(title: "Send Feedback", systemImage: "bubble.left.and.bubble.right")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsAppHelp")
    }
}

struct JotleySupportLinks: View {
    @State private var showingSupport = false
    @Environment(\.openURL) private var openURL
    var body: some View {
        #if os(iOS)
        mobileRows
        #else
        VStack(alignment: .leading, spacing: 16) {
            Button { showingSupport = true } label: {
                JotleyAccentIconLabel(title: "Share or send feedback", systemImage: "heart")
            }
            .frame(minHeight: 44).accessibilityIdentifier("settingsSupportReminderCard")
            Group {
                #if os(macOS)
                Button {
                    JotleyEngagement.shared.recordClick(.review)
                    openURL(JotleyEngagement.feedbackURL)
                } label: { reviewLabel }
                #else
                Link(destination: JotleyEngagement.feedbackURL) { reviewLabel }
                #endif
            }
            .accessibilityIdentifier("settingsRateJotley")
            Button { showingSupport = true } label: {
                JotleyAccentIconLabel(title: supportTitle, systemImage: "info.circle")
            }
            .frame(minHeight: 44).accessibilityIdentifier("settingsSupportJotleyCard")
            Button {
                JotleyEngagement.shared.recordClick(.apps)
                openURL(JotleyEngagement.atomAppsURL)
            } label: {
                JotleyAccentIconLabel(title: "More Free Apps from Project ATOM", systemImage: "square.grid.2x2")
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("settingsAtomApps")
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
            Button { showingSupport = true } label: {
                supportRow("Share or send feedback", systemImage: "heart")
            }
            .accessibilityIdentifier("settingsSupportReminderCard")
            Button { visit(.review, url: JotleyEngagement.feedbackURL) } label: {
                supportRow("Share Your Experience", systemImage: "star")
            }
            .accessibilityIdentifier("settingsRateJotley")
            ShareLink(item: JotleyEngagement.website) {
                supportRow("Share Jotley", systemImage: "square.and.arrow.up")
            }
            .simultaneousGesture(TapGesture().onEnded { JotleyEngagement.shared.recordClick(.share) })
            .accessibilityIdentifier("settingsShareJotley")
            Button { visit(.feedback, url: JotleyEngagement.feedbackURL) } label: {
                supportRow("Send Feedback", systemImage: "bubble.left.and.bubble.right")
            }
            .accessibilityIdentifier("settingsFeedbackJotley")
            Button { visit(.apps, url: JotleyEngagement.atomAppsURL) } label: {
                supportRow("More Free Apps from Project ATOM", systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("settingsAtomApps")
            Button { showingSupport = true } label: {
                supportRow("More Information & Support", systemImage: "info.circle")
            }
            .accessibilityIdentifier("settingsSupportJotleyCard")
            // One presenter per Form; a Group modifier would attach to every row.
            .modifier(JotleySupportCardPresentation(isPresented: $showingSupport))
        }
        .buttonStyle(.plain)
    }
    private func supportRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
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
        JotleyAccentIconLabel(title: "Share Your Experience", systemImage: "star").frame(minHeight: 44)
    }
    private var supportTitle: LocalizedStringKey { "More Information & Support" }
}

// One local completion flag across windows; replay never changes notes or permissions.
enum JotleyOnboarding {
    static let completedKey = "jotleyWelcomeCompleted.v1"
    static var bypassForFixture: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["JOTLEY_SCREENSHOT_DATA"] != nil && environment["JOTLEY_TEST_ONBOARDING"] != "1"
        #else
        return false
        #endif
    }
}

extension EnvironmentValues {
    /// True while setup covers the window, so toolbar items behind it can step aside.
    @Entry var jotleyOnboardingActive = false
}

struct JotleyOnboardingPresentation: ViewModifier {
    @Binding var replay: Bool
    var onDismiss: () -> Void
    init(replay: Binding<Bool> = .constant(false), onDismiss: @escaping () -> Void = {}) {
        _replay = replay
        self.onDismiss = onDismiss
    }
    @AppStorage(JotleyOnboarding.completedKey) private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var showing: Bool { replay || (!completed && !JotleyOnboarding.bypassForFixture) }
    func body(content: Content) -> some View {
        ZStack {
            // Preserve the open note and navigation state while setup owns the window.
            content.opacity(showing ? 0 : 1)
                .disabled(showing).accessibilityHidden(showing)
                .environment(\.jotleyOnboardingActive, showing)
            if showing {
                JotleyOnboardingView { replay = false; onDismiss() }
                    .transition(.opacity).zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showing)
        #if os(macOS)
        .toolbarBackgroundVisibility(showing ? .hidden : .automatic, for: .windowToolbar)
        #endif
    }
}

#if os(iOS)
/// Bias the shared page block toward the screen's center without allowing
/// its tallest page to overlap the footer on shorter windows.
private struct JotleyOnboardingContentLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let contentProposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        let size = content.sizeThatFits(contentProposal)
        let spareHeight = max(0, bounds.height - size.height)
        let lowerBy = min(72, spareHeight / 2)
        content.place(at: CGPoint(x: bounds.midX, y: bounds.minY + spareHeight / 2 + lowerBy),
                      anchor: .top, proposal: contentProposal)
    }
}
#endif

struct JotleyOnboardingView: View {
    let onFinish: () -> Void
    @AppStorage(JotleyOnboarding.completedKey) private var completed = false
    @AppStorage("transcriptionLanguage") private var language = "en-US"
    @AppStorage(JotleySummaryNotifications.enabledKey) private var summaryNotificationsEnabled = JotleySummaryNotifications.enabledByDefault
    @ObservedObject private var theme = ThemeManager.shared
    @ScaledMetric(relativeTo: .largeTitle) private var regularIconSize: CGFloat = 88
    @ScaledMetric(relativeTo: .title2) private var denseIconSize: CGFloat = 68
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingLanguages = false
    @State private var step = 0
    @State private var languages: [LocalSpeech.Language] = []
    @State private var speechReady = false
    @State private var speechCanSetUp = false
    @State private var checkingSpeech = true
    @State private var summaryReason: String? = "Checking Apple Intelligence…"
    @State private var settingUpSpeech = false
    @State private var setupProgress = 0.0
    @State private var setupError: String?
    @State private var setupTask: Task<Void, Never>?
    @State private var microphoneAllowed = false
    @State private var microphoneDenied = false
    @State private var requestingMicrophone = false
    #if os(macOS)
    @AppStorage("recordSystemAudio") private var includeSystemAudio = true
    @State private var systemAudioProbe: JotleySystemAudioPermissionProbe?
    @State private var systemAudioRequested = false
    @State private var systemAudioMessage: String?
    @State private var systemAudioTimeout: Task<Void, Never>?
    #endif
    private var steps: [String] {
        #if os(macOS)
        ["Welcome", "Intelligence", "Language", "Microphone", "System audio", "Notifications", "Support"]
        #else
        ["Welcome", "Intelligence", "Language", "Microphone", "Notifications", "Support"]
        #endif
    }
    private var supportStep: Int { steps.count - 1 }
    private var notificationsStep: Int { supportStep - 1 }
    private var isSupportStep: Bool { step == supportStep }
    private var accent: Color { theme.currentThemeColor.color(in: colorScheme) }
    private var ink: Color { colorScheme == .dark ? Color(white: 0.94) : Color(red: 0.14, green: 0.11, blue: 0.19) }
    private var actionInk: Color { .primary }
    private var muted: Color { ink.opacity(colorScheme == .dark ? 0.76 : 0.68) }
    private var onboardingBackground: Color { colorScheme == .dark ? .themeDarkBackground : .themeLightBackground }
    private func title(for page: Int, twoLines: Bool = false) -> String {
        if page == notificationsStep { return "Summary notifications" }
        if twoLines && page != supportStep {
            return switch page {
            case 0: "Stay in the\nconversation."
            case 1: "Find clarity in\nevery conversation."
            case 2: "Start with\nyour language."
            case 3: "Give your words\na place."
            default: "Bring app audio along."
            }
        }
        if page == supportStep { return "Free software.\nSupported by people." }
        return switch page {
        case 0: "Stay in the conversation."
        case 1: "Find the useful parts."
        case 2: "Start with your language."
        case 3: "Give your words a place."
        default: "Bring app audio along."
        }
    }
    private func subtitle(for page: Int) -> String {
        if page == notificationsStep { return "Get a local alert when your summary is saved." }
        if page == supportStep { return "All note-taking features are free.\nNo subscription, no account." }
        return switch page {
        case 0: "Your thoughts become clear notes.\nYou get to be there for the moment."
        case 1: "Summaries, useful titles and answers.\nPowered by Apple Intelligence on your device."
        case 2: "Choose your Apple Intelligence language.\nTranscription, summaries and Ask AI stay on-device."
        case 3: "Allow microphone access for live transcription.\nYou can change this later in Settings."
        default: "Meetings, videos and the apps you listen to.\nmacOS controls access to system audio."
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 620
            let scale = onboardingScale(in: geometry.size)
            let artWidth = min(300 * scale, geometry.size.width * 0.3)
            let compact = !dynamicTypeSize.isAccessibilitySize && (geometry.size.height < 800 || (!wide && geometry.size.width < 390))
            VStack(spacing: 16) {
                header(scale: scale)
                #if os(macOS)
                pageLayout(wide: wide, dense: compact, artWidth: artWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.vertical, 12)
                #else
                JotleyOnboardingContentLayout {
                    ViewThatFits(in: .vertical) {
                        mobilePageLayout(wide: wide, dense: compact, artWidth: artWidth, scale: scale)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                        if !wide && !compact && !dynamicTypeSize.isAccessibilitySize {
                            mobilePageLayout(wide: false, dense: true, artWidth: artWidth, scale: scale)
                                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                        }
                        ScrollView {
                            mobilePageLayout(wide: wide, dense: !dynamicTypeSize.isAccessibilitySize, artWidth: artWidth, scale: scale)
                                .padding(.vertical, 8)
                        }
                        .scrollIndicators(.never).scrollBounceBehavior(.basedOnSize)
                        .accessibilityIdentifier("onboardingFallbackScroll")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                #endif
                if wide {
                    HStack(spacing: 24 * scale) {
                        Color.clear.frame(width: artWidth, height: 0)
                        footer(wide: true, scale: scale).frame(maxWidth: wideFooterWidth * scale)
                            .frame(maxWidth: 380 * scale, alignment: .leading)
                    }
                    .dynamicTypeSize(onboardingTextSize(scale: scale))
                } else {
                    footer(wide: false).frame(maxWidth: 480)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            #if os(macOS)
            .padding(.bottom, 18)
            #else
            .padding(.bottom, 12)
            #endif
            #if os(macOS)
            .frame(maxWidth: wide ? 820 : .infinity)
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                onboardingBackground.ignoresSafeArea()
            }
        }
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .bottom)
        #endif
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 36).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                let forward = layoutDirection == .rightToLeft ? value.translation.width > 0 : value.translation.width < 0
                swipePage(forward: forward)
            }
        )
        .foregroundStyle(ink)
        .preferredColorScheme(theme.effectiveColorScheme)
        .observeThemeChanges()
        .task(id: language) { await refreshModels() }
        .onAppear {
            refreshMicrophone()
            #if DEBUG
            // Screenshot checks can open a specific setup page.
            if let page = ProcessInfo.processInfo.environment["JOTLEY_ONBOARDING_STEP"].flatMap(Int.init),
               steps.indices.contains(page) { step = page }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshMicrophone(); summaryReason = intelligenceReadiness() }
        }
        .onDisappear {
            setupTask?.cancel()
            #if os(macOS)
            stopSystemAudioSetup()
            #endif
        }
    }
    // Enlarge only roomy iPad windows; phones and narrow multitasking windows
    // retain the compact layout. Never reduce the user's Dynamic Type choice.
    private func onboardingScale(in size: CGSize) -> CGFloat {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad, size.width >= 800, size.height >= 700 else { return 1 }
        return max(1, min(1.3, (size.width - 48) / 720, (size.height - 200) / 620))
        #else
        return 1
        #endif
    }
    private func onboardingTextSize(scale: CGFloat) -> DynamicTypeSize {
        guard scale > 1 else { return dynamicTypeSize }
        let minimum: DynamicTypeSize = scale >= 1.24 ? .xxLarge : .xLarge
        return max(dynamicTypeSize, minimum)
    }
    @ViewBuilder private func pageLayout(wide: Bool, dense: Bool, artWidth: CGFloat, smallArtwork: Bool = false) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 24) {
                largeIllustration(height: smallArtwork ? 240 : nil).frame(width: artWidth)
                pageContent(page: step, dense: dense).frame(maxWidth: 380, alignment: .leading)
            }
        } else {
            pageContent(page: step, dense: dense, inlineArtwork: true).frame(maxWidth: 480)
        }
    }
    #if os(iOS)
    /// Every page reserves the tallest page's size. Center this shared block,
    /// keeping its children top-aligned so headings and artwork never jump.
    private func mobilePageLayout(wide: Bool, dense: Bool, artWidth: CGFloat, scale: CGFloat) -> some View {
        HStack(alignment: .top, spacing: wide ? 24 * scale : 0) {
            if wide { largeIllustration(height: artWidth).frame(width: artWidth) }
            ZStack(alignment: .topLeading) {
                ForEach(steps.indices, id: \.self) { page in
                    if page == step {
                        pageContent(page: page, dense: dense, inlineArtwork: !wide, scale: scale, twoLineTitle: wide && UIDevice.current.userInterfaceIdiom == .pad)
                    } else {
                        pageContent(page: page, dense: dense, inlineArtwork: !wide, scale: scale, twoLineTitle: wide && UIDevice.current.userInterfaceIdiom == .pad)
                            .hidden()
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: wide ? 380 * scale : 480, alignment: .leading)
        }
        .dynamicTypeSize(onboardingTextSize(scale: scale))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardingContentBlock")
    }
    #endif

    private func header(scale: CGFloat) -> some View {
        HStack(spacing: 10) {
            Text("Jotley").font(.system(size: 23 * scale, weight: .semibold, design: .rounded))
                .accessibilityIdentifier("onboardingBrand")
            Spacer()
            Button { finish() } label: { Text("Skip setup").foregroundStyle(actionInk) }
                .font(.subheadline.weight(.medium)).buttonStyle(JotleyGlassButtonStyle(diameter: 36))
                .controlSize(.small).frame(minHeight: 36 * scale)
                .disabled(settingUpSpeech || requestingMicrophone)
                .accessibilityIdentifier("onboardingSkip")
        }
        .frame(minHeight: 44 * scale)
        .dynamicTypeSize(onboardingTextSize(scale: scale))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardingHeader")
    }
    private func pageContent(page: Int, dense: Bool, inlineArtwork: Bool = false, scale: CGFloat = 1, twoLineTitle: Bool = false) -> some View {
        let stackedArtwork = inlineArtwork && !dense
        let headingLayout = stackedArtwork
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8 * scale))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12 * scale))
        return VStack(alignment: .leading, spacing: (dense ? 10 : 22) * scale) {
            VStack(alignment: .leading, spacing: 10) {
                headingLayout {
                    if inlineArtwork {
                        let artworkSize = (stackedArtwork ? 116 : 88) * scale
                        Image(illustrationAsset(for: page)).resizable().interpolation(.high).antialiased(true).scaledToFit()
                            .frame(width: artworkSize, height: artworkSize)
                            .accessibilityHidden(true)
                    }
                    Text(LocalizedStringKey(title(for: page, twoLines: twoLineTitle))).font(.system(inlineArtwork ? .title2 : .largeTitle, design: .rounded).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: (stackedArtwork ? 58 : 88) * scale, alignment: .topLeading)
                        .accessibilityIdentifier("onboardingTitle")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onboardingHeading")
                Text(LocalizedStringKey(dense && page == 2 ? "Choose your Apple Intelligence language." : subtitle(for: page))).font(dense ? .callout : .body).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: (dense ? 48 : 64) * scale, alignment: .topLeading)
            }
            switch page {
            case let value where value == supportStep:
                Text("Enjoying Jotley? Share it with a friend or tell us what you think on projectatom.ai.")
                    .font(.callout).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    ShareLink(item: JotleyEngagement.website) {
                        Label("Share Jotley", systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold)).foregroundStyle(actionInk).frame(maxWidth: .infinity)
                    }
                    .simultaneousGesture(TapGesture().onEnded { JotleyEngagement.shared.recordClick(.share) })
                    .accessibilityIdentifier("onboardingShareJotley")
                    Button {
                        JotleyEngagement.shared.recordClick(.review)
                        openURL(JotleyEngagement.feedbackURL)
                    } label: {
                        Label("Share Your Experience", systemImage: "star")
                            .font(.body.weight(.semibold)).foregroundStyle(actionInk).frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("onboardingReviewJotley")
                }
                .buttonStyle(JotleyGlassButtonStyle())
                Text("You can find these options again in Settings.")
                    .font(.footnote).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboardingSupportSettingsHint")
            case 0:
                feature("Private by design", detail: "Speech and AI run on this device. Optional private iCloud sync is yours to control.", icon: "lock.shield", dense: dense, scale: scale)
                feature("Free note-taking. No account needed.", detail: "Every feature is free, with no subscription.", icon: "heart", dense: dense, scale: scale)
            case 1:
                status(summaryReason == nil ? "Apple Intelligence is ready" : "Apple Intelligence needs setup",
                       detail: summaryReason ?? "Your summaries and Ask AI answers are processed on this device.",
                       ready: summaryReason == nil, dense: dense, scale: scale)
                    .accessibilityIdentifier("onboardingIntelligenceStatus")
                feature("From thoughts to next steps", detail: "Pull out decisions, action items and topic tags. Ask a question when you need more.", icon: "sparkles", dense: dense, scale: scale)
                if summaryReason != nil {
                    Text("Enable Apple Intelligence in your device’s Settings and let its model finish downloading. You can continue now and return to setup later.")
                        .font(.callout).foregroundStyle(muted)
                }
            case 2:
                languageSelection(dense: dense)
                if checkingSpeech {
                    ProgressView("Checking Apple speech…").tint(accent)
                } else {
                    status(setupError != nil ? "Finish setup when you’re ready" : (speechReady ? "Ready to transcribe offline" : (speechCanSetUp ? "One-time speech setup" : "Choose another language")),
                           detail: setupError ?? (speechReady ? "The selected language’s Apple speech model is installed." :
                            (speechCanSetUp ? (dense ? "Download Apple’s speech model once to transcribe offline." : "Speech uses a separate Apple model. Setup needs internet access; transcription then works offline.") : "Choose an Apple Intelligence language supported by this device. You can also change it later in Settings.")),
                           ready: speechReady, dense: dense, scale: scale)
                        .accessibilityIdentifier(setupError == nil ? "onboardingSpeechStatus" : "onboardingSpeechError")
                }
                if settingUpSpeech {
                    ProgressView("Setting up Apple speech…", value: setupProgress).tint(accent)
                    Button("Cancel setup") { setupTask?.cancel() }
                        .jotleyDismissButtonStyle()
                        .accessibilityIdentifier("onboardingCancelSpeechSetup")
                } else if speechCanSetUp && !speechReady {
                    Button("Set Up On-Device Speech") { setUpSpeech() }
                        .buttonStyle(JotleyGlassButtonStyle()).foregroundStyle(actionInk)
                        .accessibilityIdentifier("onboardingSpeechSetup")
                }
                Text(LocalizedStringKey(dense ? "Change your language or finish setup later in Settings." : "You can change your language or finish setup in Settings at any time.")).font(.footnote).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboardingLanguageHint")
            case 3:
                status(microphoneAllowed ? "Microphone access is enabled" : (microphoneDenied ? "Microphone access is off" : "You’re in control"),
                       detail: microphoneAllowed ? "Tap + in your notes list whenever you want to start transcribing." :
                        (microphoneDenied ? "Enable Microphone for Jotley in your device’s privacy settings when you’re ready." : "Jotley listens only when you start a transcription. Browsing your notes doesn’t need microphone access."),
                       ready: microphoneAllowed, dense: dense, scale: scale)
                    .accessibilityIdentifier("onboardingMicrophoneStatus")
                #if os(iOS)
                feature("Words worth keeping", detail: "Save your transcript without saving an audio file.", icon: "text.alignleft", dense: dense, scale: scale)
                #else
                feature("Bring your meetings along", detail: "Mac can also transcribe audio from apps, without saving an audio file. macOS asks for any extra access when you use that feature.", icon: "desktopcomputer", dense: dense, scale: scale)
                #endif
            case notificationsStep:
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Notify when a summary is ready", isOn: $summaryNotificationsEnabled)
                        .toggleStyle(.switch)
                        .tint(accent)
                        .accessibilityIdentifier("onboardingSummaryNotificationsToggle")
                    Text("Local alerts contain no note text and work offline. You can change this in Settings.")
                        .font(.footnote)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(dense ? 12 : 16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            default:
                #if os(macOS)
                status("A separate macOS permission",
                       detail: "Let Jotley hear other apps. This is separate from microphone access and does not capture your screen.",
                       ready: false, dense: dense, scale: scale)
                feature(systemAudioMessage == nil ? "Nothing is saved during setup" : "macOS manages your access",
                        detail: systemAudioMessage ?? "Request access now, or keep transcription microphone-only. Your choice can be changed in Settings.", icon: "lock.shield", dense: dense, scale: scale)
                    .accessibilityIdentifier("onboardingSystemAudioStatus")
                Button("Open Audio Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }.buttonStyle(JotleyGlassButtonStyle())
                    .accessibilityIdentifier("onboardingAudioPrivacySettings")
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func languageSelection(dense: Bool) -> some View {
        Button { showingLanguages = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription Language").font(dense ? .footnote : .callout).foregroundStyle(muted)
                    Text(languages.first(where: { $0.id == language })?.name ?? "Choose a supported language").font((dense ? Font.callout : .body).weight(.semibold)).foregroundStyle(ink)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(muted)
            }.padding(dense ? 12 : 16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(settingUpSpeech || checkingSpeech)
        .accessibilityIdentifier("onboardingLanguagePicker")
        .popover(isPresented: $showingLanguages, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Transcription Language").font(.headline).foregroundStyle(ink)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(languages) { item in
                            Button { language = item.id; showingLanguages = false } label: {
                                HStack {
                                    Text(item.name).foregroundStyle(ink)
                                    Spacer()
                                    if item.id == language {
                                        Image(systemName: "checkmark").foregroundStyle(accent).accessibilityHidden(true)
                                    }
                                }
                                .font(.body).padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(item.id == language ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel(item.name)
                        }
                    }
                }
                .scrollIndicators(.never).frame(maxHeight: 310)
            }
            .padding(16).frame(width: 290)
            .background(onboardingBackground)
            .presentationCompactAdaptation(.popover)
        }
    }
    private func feature(_ title: String, detail: String, icon: String, dense: Bool, scale: CGFloat = 1) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).font(.system(size: 21 * scale, weight: .medium)).foregroundStyle(accent).frame(width: 28 * scale)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title)).font(dense ? .subheadline.weight(.semibold) : .headline)
                Text(LocalizedStringKey(detail)).font(dense ? .footnote : .callout).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
    private func status(_ title: String, detail: String, ready: Bool, dense: Bool, scale: CGFloat = 1) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "info.circle").foregroundStyle(ready ? .green : accent)
                .font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title)).font(dense ? .subheadline.weight(.semibold) : .headline)
                Text(LocalizedStringKey(detail)).font(dense ? .footnote : .callout).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
        }.padding((dense ? 12 : 16) * scale).frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
    }
    private func illustrationAsset(for page: Int) -> String {
        if page == supportStep { return "onboarding-support" }
        if page == notificationsStep { return "onboarding-intelligence" }
        return switch page {
        case 0: "onboarding-welcome"
        case 1: "onboarding-intelligence"
        case 2: "onboarding-language"
        case 3: "onboarding-microphone"
        default: "onboarding-system-audio"
        }
    }
    private func largeIllustration(height: CGFloat? = nil) -> some View {
        Image(illustrationAsset(for: step))
            .resizable().interpolation(.high).antialiased(true).scaledToFit()
            .frame(maxWidth: height ?? 300)
            .frame(height: height ?? 300)
            .accessibilityHidden(true)
    }
    private var wideFooterWidth: CGFloat {
        #if os(macOS)
        278
        #else
        314
        #endif
    }
    private var onboardingBackButton: some View {
        Button { changeStep(step - 1) } label: {
            Image(systemName: "chevron.left").font(.system(size: 14, weight: .medium)).foregroundStyle(actionInk)
        }
        .buttonStyle(JotleyGlassButtonStyle(circular: true)).frame(width: 54)
        .accessibilityLabel("Back").accessibilityIdentifier("onboardingBack")
        .disabled(settingUpSpeech || requestingMicrophone)
    }
    private func footer(wide: Bool, scale: CGFloat = 1) -> some View {
        // Wide layouts align the primary action with the copy; Back sits outside that column.
        let actionInset: CGFloat = !wide ? 66 : 0
        return VStack(spacing: 13) {
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule().fill(index == step ? accent : ink.opacity(0.13)).frame(width: index == step ? 25 : 6, height: 6)
                }
                Text("\(step + 1) of \(steps.count) · \(String(localized: String.LocalizationValue(steps[step])))").font(.caption).foregroundStyle(muted).padding(.leading, 5)
                    .frame(width: 130 * scale, alignment: .leading)
            }
            .padding(.leading, actionInset)
            .accessibilityElement(children: .ignore).accessibilityLabel("Step \(step + 1) of \(steps.count), \(steps[step])")
            .accessibilityIdentifier("onboardingProgress")
            HStack(spacing: 12) {
                if !wide {
                    onboardingBackButton.opacity(step > 0 ? 1 : 0)
                        .allowsHitTesting(step > 0).accessibilityHidden(step == 0)
                }
                Button {
                    if isSupportStep { finish() }
                    else if step == notificationsStep {
                        if !completed && summaryNotificationsEnabled {
                            JotleySummaryNotifications.shared.prepareForSummary()
                        }
                        changeStep(supportStep)
                    }
                    else if step == 3 {
                        if microphoneAllowed || microphoneDenied { advancePastMicrophone() }
                        else { allowMicrophone() }
                    } else if step == 4 {
                        #if os(macOS)
                        if systemAudioRequested { changeStep(notificationsStep) } else { requestSystemAudio() }
                        #endif
                    } else { changeStep(step + 1) }
                } label: {
                    HStack(spacing: 9) {
                        if requestingMicrophone { ProgressView().controlSize(.small).tint(actionInk) }
                        Text(LocalizedStringKey(primaryTitle))
                            .font(.body.weight(.semibold))
                    }.frame(maxWidth: .infinity).foregroundStyle(actionInk)
                }
                .buttonStyle(JotleyGlassButtonStyle()).tint(accent)
                .disabled(settingUpSpeech || requestingMicrophone)
                .accessibilityIdentifier("onboardingContinue")
            }
            .overlay(alignment: .leading) {
                if wide && step > 0 { onboardingBackButton.offset(x: -66) }
            }
            onboardingSecondaryAction.frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                .padding(.leading, actionInset)
        }
        .frame(height: 128, alignment: .top)
    }
    private var onboardingSecondaryAction: some View {
        Group {
            if step == 3 && !microphoneAllowed && !microphoneDenied {
                Button("Not now") { advancePastMicrophone() }
                    .accessibilityIdentifier("onboardingNotNow")
            } else {
                #if os(macOS)
                if step == 4 {
                    Button("Use Microphone Only") { includeSystemAudio = false; changeStep(notificationsStep) }
                        .accessibilityLabel("Use Microphone Only")
                        .accessibilityIdentifier("onboardingMicrophoneOnly")
                } else { Color.clear.allowsHitTesting(false).accessibilityHidden(true) }
                #else
                Color.clear.allowsHitTesting(false).accessibilityHidden(true)
                #endif
            }
        }
        .buttonStyle(JotleyGlassButtonStyle(diameter: 36))
        .font(.subheadline.weight(.medium)).controlSize(.small).foregroundStyle(actionInk)
    }
    private var primaryTitle: String {
        if isSupportStep { return "Open Jotley" }
        if step == 3 {
            #if os(macOS)
            return microphoneAllowed || microphoneDenied ? "Continue" : "Allow Microphone"
            #else
            return microphoneAllowed || microphoneDenied ? "Continue" : "Allow Microphone"
            #endif
        }
        #if os(macOS)
        if step == 4 { return systemAudioRequested ? "Continue" : "Request System Audio Access" }
        #endif
        return "Continue"
    }
    private func advancePastMicrophone() {
        #if os(macOS)
        changeStep(4)
        #else
        changeStep(notificationsStep)
        #endif
    }
    private func swipePage(forward: Bool) {
        guard !settingUpSpeech, !requestingMicrophone, !showingLanguages else { return }
        let next = step + (forward ? 1 : -1)
        guard steps.indices.contains(next) else { return }
        // Swiping only navigates. Permission requests and finishing setup stay explicit.
        changeStep(next)
    }
    private func changeStep(_ next: Int) {
        #if os(macOS)
        stopSystemAudioSetup()
        #endif
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = next }
    }
    private func finish() {
        #if os(macOS)
        stopSystemAudioSetup()
        #endif
        completed = true; onFinish()
    }
    #if os(macOS)
    private func requestSystemAudio() {
        let probe = JotleySystemAudioPermissionProbe()
        do {
            try probe.start()
            systemAudioProbe = probe
            includeSystemAudio = true
            systemAudioRequested = true
            systemAudioMessage = "Check the macOS prompt. If access is off, enable it in Privacy & Security. You can also continue with microphone-only transcription."
            systemAudioTimeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                systemAudioProbe?.stop(); systemAudioProbe = nil
            }
        } catch {
            probe.stop()
            systemAudioMessage = error.localizedDescription
        }
    }
    private func stopSystemAudioSetup() {
        systemAudioTimeout?.cancel(); systemAudioTimeout = nil
        systemAudioProbe?.stop(); systemAudioProbe = nil
    }
    #endif
    private func refreshMicrophone() {
        #if os(iOS)
        microphoneAllowed = AVAudioApplication.shared.recordPermission == .granted
        microphoneDenied = AVAudioApplication.shared.recordPermission == .denied
        #else
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        microphoneDenied = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .audio))
        #endif
    }
    private func allowMicrophone() {
        guard !requestingMicrophone else { return }
        requestingMicrophone = true
        Task { @MainActor in
            #if os(iOS)
            _ = await AVAudioApplication.requestRecordPermission()
            #else
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            #endif
            refreshMicrophone(); requestingMicrophone = false
        }
    }
    private func refreshModels() async {
        checkingSpeech = true
        summaryReason = intelligenceReadiness()
        let available = await LocalSpeech.languages()
        let ready = await LocalSpeech.readiness(locale: Locale(identifier: language))
        guard !Task.isCancelled else { return }
        languages = available
        // Keep the same canonical language used by Settings and live transcription.
        if let matched = LocalSpeech.selectedLanguage(locale: Locale(identifier: language), in: available)?.id, matched != language {
            language = matched
            return
        }
        speechReady = ready.status == .installed && setupError == nil
        speechCanSetUp = ready.needsSetup || setupError != nil
        checkingSpeech = false
    }
    private func setUpSpeech() {
        guard !settingUpSpeech else { return }
        settingUpSpeech = true; setupProgress = 0; setupError = nil
        setupTask = Task { @MainActor in
            defer { settingUpSpeech = false; setupTask = nil }
            do {
                try await LocalSpeech.setUp(locale: Locale(identifier: language)) { progress in
                    await MainActor.run { setupProgress = progress }
                }
            } catch is CancellationError {
                setupError = "Setup paused. You can finish it later in Settings."
            } catch {
                LocalSpeech.recordFailure(error, locale: Locale(identifier: language), details: "Onboarding speech setup")
                #if targetEnvironment(simulator)
                setupError = "Speech setup couldn’t finish in this simulator. Try on a supported iPhone or iPad, or continue setup for now."
                #else
                setupError = "Speech setup couldn’t finish. Check your connection and try again, or continue and set it up later in Settings."
                #endif
            }
            await Task { @MainActor in await refreshModels() }.value
        }
    }
    private func intelligenceReadiness() -> String? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: language)) ? nil : "Apple Intelligence does not support the selected language for summaries. You can choose another language in Settings."
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in your device’s Settings to use summaries and Ask AI."
            case .modelNotReady: return "Apple is still preparing its on-device model. Connect to Wi-Fi and check Apple Intelligence in Settings."
            case .deviceNotEligible: return "Summaries and Ask AI require a device that supports Apple Intelligence."
            @unknown default: return "Apple Intelligence is unavailable right now. Check its status in your device’s Settings."
            }
        }
    }
}
