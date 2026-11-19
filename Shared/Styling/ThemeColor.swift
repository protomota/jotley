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

    // Match the website's violet for each appearance.
    private static let purpleLightMode = Color(red: 124.0 / 255, green: 58.0 / 255, blue: 237.0 / 255)
    private static let purpleDarkMode = Color(red: 139.0 / 255, green: 92.0 / 255, blue: 246.0 / 255)

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
}
