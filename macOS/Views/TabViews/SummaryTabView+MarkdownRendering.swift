import AppKit

extension SummaryTabView {
    func sanitizeMarkdownForRendering(_ text: String) -> String {
        var sanitized = LocalSummary.markdownForDisplay(text)
        sanitized = sanitized.replacingOccurrences(of: "=\"-1\"", with: "=\"0\"")
        sanitized = sanitized.replacingOccurrences(of: "='-1'", with: "='0'")
        sanitized = sanitized.replacingOccurrences(of: ":-1", with: ":0")
        sanitized = sanitized.replacingOccurrences(of: "=-1", with: "=0")
        sanitized = sanitized.replacingOccurrences(of: "\0", with: "")
        return sanitized
    }

    func applyInlineMarkdownStyles(to attributed: NSMutableAttributedString, baseFont: NSFont) {
        let key = NSAttributedString.Key("NSInlinePresentationIntent")
        let fullRange = NSRange(location: 0, length: attributed.length)
        let fontManager = NSFontManager.shared

        attributed.enumerateAttribute(key, in: fullRange, options: []) { value, range, _ in
            guard let value = value as? NSNumber else { return }
            let intent = value.intValue

            let isItalic = (intent & 1) != 0
            let isBold = (intent & 2) != 0
            let isCode = (intent & 4) != 0

            if isCode {
                let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                attributed.addAttribute(.font, value: codeFont, range: range)
                return
            }

            var font = baseFont
            if isBold {
                font = fontManager.convert(font, toHaveTrait: .boldFontMask)
            }
            if isItalic {
                font = fontManager.convert(font, toHaveTrait: .italicFontMask)
            }
            attributed.addAttribute(.font, value: font, range: range)
        }
    }

    func applyBlockMarkdownStyles(to attributed: NSMutableAttributedString, bodyFont: NSFont, textColor: NSColor) {
        styleHeadings(in: attributed, bodyFont: bodyFont, textColor: textColor)
        styleUnorderedLists(in: attributed, bodyFont: bodyFont)
        styleOrderedLists(in: attributed, bodyFont: bodyFont)
        styleImplicitSectionHeadings(in: attributed, bodyFont: bodyFont, textColor: textColor)
    }

    private func styleHeadings(in attributed: NSMutableAttributedString, bodyFont: NSFont, textColor: NSColor) {
        guard let headingRegex = try? NSRegularExpression(pattern: #"(?m)^(#{1,6})\h+"#) else { return }

        let nsString = attributed.string as NSString
        let matches = headingRegex.matches(
            in: attributed.string,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        ).reversed()

        for match in matches {
            let markerRange = match.range(at: 0)
            let levelRange = match.range(at: 1)
            let level = (nsString.substring(with: levelRange) as NSString).length

            attributed.replaceCharacters(in: markerRange, with: "")

            let lineRange = lineContentRange(in: attributed.string as NSString, from: markerRange.location)
            let headingFont = fontForHeadingLevel(level, bodySize: bodyFont.pointSize)
            attributed.addAttribute(.font, value: headingFont, range: lineRange)
            attributed.addAttribute(.foregroundColor, value: textColor, range: lineRange)
        }
    }

    private func styleUnorderedLists(in attributed: NSMutableAttributedString, bodyFont: NSFont) {
        guard let listRegex = try? NSRegularExpression(pattern: #"(?m)^([ \t]*)[-*+]\h+"#) else { return }

        let nsString = attributed.string as NSString
        let matches = listRegex.matches(
            in: attributed.string,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        ).reversed()

        for match in matches {
            let prefixRange = match.range(at: 1)
            let markerRange = match.range(at: 0)
            let indentPrefix = nsString.substring(with: prefixRange)
            let replacement = "\(indentPrefix)\u{2022} "

            attributed.replaceCharacters(in: markerRange, with: replacement)

            let lineRange = lineContentRange(in: attributed.string as NSString, from: markerRange.location)
            let paragraphStyle = NSMutableParagraphStyle()
            let markerWidth = markerPrefixWidth(replacement, font: bodyFont)
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = markerWidth
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.paragraphSpacing = 5
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        }
    }

    private func styleOrderedLists(in attributed: NSMutableAttributedString, bodyFont: NSFont) {
        guard let orderedRegex = try? NSRegularExpression(pattern: #"(?m)^([ \t]*)\d+\.\h+"#) else { return }

        let nsString = attributed.string as NSString
        let matches = orderedRegex.matches(
            in: attributed.string,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )

        for match in matches {
            let markerText = nsString.substring(with: match.range(at: 0))
            let lineRange = lineContentRange(in: attributed.string as NSString, from: match.range.location)
            let paragraphStyle = NSMutableParagraphStyle()
            let markerWidth = markerPrefixWidth(markerText, font: bodyFont)
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = markerWidth
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.paragraphSpacing = 5
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        }
    }

    private func markerPrefixWidth(_ marker: String, font: NSFont) -> CGFloat {
        let width = (marker as NSString).size(withAttributes: [.font: font]).width
        return max(ceil(width), 10)
    }

    private func styleImplicitSectionHeadings(in attributed: NSMutableAttributedString, bodyFont: NSFont, textColor: NSColor) {
        let nsString = attributed.string as NSString
        var location = 0

        while location < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = lineContentRange(in: nsString, from: lineRange.location)
            guard contentRange.length > 0 else {
                location = lineRange.location + lineRange.length
                continue
            }

            let lineText = nsString.substring(with: contentRange).trimmingCharacters(in: .whitespaces)
            guard isPotentialSectionHeading(lineText) else {
                location = lineRange.location + lineRange.length
                continue
            }

            if let nextNonEmptyLine = nextNonEmptyLineText(in: nsString, after: lineRange.location + lineRange.length),
               isListItemLine(nextNonEmptyLine) {
                let sectionFont = NSFont.systemFont(ofSize: bodyFont.pointSize * 1.08, weight: .semibold)
                attributed.addAttribute(.font, value: sectionFont, range: contentRange)
                attributed.addAttribute(.foregroundColor, value: textColor, range: contentRange)

                let paragraphStyle = mutableParagraphStyle(
                    in: attributed,
                    at: contentRange.location
                )
                paragraphStyle.paragraphSpacingBefore = max(paragraphStyle.paragraphSpacingBefore, 10)
                paragraphStyle.paragraphSpacing = max(paragraphStyle.paragraphSpacing, 6)
                paragraphStyle.lineSpacing = max(paragraphStyle.lineSpacing, 1.5)
                attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: contentRange)
            }

            location = lineRange.location + lineRange.length
        }
    }

    private func isPotentialSectionHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 96 else { return false }
        guard !isListItemLine(trimmed) else { return false }

        if let last = trimmed.unicodeScalars.last,
           CharacterSet(charactersIn: ".!?;").contains(last) {
            return false
        }

        return true
    }

