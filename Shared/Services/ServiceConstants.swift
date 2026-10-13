import Foundation

struct TranscriptUtterance: Codable, Identifiable, Hashable {
    let id: String
    let text: String
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

    static func fallbackUtterances(from transcript: String) -> [TranscriptUtterance] {
        let paragraphs = transcript
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.isEmpty {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return []
            }
            return [TranscriptUtterance(text: trimmed)]
        }

        return paragraphs.map { TranscriptUtterance(text: $0) }
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
        maxSentencesPerChunk: Int = 2
    ) -> [TranscriptUtterance] {
        let cleaned = deduplicated(utterances)
            .filter { !$0.isInterim && !$0.isEmpty }

        guard !cleaned.isEmpty else { return [] }

        let expanded = cleaned.flatMap { utterance in
            splitOversizedUtterance(
                utterance,
                maxWordsPerChunk: maxWordsPerChunk,
                maxSentencesPerChunk: maxSentencesPerChunk,
                maxDurationSeconds: maxDurationSeconds
            )
        }

        guard expanded.count > 1 else { return expanded }

        // If no timing exists, keep original segmentation (often paragraph-based fallback text).
        let hasTiming = expanded.contains { $0.start != nil || $0.end != nil }
        guard hasTiming else { return expanded }

        var coalesced: [TranscriptUtterance] = []
        var buffer: [TranscriptUtterance] = []
        var bufferedWordCount = 0
        var bufferedSentenceCount = 0

        for utterance in expanded {
            let incomingWordCount = wordCount(in: utterance.text)
            let sentenceBoundary = endsSentence(utterance.text)

            if buffer.isEmpty {
                buffer = [utterance]
                bufferedWordCount = incomingWordCount
                bufferedSentenceCount = sentenceBoundary ? 1 : 0
                continue
            }

            let speakerChanged = didSpeakerChange(current: buffer, incoming: utterance)
            if speakerChanged && bufferedWordCount >= minWordsPerChunk {
                coalesced.append(mergeUtterancesForDisplay(buffer))
                buffer = [utterance]
                bufferedWordCount = incomingWordCount
                bufferedSentenceCount = sentenceBoundary ? 1 : 0
                continue
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
                coalesced.append(mergeUtterancesForDisplay(buffer))
                buffer.removeAll(keepingCapacity: true)
                bufferedWordCount = 0
                bufferedSentenceCount = 0
            }
        }

        if !buffer.isEmpty {
            coalesced.append(mergeUtterancesForDisplay(buffer))
        }

        return coalesced
    }

    private static func splitOversizedUtterance(
        _ utterance: TranscriptUtterance,
        maxWordsPerChunk: Int,
        maxSentencesPerChunk: Int,
        maxDurationSeconds: Double
    ) -> [TranscriptUtterance] {
        let normalizedText = utterance.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else { return [] }

        let sentenceParts = sentenceUnits(from: normalizedText)
        let totalWords = wordCount(in: normalizedText)
        let totalSentences = max(sentenceParts.count, 1)
        let utteranceDuration = mergedDuration(of: [utterance])

        let shouldSplit = totalWords > maxWordsPerChunk ||
            totalSentences > maxSentencesPerChunk ||
            utteranceDuration > maxDurationSeconds * 1.15

        guard shouldSplit else { return [utterance] }

        var boundedUnits: [String] = []
        for part in sentenceParts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if wordCount(in: trimmed) <= maxWordsPerChunk {
                boundedUnits.append(trimmed)
            } else {
                boundedUnits.append(contentsOf: splitByWordCount(trimmed, maxWords: maxWordsPerChunk))
            }
        }

        guard !boundedUnits.isEmpty else { return [utterance] }

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

        for unit in boundedUnits {
            let unitWordCount = max(wordCount(in: unit), 1)
            let shouldFlushBeforeAppend = !buffer.isEmpty &&
                (bufferedWords + unitWordCount > maxWordsPerChunk ||
                    bufferedSentences + 1 > maxSentencesPerChunk)

            if shouldFlushBeforeAppend {
                flushBuffer()
            }

            buffer.append(unit)
            bufferedWords += unitWordCount
            bufferedSentences += 1

            if bufferedWords >= maxWordsPerChunk || bufferedSentences >= maxSentencesPerChunk {
                flushBuffer()
            }
        }

        flushBuffer()

        guard chunkTexts.count > 1 else { return [utterance] }

        let timeBounds = interpolatedTimeBounds(
            for: utterance,
            totalWords: max(totalWords, 1),
            fallbackChunkCount: chunkTexts.count
        )

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
                chunkStart = nil
                chunkEnd = nil
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

    private static func interpolatedTimeBounds(
        for utterance: TranscriptUtterance,
        totalWords: Int,
        fallbackChunkCount: Int
    ) -> (start: Double, end: Double, duration: Double)? {
        if let start = utterance.start,
           let end = utterance.end,
           end > start {
            return (start: start, end: end, duration: end - start)
        }

        let estimatedDuration = max(
            Double(totalWords) / 2.7,
            Double(max(fallbackChunkCount, 1)) * 2.0
        )

        if let start = utterance.start {
            return (start: start, end: start + estimatedDuration, duration: estimatedDuration)
        }

        if let end = utterance.end {
            let start = max(0, end - estimatedDuration)
            return (start: start, end: end, duration: estimatedDuration)
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
            return true
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

// MARK: - Common Response Structures

struct Template: Codable {
    let key: String
    let title: String
    let description: String
    let category: String?
}
