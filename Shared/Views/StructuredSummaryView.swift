//
//  StructuredSummaryView.swift
//  Jotley
//
//  Renders a Markdown summary as an overview card and visual sections on
//  iPhone, iPad and Mac. The stored summary stays plain Markdown.
//

import SwiftUI

/// Cache syntax only: appearance and fonts stay reactive in the SwiftUI view.
/// Template changes must not parse the whole unchanged summary on the main thread.
@MainActor
final class ParsedNoteMarkdown: NSObject {
    struct Line: Identifiable {
        let id: Int
        let heading: Bool
        let marker: String?
        let indentation: Int
        let text: AttributedString
    }
    let lines: [Line]
    private static let cache: NSCache<NSString, ParsedNoteMarkdown> = {
        let cache = NSCache<NSString, ParsedNoteMarkdown>()
        cache.countLimit = 16
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private static let listPattern = try! NSRegularExpression(pattern: #"^([ \t]*)([-+*]|[0-9]{1,9}[.)])[ \t]+(.*)$"#)
    private init(content: String) {
        lines = LocalSummary.markdownForDisplay(content).components(separatedBy: "\n").enumerated().map { index, line in
            let heading = line.hasPrefix("#")
            var text = heading ? String(line.drop(while: { $0 == "#" || $0 == " " })) : line
            var marker: String?
            var indentation = 0
            if let match = Self.listPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let whitespace = Range(match.range(at: 1), in: line),
               let prefix = Range(match.range(at: 2), in: line),
               let body = Range(match.range(at: 3), in: line) {
                let token = String(line[prefix])
                marker = ["-", "+", "*"].contains(token) ? "•" : String(token.dropLast()) + "."
                indentation = line[whitespace].reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                text = String(line[body])
            }
            return Line(id: index, heading: heading, marker: marker, indentation: indentation,
                text: (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
        }
    }
    static func rendering(_ content: String) -> ParsedNoteMarkdown {
        let key = content as NSString
        if let saved = cache.object(forKey: key) { return saved }
        let result = ParsedNoteMarkdown(content: content)
        // Account for both the source key and the attributed-text/line storage.
        cache.setObject(result, forKey: key, cost: content.utf8.count * 8 + result.lines.count * 128)
        return result
    }
}


// MARK: - Structured Summary

/// Groups a Markdown summary into an overview and titled sections. It reads the
/// same cached lines as `MarkdownContentView`, so the stored summary, editing and
/// exports stay plain Markdown.
struct StructuredSummary {
    enum Style { case numbered, checklist, questions, risks, plain }
    struct Item: Identifiable {
        let id: Int
        let marker: String
        let indentation: Int
        let label: AttributedString?
        let body: AttributedString
        let fullText: String
    }
    struct Section: Identifiable {
        let id: Int
        let title: String?
        var paragraphs: [ParsedNoteMarkdown.Line] = []
        var items: [Item] = []
        var isEmpty: Bool { paragraphs.isEmpty && items.isEmpty }
        var style: Style { StructuredSummary.style(for: title) }
        var systemImage: String { StructuredSummary.systemImage(for: title, style: style) }
    }
    let overview: Section?
    let sections: [Section]

    private static let overviewTitles: Set<String> = ["summary", "overview", "tl;dr", "tldr", "in short", "at a glance", "executive summary",
        "résumé", "resume", "resumen", "resumo", "riassunto", "zusammenfassung", "samenvatting", "概要", "要約", "摘要", "요약"]

    init(_ parsed: ParsedNoteMarkdown) {
        var sections: [Section] = []
        var current = Section(id: -1, title: nil)
        for line in parsed.lines {
            let plain = String(line.text.characters).trimmingCharacters(in: .whitespaces)
            if line.heading || Self.isBoldHeading(line, plain: plain) {
                if !current.isEmpty || current.title != nil { sections.append(current) }
                current = Section(id: line.id, title: Self.headingTitle(plain))
            } else if let marker = line.marker {
                // A bare "-" or a "No formulas provided." filler has nothing to show.
                guard !plain.isEmpty, !Self.isPlaceholder(plain) else { continue }
                let (label, body) = Self.split(line.text)
                current.items.append(Item(id: line.id, marker: marker, indentation: line.indentation,
                    label: label, body: body, fullText: plain))
            } else if !plain.isEmpty {
                current.paragraphs.append(line)
            }
        }
        if !current.isEmpty || current.title != nil { sections.append(current) }
        sections.removeAll { $0.isEmpty }
        // The opening section is the overview when it is untitled, uses a known
        // overview title, or is a short prose lead-in before other sections.
        if let first = sections.first, first.title == nil || Self.overviewTitles.contains(first.title!.lowercased())
            || (first.items.isEmpty && sections.count > 1) {
            overview = first; self.sections = Array(sections.dropFirst())
        } else {
            overview = nil; self.sections = sections
        }
    }

    /// Earlier summaries mark sections with a standalone bold line such as
    /// "**Key Points:**" rather than a Markdown heading.
    static func isBoldHeading(_ line: ParsedNoteMarkdown.Line, plain: String) -> Bool {
        guard line.marker == nil, !plain.isEmpty, plain.count <= 60 else { return false }
        return line.text.runs.allSatisfy { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
                || String(line.text[run.range].characters).allSatisfy { $0.isWhitespace || $0 == ":" }
        }
    }

    private static let placeholderPattern = try! NSRegularExpression(
        pattern: #"^(none|n/?a|nothing|no\b.{0,40}\b(provided|mentioned|discussed|given|stated|identified|noted|specified))\.?$"#,
        options: [.caseInsensitive])

    static func isPlaceholder(_ plain: String) -> Bool {
        let text = plain.trimmingCharacters(in: .whitespaces)
        return placeholderPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func headingTitle(_ plain: String) -> String {
        var title = plain
        while title.hasSuffix(":") { title.removeLast() }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// "**Owner**: task" or "Topic: detail" becomes a short label and a body.
    /// Long prefixes are ordinary sentences, so they stay intact.
    static func split(_ text: AttributedString) -> (AttributedString?, AttributedString) {
        guard let colon = text.characters.firstIndex(of: ":") else { return (nil, text) }
        let prefix = String(text.characters[..<colon]).trimmingCharacters(in: .whitespaces)
        let afterColon = text.characters.index(after: colon)
        let rest = String(text.characters[afterColon...]).trimmingCharacters(in: .whitespaces)
        // Times ("10:30") and bare URLs ("https://") are not labels.
        guard !prefix.isEmpty, prefix.count <= 40, prefix.split(separator: " ").count <= 5,
              !prefix.allSatisfy(\.isNumber), !rest.isEmpty, !rest.hasPrefix("//") else { return (nil, text) }
        var body = AttributedString(text[afterColon...])
        while body.characters.first?.isWhitespace == true { body.removeSubrange(body.startIndex..<body.characters.index(after: body.startIndex)) }
        // "**Sam**: sends the list" reads as a sentence once the name becomes a chip.
        if let first = body.characters.first, first.isLowercase {
            let end = body.characters.index(after: body.startIndex)
            body.replaceSubrange(body.startIndex..<end, with: AttributedString(String(first).uppercased(), attributes: body[body.startIndex..<end].runs.first?.attributes ?? AttributeContainer()))
        }
        return (AttributedString(prefix), body)
    }

    static func style(for title: String?) -> Style {
        let title = (title ?? "").lowercased()
        func has(_ words: [String]) -> Bool { words.contains { title.contains($0) } }
        if has(["action", "next step", "to-do", "todo", "task", "follow-up", "follow up", "owner", "assignment"]) { return .checklist }
        if has(["question", "unresolved", "open item", "unknown"]) { return .questions }
        if has(["risk", "blocker", "concern", "issue", "challenge"]) { return .risks }
        if title.isEmpty { return .plain }
        return .numbered
    }

    static func systemImage(for title: String?, style: Style) -> String {
        let title = (title ?? "").lowercased()
        func has(_ words: [String]) -> Bool { words.contains { title.contains($0) } }
        switch style {
        case .checklist: return "checklist"
        case .questions: return "questionmark.bubble"
        case .risks: return "exclamationmark.triangle"
        case .plain: return "text.alignleft"
        case .numbered:
            if has(["decision", "agreed", "outcome"]) { return "checkmark.seal" }
            if has(["date", "deadline", "schedule", "timeline", "milestone", "check-in", "meeting"]) { return "calendar" }
            if has(["idea", "brainstorm", "theme"]) { return "lightbulb" }
            if has(["people", "participant", "attendee", "who"]) { return "person.2" }
            if has(["metric", "number", "fact", "data", "progress"]) { return "chart.bar" }
            if has(["concept", "definition", "lecture", "learn", "study", "review"]) { return "book" }
            if has(["feedback", "quote"]) { return "quote.bubble" }
            return "list.number"
        }
    }
}

struct StructuredSummaryView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let content: String

    var body: some View {
        let summary = StructuredSummary(ParsedNoteMarkdown.rendering(content))
        let accent = Color.themePrimaryAccent
        let textColor = Color.themeTextPrimary
        let secondary = Color.themeTextSecondary
        let card = Color.themeContentBackground
        return LazyVStack(alignment: .leading, spacing: 20) {
            if let overview = summary.overview {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Summary", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                    sectionBody(overview, accent: accent, textColor: textColor, secondary: secondary)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(accent.opacity(0.25), lineWidth: 1))
                .accessibilityIdentifier("structuredSummaryOverview")
            }
            ForEach(summary.sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    if let title = section.title {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                                .frame(width: 32, height: 32)
                                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .accessibilityHidden(true)
                            Text(title).font(.headline).foregroundStyle(textColor)
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength: 0)
                            if section.items.count > 1 {
                                Text("\(section.items.filter { $0.indentation == 0 }.count)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.themeTextSecondary.opacity(0.15)))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    if !section.paragraphs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.paragraphs) { line in
                                Text(line.text).font(.body).foregroundStyle(textColor).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(16).background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if !section.items.isEmpty {
                        itemsView(section, accent: accent, textColor: textColor, secondary: secondary, card: card)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ section: StructuredSummary.Section, accent: Color, textColor: Color, secondary: Color) -> some View {
        ForEach(section.paragraphs) { line in
            Text(line.text).font(.body).foregroundStyle(textColor).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(section.items) { item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.marker).foregroundStyle(accent).accessibilityHidden(true)
                itemText(item, textColor: textColor)
            }
            .padding(.leading, CGFloat(item.indentation) * 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.marker) \(item.fullText)")
            .accessibilityIdentifier("markdownListItem-\(item.id)")
        }
    }

    @ViewBuilder
    private func itemsView(_ section: StructuredSummary.Section, accent: Color, textColor: Color, secondary: Color, card: Color) -> some View {
        let groups = Self.groups(section.items)
        switch section.style {
        case .numbered:
            VStack(spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.element.first?.id) { index, group in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Circle().fill(accent))
                            .accessibilityHidden(true)
                        groupText(group, accent: accent, textColor: textColor, secondary: secondary, emphasizeLabel: true)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.first?.id) { index, group in
                    if index > 0 { Divider().padding(.leading, 44) }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: Self.rowImage(section.style))
                            .font(.system(size: 18, weight: .medium)).foregroundStyle(section.style == .risks ? Color.orange : accent)
                            .frame(width: 22).padding(.top, 1).accessibilityHidden(true)
                        groupText(group, accent: accent, textColor: textColor, secondary: secondary, emphasizeLabel: false)
                    }.padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 14)
            .background(card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func groupText(_ group: [StructuredSummary.Item], accent: Color, textColor: Color, secondary: Color, emphasizeLabel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group) { item in
                Group {
                    if item.id == group.first?.id {
                        if let label = item.label, emphasizeLabel {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label).font(.body.weight(.semibold)).foregroundStyle(textColor)
                                Text(item.body).font(.subheadline).foregroundStyle(secondary)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            // Owners and short labels read as a chip beside the task.
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.body).font(.body).foregroundStyle(textColor)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if let label = item.label {
                                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(accent)
                                        .lineLimit(1).fixedSize()
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(accent.opacity(0.14)))
                                }
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(accent).accessibilityHidden(true)
                            itemText(item, textColor: secondary)
                        }.font(.subheadline).padding(.leading, 6 + CGFloat(max(0, item.indentation - 2)) * 6)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.marker) \(item.fullText)")
                .accessibilityIdentifier("markdownListItem-\(item.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemText(_ item: StructuredSummary.Item, textColor: Color) -> some View {
        var text = AttributedString()
        if let label = item.label {
            var bold = label; bold.inlinePresentationIntent = .stronglyEmphasized
            text = bold + AttributedString(": ") + item.body
        } else { text = item.body }
        return Text(text).foregroundStyle(textColor).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A top-level item and the nested items under it share one card or row.
    static func groups(_ items: [StructuredSummary.Item]) -> [[StructuredSummary.Item]] {
        var result: [[StructuredSummary.Item]] = []
        let base = items.map(\.indentation).min() ?? 0
        for item in items {
            if item.indentation > base, !result.isEmpty { result[result.count - 1].append(item) }
            else { result.append([item]) }
        }
        return result
    }

    private static func rowImage(_ style: StructuredSummary.Style) -> String {
        switch style {
        case .checklist: return "circle"
        case .questions: return "questionmark.circle"
        case .risks: return "exclamationmark.triangle.fill"
        default: return "smallcircle.filled.circle"
        }
    }
}
