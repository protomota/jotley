import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Sends a note to Inkspring as a post idea through Inkspring's
/// `inkspring://new-idea?title=&text=&source=` link. The menu item only
/// appears when Inkspring is installed on this device.
enum InkspringIdeaLink {
    static let scheme = "inkspring"
    static let source = "jotley"
    /// Inkspring keeps 2,000 UTF-16 units of the text; trimming here keeps the link short.
    static let maxTextLength = 2_000
    static let maxTitleLength = 140

    /// The idea text: the summary when the note has one, otherwise the transcript.
    static func ideaText(summary: String?, transcript: String?) -> String? {
        let summaryText = summary.map(plainText) ?? ""
        let body = Note.isMeaningfulSummaryText(summary) && !summaryText.isEmpty
            ? summaryText
            : (transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return truncated(body, to: maxTextLength)
    }

    static func url(title: String?, text: String) -> URL? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }
        var items = [URLQueryItem]()
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { items.append(URLQueryItem(name: "title", value: truncated(trimmedTitle, to: maxTitleLength))) }
        items.append(URLQueryItem(name: "text", value: trimmedText))
        items.append(URLQueryItem(name: "source", value: source))
        var components = URLComponents()
        components.scheme = scheme
        components.host = "new-idea"
        components.queryItems = items
        // URLComponents leaves "+" alone, and Inkspring reads "+" as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Strips the **bold** and `#` heading markers Jotley's summaries use.
    static func plainText(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"(?m)^#{1,6}[ \t]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ text: String, to limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var result = ""
        for character in text {
            if result.utf16.count + character.utf16.count > limit - 1 { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static var probeURL: URL { URL(string: "\(scheme)://new-idea")! }

    @MainActor static var isInstalled: Bool {
        #if os(macOS)
        NSWorkspace.shared.urlForApplication(toOpen: probeURL) != nil
        #else
        UIApplication.shared.canOpenURL(probeURL)
        #endif
    }

    /// Opens Inkspring with the note as a new post idea. Returns false when there is nothing to send.
    @MainActor @discardableResult
    static func send(title: String?, summary: String?, transcript: String?) -> Bool {
        guard let text = ideaText(summary: summary, transcript: transcript),
              let link = url(title: title, text: text) else { return false }
        #if os(macOS)
        NSWorkspace.shared.open(link)
        #else
        UIApplication.shared.open(link)
        #endif
        return true
    }
}
