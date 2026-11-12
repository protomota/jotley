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
    case neutral = "Neutral"

    var displayName: String {
        return self.rawValue
    }

    private static let purpleLightMode = Color(red: 0.576, green: 0.2, blue: 0.918)
    private static let purpleDarkMode = purpleLightMode.mix(with: .white, by: 0.45)

    var color: Color {
        color(in: Color.shouldUseDarkTheme() ? .dark : .light)
    }

    func color(in scheme: ColorScheme) -> Color {
        switch self {
        case .purple:
            return scheme == .dark ? Self.purpleDarkMode : Self.purpleLightMode
        case .orange:
            return scheme == .dark
                ? Color(red: 1, green: 181.0 / 255, blue: 111.0 / 255)
                : Color(red: 181.0 / 255, green: 75.0 / 255, blue: 0)
        case .magenta:
            return scheme == .dark
                ? Color(red: 236.0 / 255, green: 95.0 / 255, blue: 224.0 / 255)
                : Color(red: 163.0 / 255, green: 34.0 / 255, blue: 147.0 / 255)
        case .yellow:
            return scheme == .dark
                ? Color(red: 248.0 / 255, green: 214.0 / 255, blue: 80.0 / 255)
                : Color(red: 118.0 / 255, green: 109.0 / 255, blue: 0)
        case .lightBlue:
            return scheme == .dark
                ? Color(red: 136.0 / 255, green: 203.0 / 255, blue: 1)
                : Color(red: 0, green: 107.0 / 255, blue: 161.0 / 255)
        case .neutral:
            // Gray glass stays subtle while its icons and labels remain readable.
            return Color(white: scheme == .dark ? 0.75 : 0.38)
        }
    }

    func textOnAccent(in scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    /// Bright yellow needs a dark surface for small controls to remain readable.
    func usesDarkGlass(in scheme: ColorScheme) -> Bool {
        self == .yellow && scheme == .light
    }

    func glassForeground(in scheme: ColorScheme) -> Color {
        usesDarkGlass(in: scheme) ? Color(red: 1, green: 0.89, blue: 0.12) : color(in: scheme)
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

    static var themeSelectionBackground: Color {
        shouldUseDarkTheme() ? Color(white: 0.20) : Color(white: 0.91)
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
            // SwiftUI reports the active view's appearance. There is no single
            // main screen on a two-display iPhone, and polling scenes here also
            // stalls frequent waveform updates.
            darkThemeCacheLock.lock()
            let isDark = observedSystemIsDark
            darkThemeCacheLock.unlock()
            return isDark
            #endif
        }
    }

    private static var observedSystemIsDark = false
    static func recordSystemColorScheme(_ scheme: ColorScheme) {
        darkThemeCacheLock.lock()
        observedSystemIsDark = scheme == .dark
        cachedDarkTheme = nil
        darkThemeCacheGeneration &+= 1
        darkThemeCacheLock.unlock()
    }

    // Dynamic theme primary accent color
    static var themePrimaryAccent: Color {
        ThemeManager.shared.currentThemeColor.color
    }

    /// Contrast for labels drawn directly on a solid accent fill.
    static var themeTextOnAccent: Color {
        ThemeManager.shared.currentThemeColor.textOnAccent(in: shouldUseDarkTheme() ? .dark : .light)
    }

    /// Use the same readable accent for action labels, icons, and controls.
    static var themeActionText: Color {
        themePrimaryAccent
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
            .onChange(of: colorScheme, initial: true) { _, scheme in
                Color.recordSystemColorScheme(scheme)
                // System appearance can change without a manual preference change.
                themeManager.notifySystemAppearanceChanged()
            }
    }
}

extension View {
    func jotleyNoteSelection(_ selected: Bool, unselectedBackground: Color) -> some View {
        let outline = RoundedRectangle(cornerRadius: 8)
        return background(selected ? Color.themeSelectionBackground : unselectedBackground, in: outline)
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Color.themePrimaryAccent)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    func observeThemeChanges() -> some View {
        modifier(ThemeObserver())
    }
}

extension View {
    /// Use the same accent and glass surface for Done and Cancel across platforms.
    func jotleyDismissButtonStyle(expandsHorizontally: Bool = false, inToolbar: Bool = false) -> some View {
        font(.subheadline.weight(.semibold))
            .buttonStyle(JotleyGlassButtonStyle(diameter: inToolbar ? 32 : nil, floatsOverContent: true))
            .fixedSize(horizontal: !expandsHorizontally, vertical: false)
            .frame(minHeight: inToolbar ? 44 : nil)
    }
}

struct JotleyNoteFooterTextStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        let darkSurface = colorScheme == .dark || theme.currentThemeColor.usesDarkGlass(in: colorScheme)
        return content.foregroundStyle((darkSurface ? Color.white : Color.black).opacity(isEnabled ? 1 : 0.55))
    }
}

/// Keep action text neutral while the symbol follows the current theme.
struct JotleyAccentIconLabel: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(title).foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.currentThemeColor.color(in: colorScheme))
        }
    }
}

struct JotleyNoteTagStyle: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            // Use the saturated shade that supports white text in either appearance.
            .background(theme.currentThemeColor.color(in: .light), in: Capsule())
    }
}

#if os(iOS)
/// Match compact action text and icons to the selected accent.
struct MobileActionLabel: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(themeManager.currentThemeColor.color(in: colorScheme))
    }
}
#endif


/// Neutral editing surface with a visible boundary and an accent focus ring.
struct JotleyEditorField: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var theme = ThemeManager.shared
    var isFocused = false

    func body(content: Content) -> some View {
        let outline = RoundedRectangle(cornerRadius: 10)
        let scheme = theme.effectiveColorScheme ?? colorScheme
        let accent = theme.currentThemeColor.color(in: scheme)
        content
            .foregroundStyle(Color.themeTextPrimary)
            .tint(accent)
            .background(scheme == .dark ? Color.themeDarkContentBackground : .white, in: outline)
            .overlay {
                outline.strokeBorder(isFocused ? accent : Color.themeTextSecondary.opacity(0.34),
                                     lineWidth: isFocused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}

/// Use an app-colored outline instead of the platform's fixed focus-ring color.
struct JotleyFormInputStyle: ViewModifier {
    @FocusState private var focused: Bool
    @ObservedObject private var themeManager = ThemeManager.shared
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain)
            .foregroundStyle(Color.themeTextPrimary)
            .tint(themeManager.currentThemeColor.color)
            .accentColor(themeManager.currentThemeColor.color)
            .padding(8)
            .background(Color.themeBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? themeManager.currentThemeColor.color : Color.themeTextSecondary.opacity(0.25), lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .focused($focused)
    }
}
