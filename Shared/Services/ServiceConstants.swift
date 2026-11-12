import Foundation

struct TranscriptUtterance: Codable, Identifiable, Hashable {
    let id: String
    var text: String
    let start: Double?
    let end: Double?
    let speaker: Int?
    let confidence: Double?
    let isInterim: Bool

    init(
        id: String = UUID().uuidString,
        text: String,
        start: Double? = nil,
        end: Double? = nil,
        speaker: Int? = nil,
        confidence: Double? = nil,
        isInterim: Bool = false
    ) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.start = start
        self.end = end
        self.speaker = speaker
        self.confidence = confidence
        self.isInterim = isInterim
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var timestampLabel: String? {
        guard let start, start.isFinite, start >= 0, start < Double(Int.max) else { return nil }
        let seconds = Int(start)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func displayParagraphs(_ utterances: [TranscriptUtterance]) -> [TranscriptUtterance] {
        utterances.flatMap { coalescedForDisplay([$0]) }
    }

    static func fallbackUtterances(from transcript: String) -> [TranscriptUtterance] {
        let paragraphs = transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.enumerated().map { TranscriptUtterance(id: "plain-\($0.offset)", text: $0.element) }
    }

    static func deduplicated(_ utterances: [TranscriptUtterance]) -> [TranscriptUtterance] {
        var results: [TranscriptUtterance] = []
        var needsSorting = false
        var lastStartTime: Double?

        for rawUtterance in utterances {
            let utterance = TranscriptUtterance(
                id: rawUtterance.id,
                text: rawUtterance.text,
                start: rawUtterance.start,
                end: rawUtterance.end,
                speaker: rawUtterance.speaker,
                confidence: rawUtterance.confidence,
                isInterim: rawUtterance.isInterim
            )

            guard !utterance.isEmpty else { continue }

            if let last = results.last, last.isLikelyDuplicate(of: utterance) {
                continue
            }

            if let start = utterance.start {
                if let lastStartTime, start + 0.0001 < lastStartTime {
                    needsSorting = true
                }
                lastStartTime = start
            }

            results.append(utterance)
        }

        guard needsSorting else { return results }

        // Keep deterministic ordering while preferring timestamp order when available.
        return results
            .enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element
                let right = rhs.element

                switch (left.start, right.start) {
                case let (l?, r?) where abs(l - r) > 0.0001:
                    return l < r
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// Coalesces short utterances into larger timestamped chunks for easier reading.
    /// This keeps timing metadata while avoiding overly fragmented, word-level bubbles.
    static func coalescedForDisplay(
        _ utterances: [TranscriptUtterance],
        minWordsPerChunk: Int = 8,
        maxWordsPerChunk: Int = 20,
        maxDurationSeconds: Double = 12,
        maxSentencesPerChunk: Int = 2,
        pauseSeconds: Double = 2
    ) -> [TranscriptUtterance] {
        let cleaned = deduplicated(utterances)
            .filter { !$0.isInterim && !$0.isEmpty }

        var coalesced: [TranscriptUtterance] = []
        var buffer: [TranscriptUtterance] = []
        var bufferedWordCount = 0
        var bufferedSentenceCount = 0

        func flush() {
            guard let first = buffer.first else { return }
            coalesced.append(buffer.count == 1 ? first : mergeUtterancesForDisplay(buffer))
            buffer.removeAll(keepingCapacity: true)
            bufferedWordCount = 0
            bufferedSentenceCount = 0
        }

        for utterance in cleaned {
            let chunks = splitOversizedUtterance(utterance, maxWordsPerChunk: maxWordsPerChunk,
                maxSentencesPerChunk: maxSentencesPerChunk, maxDurationSeconds: maxDurationSeconds)
            // Already split paragraphs and legacy lines are standalone.
            guard chunks.count == 1, let start = utterance.start else {
                flush()
                coalesced.append(contentsOf: chunks)
                continue
            }

            let incomingWordCount = wordCount(in: utterance.text)
            let sentenceBoundary = endsSentence(utterance.text)
            if let previous = buffer.last {
                let pause = previous.end.map { start - $0 } ?? 0
                if pause >= pauseSeconds || didSpeakerChange(current: buffer, incoming: utterance)
                    || bufferedWordCount + incomingWordCount > maxWordsPerChunk {
                    flush()
                }
            }
            buffer.append(utterance)
            bufferedWordCount += incomingWordCount
            if sentenceBoundary {
                bufferedSentenceCount += 1
            }

            let duration = mergedDuration(of: buffer)

            if bufferedWordCount >= maxWordsPerChunk ||
                duration >= maxDurationSeconds ||
                (bufferedSentenceCount >= maxSentencesPerChunk && bufferedWordCount >= minWordsPerChunk) ||
                (bufferedWordCount >= minWordsPerChunk && sentenceBoundary) {
                flush()
            }
        }

        flush()

        return coalesced
    }

    private static func splitOversizedUtterance(
        _ utterance: TranscriptUtterance,
        maxWordsPerChunk: Int,
        maxSentencesPerChunk: Int,
        maxDurationSeconds: Double
    ) -> [TranscriptUtterance] {
        let paragraphs = utterance.text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let sentenceParts = paragraphs.map { sentenceUnits(from: $0) }
        let totalWords = wordCount(in: utterance.text)
        let totalSentences = sentenceParts.reduce(0) { $0 + $1.count }
        let utteranceDuration = mergedDuration(of: [utterance])

        let shouldSplit = paragraphs.count > 1 || totalWords > maxWordsPerChunk ||
            totalSentences > maxSentencesPerChunk ||
            utteranceDuration > maxDurationSeconds * 1.15

        guard shouldSplit else { return [utterance] }

        var chunkTexts: [String] = []
        var chunkWordCounts: [Int] = []
        var buffer: [String] = []
        var bufferedWords = 0
        var bufferedSentences = 0

        func flushBuffer() {
            guard !buffer.isEmpty else { return }

            let chunkText = buffer.joined(separator: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !chunkText.isEmpty else {
                buffer.removeAll(keepingCapacity: true)
                bufferedWords = 0
                bufferedSentences = 0
                return
            }

            chunkTexts.append(chunkText)
            chunkWordCounts.append(max(wordCount(in: chunkText), 1))
            buffer.removeAll(keepingCapacity: true)
            bufferedWords = 0
            bufferedSentences = 0
        }

        for paragraph in sentenceParts {
            let units = paragraph.flatMap { part in
                wordCount(in: part) <= maxWordsPerChunk ? [part] : splitByWordCount(part, maxWords: maxWordsPerChunk)
            }
            for unit in units {
                let unitWordCount = wordCount(in: unit)
                if bufferedWords + unitWordCount > maxWordsPerChunk { flushBuffer() }
                buffer.append(unit)
                bufferedWords += unitWordCount
                bufferedSentences += 1

                if bufferedWords >= maxWordsPerChunk || bufferedSentences >= maxSentencesPerChunk {
                    flushBuffer()
                }
            }
            flushBuffer()
        }

        guard chunkTexts.count > 1 else { return [utterance] }

        let timeBounds = interpolatedTimeBounds(for: utterance)

        let totalWordWeight = max(chunkWordCounts.reduce(0, +), 1)
        var currentStart = timeBounds?.start ?? 0
        var splitChunks: [TranscriptUtterance] = []
        splitChunks.reserveCapacity(chunkTexts.count)

        for index in chunkTexts.indices {
            let chunkText = chunkTexts[index]
            let chunkWeight = Double(chunkWordCounts[index]) / Double(totalWordWeight)

            let chunkStart: Double?
            let chunkEnd: Double?
            if let timeBounds {
                chunkStart = currentStart
                if index == chunkTexts.count - 1 {
                    chunkEnd = timeBounds.end
                } else {
                    let estimatedDuration = timeBounds.duration * chunkWeight
                    chunkEnd = min(timeBounds.end, currentStart + estimatedDuration)
                }
                currentStart = chunkEnd ?? currentStart
            } else {
                chunkStart = index == chunkTexts.startIndex ? utterance.start : nil
                chunkEnd = index == chunkTexts.indices.last ? utterance.end : nil
            }

            splitChunks.append(
                TranscriptUtterance(
                    id: "\(utterance.id)-\(index)",
                    text: chunkText,
                    start: chunkStart,
                    end: chunkEnd,
                    speaker: utterance.speaker,
                    confidence: utterance.confidence,
                    isInterim: false
                )
            )
        }

        return splitChunks
    }

    private static func sentenceUnits(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let segmented = normalized.replacingOccurrences(
            of: "(?<=[.!?])\\s+",
            with: "\n",
            options: .regularExpression
        )

        let units = segmented
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return units.isEmpty ? [normalized] : units
    }

    private static func splitByWordCount(_ text: String, maxWords: Int) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }

        var chunks: [String] = []
        chunks.reserveCapacity(max(1, Int(ceil(Double(words.count) / Double(max(maxWords, 1))))))

        var startIndex = 0
        while startIndex < words.count {
            let endIndex = min(startIndex + max(maxWords, 1), words.count)
            let chunk = words[startIndex..<endIndex].map(String.init).joined(separator: " ")
            chunks.append(chunk)
            startIndex = endIndex
        }

        return chunks
    }

    private static func interpolatedTimeBounds(for utterance: TranscriptUtterance) -> (start: Double, end: Double, duration: Double)? {
        if let start = utterance.start,
           let end = utterance.end,
           start.isFinite, end.isFinite, start >= 0, end > start {
            return (start: start, end: end, duration: end - start)
        }
        return nil
    }

    private func isLikelyDuplicate(of other: TranscriptUtterance) -> Bool {
        guard normalized(text) == normalized(other.text) else { return false }

        switch (start, other.start, end, other.end) {
        case let (a?, b?, c?, d?):
            return abs(a - b) <= 0.25 && abs(c - d) <= 0.25
        case let (a?, b?, _, _):
            return abs(a - b) <= 0.25
        case let (_, _, c?, d?):
            return abs(c - d) <= 0.25
        default:
            return false
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func mergeUtterancesForDisplay(_ utterances: [TranscriptUtterance]) -> TranscriptUtterance {
        let mergedText = utterances
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let starts = utterances.compactMap(\.start)
        let ends = utterances.compactMap(\.end)
        let confidences = utterances.compactMap(\.confidence)
        let dominantSpeaker = utterances
            .compactMap(\.speaker)
            .reduce(into: [Int: Int]()) { counts, speaker in
                counts[speaker, default: 0] += 1
            }
            .max(by: { $0.value < $1.value })?
            .key

        return TranscriptUtterance(
            id: utterances.first?.id ?? UUID().uuidString,
            text: mergedText,
            start: starts.isEmpty ? nil : starts.min(),
            end: ends.isEmpty ? nil : ends.max(),
            speaker: dominantSpeaker,
            confidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count),
            isInterim: false
        )
    }

    private static func mergedDuration(of utterances: [TranscriptUtterance]) -> Double {
        guard let start = utterances.compactMap(\.start).min(),
              let end = utterances.compactMap(\.end).max() else {
            return 0
        }
        return max(0, end - start)
    }

    private static func didSpeakerChange(current: [TranscriptUtterance], incoming: TranscriptUtterance) -> Bool {
        guard let incomingSpeaker = incoming.speaker else { return false }
        guard let currentSpeaker = current.compactMap(\.speaker).last else { return false }
        return currentSpeaker != incomingSpeaker
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let lastCharacter = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return lastCharacter == "." || lastCharacter == "!" || lastCharacter == "?"
    }

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// A text correction keeps each segment's recorded timing and speaker metadata.
/// Timing is never invented for imported or older plain-text transcripts.
struct TranscriptEditDraft: Equatable {
    let originalText: String
    let originalUtterances: [TranscriptUtterance]
    private let initialSegments: [TranscriptUtterance]
    var segments: [TranscriptUtterance]

    init(text: String, utterances: [TranscriptUtterance]) {
        originalText = text
        originalUtterances = utterances
        let paragraphs = utterances.isEmpty
            ? TranscriptUtterance.coalescedForDisplay(TranscriptUtterance.fallbackUtterances(from: text))
            : TranscriptUtterance.displayParagraphs(utterances)
        segments = paragraphs.isEmpty ? [TranscriptUtterance(id: "empty", text: "")] : paragraphs
        initialSegments = segments
    }

    var hasChanges: Bool { segments != initialSegments }
    var text: String { savedUtterances.map(\.text).joined(separator: "\n\n") }
    func matchCount(for query: TranscriptFindQuery) -> Int {
        guard let pattern = query.pattern else { return 0 }
        return segments.reduce(0) { $0 + pattern.numberOfMatches(in: $1.text, range: NSRange($1.text.startIndex..., in: $1.text)) }
    }

    mutating func replaceAll(_ query: TranscriptFindQuery, with replacement: String) {
        guard let pattern = query.pattern else { return }
        let literal = NSRegularExpression.escapedTemplate(for: replacement)
        for index in segments.indices {
            let text = segments[index].text
            segments[index].text = pattern.stringByReplacingMatches(in: text,
                range: NSRange(text.startIndex..., in: text), withTemplate: literal)
        }
    }
    var savedUtterances: [TranscriptUtterance] {
        segments.filter { !$0.isEmpty }.map {
            TranscriptUtterance(id: $0.id, text: $0.text, start: $0.start, end: $0.end,
                speaker: $0.speaker, confidence: $0.confidence, isInterim: false)
        }
    }
}

struct TranscriptFindQuery {
    var text = ""
    var matchCase = false
    var wholeWords = true

    var pattern: NSRegularExpression? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: text)
        let wordCharacter = #"[\p{L}\p{M}\p{N}_]"#
        let pattern = wholeWords ? "(?<!\(wordCharacter))\(escaped)(?!\(wordCharacter))" : escaped
        return try? NSRegularExpression(pattern: pattern, options: matchCase ? [] : .caseInsensitive)
    }
}

// MARK: - Common Response Structures

struct Template: Codable {
    let key: String
    let title: String
    let description: String
    let category: String?
}
