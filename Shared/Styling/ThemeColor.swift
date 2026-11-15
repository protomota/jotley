import SwiftUI

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
