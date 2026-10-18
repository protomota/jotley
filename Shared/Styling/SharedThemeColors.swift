import Combine
import SwiftUI

// Environment key for theme refresh
struct ThemeRefreshKey: EnvironmentKey {
    static let defaultValue = UUID()
}

extension EnvironmentValues {
    var themeRefresh: UUID {
        get { self[ThemeRefreshKey.self] }
        set { self[ThemeRefreshKey.self] = newValue }
    }
}

// Theme color selection enum
enum ThemeColor: String, CaseIterable, Codable {
    case purple = "Purple"
    case orange = "Orange"
    case magenta = "Magenta"
    case yellow = "Yellow"
    case lightBlue = "Light Blue"

    var displayName: String {
        return self.rawValue
    }

    var color: Color {
        switch self {
        case .purple:
            return Color(red: 0.576, green: 0.2, blue: 0.918) // #9333EA - Current default
        case .orange:
            return Color.orange
        case .magenta:
            return Color(red: 1.0, green: 0.0, blue: 0.5) // Magenta
        case .yellow:
            return Color.yellow
        case .lightBlue:
            return Color(red: 0.3, green: 0.7, blue: 1.0) // Light blue
        }
    }

    var previewColor: Color {
        // For preview in settings, ensure visibility on dark background
        switch self {
        case .yellow:
            return self.color
        default:
            return self.color
        }
    }
}

// Appearance mode enum for light/dark/system theme selection
enum AppearanceMode: String, CaseIterable, Codable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    var displayName: String {
        return self.rawValue
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil  // nil means follow system
        }
    }
}

// Notification posted when theme changes
extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
}

