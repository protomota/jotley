import Foundation

extension String {
    /// Single-line plain-text snippet for list row previews. Bounds source length
    /// before running regex passes so long transcripts don't block the main thread,
    /// and caches results so LazyVStack row recycling is free on the second render.
    func previewSnippet(maxSourceLength: Int = 400) -> String {
        // `prefix` advances at most `maxSourceLength` Characters (O(maxSourceLength)).
        // The previous `count > maxSourceLength` guard walked the ENTIRE string on
        // every call — and this runs per visible row on every list render — which is
        // why the list-row main-thread hang (JOTLEY-MACOS-N) survived the cache.
        let bounded = String(prefix(maxSourceLength))
        return MarkdownPreviewSnippetCache.shared.snippet(for: bounded)
    }
}

private final class MarkdownPreviewSnippetCache {
    static let shared = MarkdownPreviewSnippetCache()

    private let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 500
        return c
    }()

    func snippet(for source: String) -> String {
        let key = source as NSString
        if let cached = cache.object(forKey: key) {
            return cached as String
        }
        let result = Self.stripToPlainText(source)
        cache.setObject(result as NSString, forKey: key)
        return result
    }

    private static func stripToPlainText(_ markdown: String) -> String {
        var text = LocalSummary.markdownForDisplay(markdown)
        text = text.replacingOccurrences(of: "(?m)^\\s{0,3}#{1,6}\\s*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^\\s*>\\s*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?m)^\\s*(?:[-*+]\\s+|\\d+\\.\\s+)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "(\\*\\*|__)(.*?)\\1", with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: "(\\*|_)(.*?)\\1", with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: "~~(.*?)~~", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
