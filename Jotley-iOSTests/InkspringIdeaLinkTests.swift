import Foundation
import Testing
@testable import Jotley_iOS

struct InkspringIdeaLinkTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func buildsNewIdeaLinkWithSource() throws {
        let url = try #require(InkspringIdeaLink.url(title: "Weekly sync", text: "Ship the beta\nThen write the post"))
        #expect(url.scheme == "inkspring")
        #expect(url.host == "new-idea")
        let values = query(url)
        #expect(values["title"] == "Weekly sync")
        #expect(values["text"] == "Ship the beta\nThen write the post")
        #expect(values["source"] == "jotley")
    }

    @Test func encodesPlusSoInkspringKeepsIt() throws {
        let url = try #require(InkspringIdeaLink.url(title: nil, text: "C++ tips"))
        #expect(url.absoluteString.contains("C%2B%2B"))
        #expect(!url.absoluteString.contains("title="))
    }

    @Test func prefersSummaryAndStripsBoldMarkers() {
        let text = InkspringIdeaLink.ideaText(summary: "**Key Points**\n- One idea", transcript: "raw words")
        #expect(text == "Key Points\n- One idea")
        #expect(InkspringIdeaLink.plainText("## Summary\nThe source outlines #1 ideas") == "Summary\nThe source outlines #1 ideas")
    }

    @Test func fallsBackToTranscriptAndNothingWhenEmpty() {
        #expect(InkspringIdeaLink.ideaText(summary: nil, transcript: "  raw words ") == "raw words")
        #expect(InkspringIdeaLink.ideaText(summary: "  ", transcript: " ") == nil)
        #expect(InkspringIdeaLink.url(title: "x", text: "   ") == nil)
    }

    @Test func shortensLongTextTo2000Units() throws {
        let text = try #require(InkspringIdeaLink.ideaText(summary: nil, transcript: String(repeating: "word ", count: 1_000)))
        #expect(text.utf16.count <= 2_000)
        #expect(text.hasSuffix("…"))
    }
}