    private func isListItemLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        return trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private func nextNonEmptyLineText(in text: NSString, after location: Int) -> String? {
        var scan = location
        while scan < text.length {
            let lineRange = text.lineRange(for: NSRange(location: scan, length: 0))
            let contentRange = lineContentRange(in: text, from: lineRange.location)
            if contentRange.length > 0 {
                let line = text.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    return line
                }
            }
            scan = lineRange.location + lineRange.length
        }
        return nil
    }

    func applyParagraphSpacing(to attributed: NSMutableAttributedString) {
        let nsString = attributed.string as NSString
        var location = 0

        while location < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = lineContentRange(in: nsString, from: lineRange.location)

            if contentRange.length > 0 {
                let paragraphStyle = mutableParagraphStyle(
                    in: attributed,
                    at: contentRange.location
                )
                paragraphStyle.paragraphSpacing = max(paragraphStyle.paragraphSpacing, 8)
                paragraphStyle.lineSpacing = max(paragraphStyle.lineSpacing, 3)
                attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: contentRange)
            }

            location = lineRange.location + lineRange.length
        }
    }

    private func mutableParagraphStyle(in attributed: NSMutableAttributedString, at location: Int) -> NSMutableParagraphStyle {
        if let existing = attributed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
           let mutable = existing.mutableCopy() as? NSMutableParagraphStyle {
            return mutable
        }
        return NSMutableParagraphStyle()
    }

    private func lineContentRange(in text: NSString, from location: Int) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }

        let clampedLocation = min(max(location, 0), max(text.length - 1, 0))
        let lineRange = text.lineRange(for: NSRange(location: clampedLocation, length: 0))

        var contentLength = lineRange.length
        while contentLength > 0 {
            let index = lineRange.location + contentLength - 1
            let scalar = text.character(at: index)
            if scalar == 10 || scalar == 13 {
                contentLength -= 1
            } else {
                break
            }
        }

        return NSRange(location: lineRange.location, length: contentLength)
    }

    private func fontForHeadingLevel(_ level: Int, bodySize: CGFloat) -> NSFont {
        switch level {
        case 1:
            return NSFont.systemFont(ofSize: bodySize * 1.5, weight: .bold)
        case 2:
            return NSFont.systemFont(ofSize: bodySize * 1.25, weight: .semibold)
        case 3:
            return NSFont.systemFont(ofSize: bodySize * 1.1, weight: .medium)
        default:
            return NSFont.systemFont(ofSize: bodySize, weight: .semibold)
        }
    }

}
