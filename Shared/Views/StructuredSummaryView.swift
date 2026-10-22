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
    private init(content: String, isStreaming: Bool) {
        var sourceLines = LocalSummary.markdownForDisplay(content).components(separatedBy: "\n")
        // The model streams prefixes, not complete Markdown nodes. Don't turn a
        // trailing "-", "## Act" or "**Owner" into a temporary paragraph/card.
        // Ordinary prose and list bodies still update as each snapshot arrives.
        if isStreaming, let tail = sourceLines.last, Self.awaitingStructure(tail) {
            sourceLines[sourceLines.count - 1] = ""
        }
        lines = sourceLines.enumerated().map { index, line in
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
    static func awaitingStructure(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        if let match = listPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 3), in: line) {
            let body = line[range].trimmingCharacters(in: .whitespaces).lowercased()
            // Filler such as "No decisions are mentioned" is removed by the
            // finished parser. Hold its prefixes too, rather than building a
            // card for "No decisions are" and then collapsing it on "mentioned".
            if ["none", "nothing", "n/a", "na"].contains(where: { $0.hasPrefix(body) })
                || body == "no" || body.hasPrefix("no ") || body.hasPrefix("none") || body.hasPrefix("nothing") { return true }
        }
        return text.hasPrefix("#") || text.hasPrefix("**") || text.hasPrefix("__")
            || text.hasPrefix("```") || ["-", "+", "*"].contains(text)
            || text.range(of: #"^[0-9]{1,9}[.)]?$"#, options: .regularExpression) != nil
    }

    static func rendering(_ content: String, isStreaming: Bool = false) -> ParsedNoteMarkdown {
        let key = ((isStreaming ? "stream:" : "saved:") + content) as NSString
        if let saved = cache.object(forKey: key) { return saved }
        let result = ParsedNoteMarkdown(content: content, isStreaming: isStreaming)
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
                let (label, splitBody) = Self.split(line.text)
                let body = label == nil ? Self.sentenceCased(splitBody) : splitBody
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
        let isTime = prefix.last?.isNumber == true && rest.first?.isNumber == true
        guard !prefix.isEmpty, prefix.count <= 40, prefix.split(separator: " ").count <= 5, !isTime,
              !prefix.allSatisfy(\.isNumber), !rest.isEmpty, !rest.hasPrefix("//") else { return (nil, text) }
        var body = AttributedString(text[afterColon...])
        while body.characters.first?.isWhitespace == true { body.removeSubrange(body.startIndex..<body.characters.index(after: body.startIndex)) }
        return (AttributedString(prefix), sentenceCased(body))
    }

    /// "sends the list" or "renew the registration" reads as a sentence once it
    /// stands alone; words such as "iPad" keep their own capitalization.
    static func sentenceCased(_ text: AttributedString) -> AttributedString {
        let firstWord = String(text.characters.prefix { !$0.isWhitespace })
        guard let first = text.characters.first, first.isLowercase,
              firstWord.allSatisfy({ !$0.isUppercase }) else { return text }
        var result = text
        let end = result.characters.index(after: result.startIndex)
        let attributes = result[result.startIndex..<end].runs.first?.attributes ?? AttributeContainer()
        result.replaceSubrange(result.startIndex..<end, with: AttributedString(String(first).uppercased(), attributes: attributes))
        return result
    }

    static func style(for title: String?) -> Style {
        let title = (title ?? "").lowercased()
        func has(_ words: [String]) -> Bool { words.contains { title.contains($0) } }
        if has(["action", "next step", "to-do", "todo", "task", "follow-up", "follow up", "owner", "assignment", "remind"]) { return .checklist }
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

/// Colors for one rendering. The app follows the current theme; a shared PDF
/// always prints on white.
struct SummaryPalette {
    var accent: Color
    var text: Color
    var secondary: Color
    var card: Color

    static var current: SummaryPalette {
        // Supporting text stays close to the primary color so it remains easy to read.
        SummaryPalette(accent: .themePrimaryAccent, text: .themeTextPrimary,
                       secondary: Color.themeTextPrimary.opacity(0.78), card: .themeContentBackground)
    }
    static var print: SummaryPalette {
        SummaryPalette(accent: .themePrimaryAccent, text: .themeLightTextPrimary,
                       secondary: Color.themeLightTextPrimary.opacity(0.78), card: .themeLightContentBackground)
    }
}

extension StructuredSummary {
    enum Block: Identifiable {
        case overview(Section), section(Section)
        var id: Int { switch self { case .overview(let section), .section(let section): return section.id } }
    }
    var blocks: [Block] { (overview.map { [.overview($0)] } ?? []) + sections.map { .section($0) } }
}

/// One device-wide preference shared by every note and the Settings screen.
enum SummaryDisplayStyle: String, CaseIterable, Identifiable {
    case cards, standard
    static let preferenceKey = "jotley.summaryDisplayStyle"
    var id: String { rawValue }
    var title: String { self == .cards ? "Cards" : "Standard Text" }
}

struct SummaryDisplayStylePicker: View {
    @AppStorage(SummaryDisplayStyle.preferenceKey) private var style: SummaryDisplayStyle = .cards

    var body: some View {
        Picker("Summary Style", selection: $style) {
            ForEach(SummaryDisplayStyle.allCases) { style in
                Text(style.title).tag(style)
                    .accessibilityIdentifier("summaryDisplayStyle-\(style.rawValue)")
            }
        }
        .accessibilityIdentifier("summaryDisplayStylePicker")
    }
}

/// Readable Markdown with neutral text, headings and bullets, without cards.
/// This changes presentation only; editing, AI and exports keep the same source.
private struct StandardSummaryTextView: View {
    let markdown: ParsedNoteMarkdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(markdown.lines) { line in
                if !line.text.characters.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let marker = line.marker {
                            Text(marker).accessibilityHidden(true)
                        }
                        Text(line.text)
                            .font(line.heading ? .title3.weight(.semibold) : .body)
                            .accessibilityAddTraits(line.heading ? .isHeader : [])
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.body)
                    .foregroundStyle(Color.themeTextPrimary)
                    .lineSpacing(4)
                    .padding(.leading, CGFloat(line.indentation) * 8)
                    .padding(.top, line.heading && line.id > 0 ? 12 : 0)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(line.marker == nil ? "summaryTextLine-\(line.id)" : "markdownListItem-\(line.id)")
                } else {
                    Color.clear.frame(height: 4).accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("standardSummaryText")
    }
}

struct StructuredSummaryView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage(SummaryDisplayStyle.preferenceKey) private var style: SummaryDisplayStyle = .cards
    let content: String
    var isStreaming = false

    var body: some View {
        let markdown = ParsedNoteMarkdown.rendering(content, isStreaming: isStreaming)
        let summary = StructuredSummary(markdown)
        let palette = SummaryPalette.current
        // scrollTo(bottom) needs actual heights while text grows. Lazy estimates
        // repeatedly materialize and discard cards near the viewport's edge.
        return Group {
            if style == .standard {
                StandardSummaryTextView(markdown: markdown)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(summary.blocks) { block in StructuredSummaryBlockView(block: block, palette: palette) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .transaction { if isStreaming { $0.animation = nil } }
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
}

/// One overview card or section. Text uses Dynamic Type styles, so it follows
/// the person's text size setting.
struct StructuredSummaryBlockView: View {
    let block: StructuredSummary.Block
    let palette: SummaryPalette
    @ScaledMetric(relativeTo: .headline) private var iconBox: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var numberSize: CGFloat = 30

    var body: some View {
        switch block {
        case .overview(let overview):
            VStack(alignment: .leading, spacing: 10) {
                Label("Summary", systemImage: "sparkles")
                    .font(.headline).foregroundStyle(palette.accent)
                overviewBody(overview)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.accent.opacity(0.25), lineWidth: 1))
            .accessibilityIdentifier("structuredSummaryOverview")
        case .section(let section):
            VStack(alignment: .leading, spacing: 12) {
                if section.title != nil { titleRow(section) }
                if !section.paragraphs.isEmpty { paragraphsCard(section) }
                if !section.items.isEmpty { itemsView(section) }
            }
        }
    }

    func titleRow(_ section: StructuredSummary.Section) -> some View {
                    HStack(spacing: 12) {
                        Image(systemName: section.systemImage)
                            .font(.headline).foregroundStyle(palette.accent)
                            .frame(width: iconBox, height: iconBox)
                            .background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .accessibilityHidden(true)
                        Text(section.title ?? "").font(.title3.weight(.semibold)).foregroundStyle(palette.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        if section.items.count > 1 {
                            Text("\(section.items.filter { $0.indentation == 0 }.count)")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(palette.secondary)
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Capsule().fill(palette.text.opacity(0.08)))
                                .accessibilityHidden(true)
                        }
                    }
    }

    func paragraphsCard(_ section: StructuredSummary.Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(section.paragraphs) { line in
                Text(line.text).font(.body).foregroundStyle(palette.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(16).background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func overviewBody(_ section: StructuredSummary.Section) -> some View {
        ForEach(section.paragraphs) { line in
            Text(line.text).font(.body).foregroundStyle(palette.text).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(section.items) { item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.marker).foregroundStyle(palette.accent).accessibilityHidden(true)
                itemText(item, color: palette.text)
            }
            .font(.body)
            .padding(.leading, CGFloat(item.indentation) * 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.marker) \(item.fullText)")
            .accessibilityIdentifier("markdownListItem-\(item.id)")
        }
    }

    @ViewBuilder
    private func itemsView(_ section: StructuredSummary.Section) -> some View {
        let groups = StructuredSummaryView.groups(section.items)
        switch section.style {
        case .numbered:
            VStack(spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.element.first?.id) { index, group in
                    numberedCard(index: index, group: group)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.first?.id) { index, group in
                    if index > 0 { Divider().padding(.leading, 44) }
                    row(section, group: group)
                }
            }
            .padding(.horizontal, 14)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    func numberedCard(index: Int, group: [StructuredSummary.Item]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                .frame(width: numberSize, height: numberSize).background(Circle().fill(palette.accent))
                .accessibilityHidden(true)
            groupText(group, emphasizeLabel: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ section: StructuredSummary.Section, group: [StructuredSummary.Item]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.rowImage(section.style))
                .font(.title3).foregroundStyle(section.style == .risks ? Color.orange : palette.accent)
                .frame(width: 26).padding(.top, 1).accessibilityHidden(true)
            groupText(group, emphasizeLabel: false)
        }.padding(.vertical, 12)
    }

    /// A list row on its own card, so a PDF can break pages between rows.
    func rowCard(_ section: StructuredSummary.Section, group: [StructuredSummary.Item]) -> some View {
        row(section, group: group).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func groupText(_ group: [StructuredSummary.Item], emphasizeLabel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group) { item in
                Group {
                    if item.id == group.first?.id {
                        if let label = item.label, emphasizeLabel {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label).font(.headline).foregroundStyle(palette.text)
                                Text(item.body).font(.body).foregroundStyle(palette.secondary)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            // Owners and short labels read as a chip beside the task.
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.body).font(.body).foregroundStyle(palette.text)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if let label = item.label {
                                    Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent)
                                        .lineLimit(1).fixedSize()
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(palette.accent.opacity(0.14)))
                                }
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(palette.accent).accessibilityHidden(true)
                            itemText(item, color: palette.secondary)
                        }.font(.body).padding(.leading, 6 + CGFloat(max(0, item.indentation - 2)) * 6)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.marker) \(item.fullText)")
                .accessibilityIdentifier("markdownListItem-\(item.id)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemText(_ item: StructuredSummary.Item, color: Color) -> some View {
        var text = AttributedString()
        if let label = item.label {
            var bold = label; bold.inlinePresentationIntent = .stronglyEmphasized
            text = bold + AttributedString(": ") + item.body
        } else { text = item.body }
        return Text(text).foregroundStyle(color).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// Renders a summary as a paginated PDF that matches the in-app layout.
/// Sections are split into their heading, cards and rows, so pages fill
/// before breaking and a heading always stays with what follows it.
@MainActor enum SummaryPDF {
    private struct Piece { let view: AnyView; var keepWithNext = false; var gapAfter: CGFloat = 10 }

    static func write(title: String, date: Date?, markdown: String, to url: URL) throws {
        let page = CGSize(width: 612, height: 792), margin: CGFloat = 42, width = page.width - margin * 2
        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Jotley"] as CFDictionary) else {
            throw LocalError.message("The PDF could not be created.")
        }
        let palette = SummaryPalette.print
        let header = VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold()).foregroundStyle(palette.text)
            if let date {
                Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                    .font(.subheadline).foregroundStyle(palette.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        var pieces = [Piece(view: AnyView(header), gapAfter: 18)]
        for block in StructuredSummary(ParsedNoteMarkdown.rendering(markdown)).blocks {
            let view = StructuredSummaryBlockView(block: block, palette: palette)
            guard case .section(let section) = block else {
                pieces.append(Piece(view: AnyView(view), gapAfter: 22)); continue
            }
            if section.title != nil { pieces.append(Piece(view: AnyView(view.titleRow(section)), keepWithNext: true, gapAfter: 12)) }
            if !section.paragraphs.isEmpty { pieces.append(Piece(view: AnyView(view.paragraphsCard(section)))) }
            for (index, group) in StructuredSummaryView.groups(section.items).enumerated() {
                pieces.append(Piece(view: section.style == .numbered
                    ? AnyView(view.numberedCard(index: index, group: group))
                    : AnyView(view.rowCard(section, group: group)), gapAfter: 8))
            }
            if let last = pieces.indices.last { pieces[last].gapAfter = 22 }
        }
        let renderers = pieces.map { piece -> ImageRenderer<AnyView> in
            let renderer = ImageRenderer(content: AnyView(piece.view.frame(width: width)
                .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .small)))
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            return renderer
        }
        var heights: [CGFloat] = []
        for renderer in renderers { renderer.render { size, _ in heights.append(size.height) } }

        var y = margin, pageOpen = false
        func newPage() {
            if pageOpen { pdf.endPDFPage() }
            pdf.beginPDFPage(nil); pageOpen = true; y = margin
        }
        newPage()
        let bottom = page.height - margin
        for (index, renderer) in renderers.enumerated() {
            let height = heights[index]
            // A heading moves with the first card under it.
            let needed = pieces[index].keepWithNext && index + 1 < heights.count ? height + pieces[index].gapAfter + heights[index + 1] : height
            if y > margin, y + needed > bottom, needed <= bottom - margin { newPage() }
            renderer.render { size, draw in
                var shown: CGFloat = 0
                while true {
                    let available = bottom - y
                    pdf.saveGState()
                    pdf.clip(to: CGRect(x: margin, y: margin, width: width, height: available))
                    pdf.translateBy(x: margin, y: page.height - y - size.height + shown)
                    draw(pdf)
                    pdf.restoreGState()
                    let used = min(available, size.height - shown)
                    shown += used; y += used
                    if shown >= size.height { break }
                    newPage()
                }
            }
            y += pieces[index].gapAfter
        }
        if pageOpen { pdf.endPDFPage() }
        pdf.closePDF()
    }
}