// Theme manager for handling theme color and appearance mode selection
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("selectedThemeColor") private var storedThemeColor: String = ThemeColor.purple.rawValue
    @AppStorage("selectedAppearanceMode") private var storedAppearanceMode: String = AppearanceMode.system.rawValue

    @Published var currentThemeColor: ThemeColor {
        didSet {
            if storedThemeColor != currentThemeColor.rawValue {
                storedThemeColor = currentThemeColor.rawValue
            }
            Color.invalidateDarkThemeCache()
            objectWillChange.send()
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    @Published var currentAppearanceMode: AppearanceMode {
        didSet {
            if storedAppearanceMode != currentAppearanceMode.rawValue {
                storedAppearanceMode = currentAppearanceMode.rawValue
            }
            // Force all color values to be re-evaluated
            Color.invalidateDarkThemeCache()
            objectWillChange.send()
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    var effectiveColorScheme: ColorScheme? {
        currentAppearanceMode.colorScheme
    }

    private init() {
        // Initialize theme color with stored value or default
        let storedThemeColorValue = UserDefaults.standard.string(forKey: "selectedThemeColor") ?? ThemeColor.purple.rawValue
        self.currentThemeColor = ThemeColor(rawValue: storedThemeColorValue) ?? .purple

        // Initialize appearance mode with stored value or default
        let storedAppearanceModeValue = UserDefaults.standard.string(forKey: "selectedAppearanceMode") ?? AppearanceMode.system.rawValue
        self.currentAppearanceMode = AppearanceMode(rawValue: storedAppearanceModeValue) ?? .system
    }

    func setThemeColor(_ color: ThemeColor) {
        currentThemeColor = color
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        currentAppearanceMode = mode
    }

    /// Called by app delegates when system appearance changes
    func notifySystemAppearanceChanged() {
        guard currentAppearanceMode == .system else {
            print("🎨 System appearance changed but app is using manual mode (\(currentAppearanceMode.rawValue))")
            return
        }
        print("🎨 System appearance changed, notifying observers")
        Color.invalidateDarkThemeCache()
        objectWillChange.send()
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }
}

extension Color {
    // Dark theme colors (based on common dark themes like Obsidian)
    static let themeDarkBackground = Color(red: 0.12, green: 0.12, blue: 0.12) // Approx #1F1F1F
    static let themeDarkContentBackground = Color(red: 0.15, green: 0.15, blue: 0.15) // Approx #262626
    static let themeDarkTextPrimary = Color(red: 0.85, green: 0.85, blue: 0.85) // Approx #D9D9D9
    static let themeDarkTextSecondary = Color(red: 0.6, green: 0.6, blue: 0.6) // Approx #999999
    static let themeDarkAccent = Color(red: 0.4, green: 0.4, blue: 0.45) // A slightly bluish gray for accents/borders

    // Light theme colors
    static let themeLightBackground = Color(red: 0.98, green: 0.98, blue: 0.98) // Approx #FAFAFA
    static let themeLightContentBackground = Color(red: 0.96, green: 0.96, blue: 0.96) // Approx #F5F5F5
    static let themeLightTextPrimary = Color(red: 0.1, green: 0.1, blue: 0.1) // Approx #1A1A1A
    static let themeLightTextSecondary = Color(red: 0.4, green: 0.4, blue: 0.4) // Approx #666666
    static let themeLightAccent = Color(red: 0.88, green: 0.88, blue: 0.88) // Approx #E0E0E0

    // Dynamic theme colors - adapt based on selected appearance mode
    static var themeBackground: Color {
        let isDark = shouldUseDarkTheme()
        return isDark ? themeDarkBackground : themeLightBackground
    }

    static var themeContentBackground: Color {
        let isDark = shouldUseDarkTheme()
        return isDark ? themeDarkContentBackground : themeLightContentBackground
    }

    static var themeTextPrimary: Color {
        let isDark = shouldUseDarkTheme()
        return isDark ? themeDarkTextPrimary : themeLightTextPrimary
    }

    static var themeTextSecondary: Color {
        let isDark = shouldUseDarkTheme()
        return isDark ? themeDarkTextSecondary : themeLightTextSecondary
    }

    static var themeAccent: Color {
        let isDark = shouldUseDarkTheme()
        return isDark ? themeDarkAccent : themeLightAccent
    }

    // Cache for shouldUseDarkTheme()'s appearance computation. SwiftUI body
    // re-evaluations hit each theme color getter constantly (the playback
    // waveform resolves them on every 10 Hz progress tick; the live recording
    // waveform on every frame), so the resolution must never do real work in
    // steady state.
    //
    // Invalidation is EVENT-DRIVEN, not TTL-based: ThemeManager bumps the
    // generation whenever the theme/appearance changes (manual mode switches
    // and the system-appearance hooks in SceneDelegate / JotleyAppDelegate,
    // which call notifySystemAppearanceChanged on trait changes). A previous
    // version used a 1 s TTL — that recomputed mid-frame exactly once per
    // second, which is precisely the rhythm of the reported 1 Hz waveform
    // hitch. The long TTL below is only a safety net for any appearance-change
    // path that misses the delegate hooks.
    private nonisolated(unsafe) static var cachedDarkTheme: (mode: AppearanceMode, generation: UInt64, isDark: Bool, expiresAt: TimeInterval)?
    private nonisolated(unsafe) static var darkThemeCacheGeneration: UInt64 = 0
    private static let darkThemeCacheLock = NSLock()
    private static let darkThemeCacheTTL: TimeInterval = 300.0

    /// Called by ThemeManager whenever the theme color, appearance mode, or
    /// system appearance changes. The next theme color resolution recomputes.
    static func invalidateDarkThemeCache() {
        darkThemeCacheLock.lock()
        darkThemeCacheGeneration &+= 1
        darkThemeCacheLock.unlock()
    }

    // Helper function to determine if dark theme should be used
    static func shouldUseDarkTheme() -> Bool {
        let appearanceMode = ThemeManager.shared.currentAppearanceMode
        let now = ProcessInfo.processInfo.systemUptime
        darkThemeCacheLock.lock()
        let generation = darkThemeCacheGeneration
        if let cached = cachedDarkTheme,
           cached.mode == appearanceMode,
           cached.generation == generation,
           cached.expiresAt > now {
            darkThemeCacheLock.unlock()
            return cached.isDark
        }
        darkThemeCacheLock.unlock()

        let result = computeShouldUseDarkTheme(appearanceMode: appearanceMode)
        darkThemeCacheLock.lock()
        cachedDarkTheme = (appearanceMode, generation, result, now + darkThemeCacheTTL)
        darkThemeCacheLock.unlock()
        return result
    }

    private static func computeShouldUseDarkTheme(appearanceMode: AppearanceMode) -> Bool {
        switch appearanceMode {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            // Check system appearance
            #if os(macOS)
            if #available(macOS 10.14, *) {
                return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
            return true
            #else
            // iOS: read the screen-level trait. The previous implementation
            // walked UIApplication.shared.connectedScenes → UIWindowScene →
            // windows → traitCollection on every cache miss; with the 1 s TTL
            // above, that FrontBoard-backed walk ran once per second on the
            // main thread mid-frame and visibly hitched the playback waveform
            // (which resolves theme colors on every 10 Hz progress tick). No
            // window in the app overrides userInterfaceStyle, so the screen's
            // trait collection always gives the same answer as the key window.
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark
            #endif
        }
    }

    // Dynamic theme primary accent color
    static var themePrimaryAccent: Color {
        ThemeManager.shared.currentThemeColor.color
    }

    /// Text actions must remain readable against dark sheets and tinted cards.
    /// Icons and filled controls continue to use the user's accent color.
    static var themeActionText: Color {
        #if os(iOS)
        return shouldUseDarkTheme() ? themeTextPrimary : themePrimaryAccent
        #else
        return themePrimaryAccent
        #endif
    }

    // iOS specific colors that adapt to light/dark mode
}

// View modifier to ensure theme changes are observed
struct ThemeObserver: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var refreshToken = UUID()
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            // Trigger view recomputation without resetting identity so presented sheets stay mounted.
            .environment(\.themeRefresh, refreshToken)
            .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
                refreshToken = UUID()
            }
            .onChange(of: colorScheme) { _, _ in
                // System appearance can change without a manual preference change.
                themeManager.notifySystemAppearanceChanged()
            }
    }
}

extension View {
    func observeThemeChanges() -> some View {
        modifier(ThemeObserver())
    }
}

#if os(iOS)
/// The same neutral Liquid Glass dismissal control in toolbars and custom sheets.
struct MobileDoneButton: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let action: () -> Void

    var body: some View {
        doneButton.buttonStyle(.glass).buttonBorderShape(.capsule)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var doneButton: some View {
        Button("Done", action: action)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.themeTextPrimary)
            .frame(minHeight: 44)
    }
}

/// Keep accent icons separate from readable action text.
struct MobileActionLabel: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title).foregroundStyle(Color.themeActionText)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.themePrimaryAccent)
        }
    }
}
#endif
