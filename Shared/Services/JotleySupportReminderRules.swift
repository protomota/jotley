import Foundation

/// Pure rules for the direct-download Mac support reminder and the native review prompt.
/// "Later" brings the reminder back after a week, until every action is checked.
/// "Don't show again" stops it for good.
enum JotleySupportReminderRules {
    static let milestone = 5
    static let interval: TimeInterval = 7 * 24 * 60 * 60
    /// The four card actions that each need a checkmark before the reminder stops.
    static let requiredActions: Set<String> = ["feedback", "share", "support", "apps"]

    static func allClicked(_ clicked: Set<String>) -> Bool {
        requiredActions.isSubset(of: clicked)
    }

    static func isDue(completed: Int, clicked: Set<String>,
                      lastPresented: Date?, now: Date, dontShowAgain: Bool = false) -> Bool {
        guard !dontShowAgain, completed >= milestone, !allClicked(clicked) else { return false }
        guard let lastPresented else { return true }
        return now.timeIntervalSince(lastPresented) >= interval
    }

    /// The native rating sheet rates an App Store install, so TestFlight, Xcode and
    /// direct downloads never consume it.
    static func allowsNativeReview(completed: Int, alreadyRequested: Bool, clickedReview: Bool,
                                   isProductionAppStore: Bool) -> Bool {
        isProductionAppStore && completed >= milestone && !alreadyRequested && !clickedReview
    }
}
