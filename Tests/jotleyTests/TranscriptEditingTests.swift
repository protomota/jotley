import XCTest
@testable import jotley

final class TranscriptEditingTests: XCTestCase {
    func testFindReplaceAcrossParagraphsKeepsTimingAndMatchesWholeWords() {
        let source = [TranscriptUtterance(id: "first", text: "JSON met JSONKit and json.", start: 0, end: 4, speaker: 1),
                      TranscriptUtterance(id: "second", text: "Ask JSON about the launch.", start: 15, end: 19, speaker: 2)]
        var draft = TranscriptEditDraft(text: source.map(\.text).joined(separator: " "), utterances: source)
        let query = TranscriptFindQuery(text: "JSON")
        XCTAssertEqual(draft.matchCount(for: query), 3)
        XCTAssertEqual(draft.matchCount(for: .init(text: "JSON", matchCase: true)), 2)
        XCTAssertEqual(draft.matchCount(for: .init(text: "JSON", wholeWords: false)), 4)
        draft.replaceAll(query, with: "Jason")
        XCTAssertEqual(draft.savedUtterances.map(\.text), ["Jason met JSONKit and Jason.", "Ask Jason about the launch."])
        XCTAssertEqual(draft.savedUtterances.map(\.start), source.map(\.start))
        XCTAssertEqual(draft.savedUtterances.map(\.speaker), source.map(\.speaker))
        draft.replaceAll(.init(text: "Jason"), with: #"$5\test"#)
        XCTAssertTrue(draft.text.contains(#"$5\test"#))
    }

    func testCustomWordEntriesTrimAndDeduplicateWithoutChangingSpelling() {
        XCTAssertEqual(CustomSpeechWords.entries(in: " Jason \r\n\nJASON\nNew   York\nProtomota "),
                       ["Jason", "New York", "Protomota"])
    }

    func testCustomWordImportReadsDelimitedListsAndQuotedPhrases() throws {
        XCTAssertEqual(try CustomSpeechWords.importedEntries(in: "\u{FEFF}PulseCanvas,\"Studio, North\"\r\nTextley,pulsecanvas", fileExtension: "CSV"),
                       ["PulseCanvas", "Studio, North", "Textley"])
        XCTAssertEqual(try CustomSpeechWords.importedEntries(in: "Jason\tTextley\nPulseCanvas", fileExtension: "tsv"),
                       ["Jason", "Textley", "PulseCanvas"])
        XCTAssertEqual(try CustomSpeechWords.importedEntries(in: "Jason; PulseCanvas\nTextley,New York", fileExtension: "txt"),
                       ["Jason", "PulseCanvas", "Textley", "New York"])
        XCTAssertThrowsError(try CustomSpeechWords.importedEntries(in: "\"unfinished", fileExtension: "csv"))
    }

    func testCorrectionPreservesTimingSpeakersAndParagraphBreaks() throws {
        let source = [TranscriptUtterance(id: "first", text: "Review the disign.", start: 0, end: 4, speaker: 1, confidence: 0.8),
                      TranscriptUtterance(id: "second", text: "Ship on Friday.", start: 15.4, end: 19, speaker: 2)]
        var draft = TranscriptEditDraft(text: "Review the disign. Ship on Friday.", utterances: source)
        XCTAssertFalse(draft.hasChanges)
        draft.segments[0].text = "Review the design.\nKeep the purple branding."
        XCTAssertTrue(draft.hasChanges)
        XCTAssertEqual(draft.text, "Review the design.\nKeep the purple branding.\n\nShip on Friday.")
        let decoded = try JSONDecoder().decode([TranscriptUtterance].self, from: JSONEncoder().encode(draft.savedUtterances))
        XCTAssertEqual(decoded[0].id, "first")
        XCTAssertEqual(decoded[0].start, 0)
        XCTAssertEqual(decoded[0].end, 4)
        XCTAssertEqual(decoded[0].speaker, 1)
        XCTAssertEqual(decoded[0].confidence, 0.8)
        XCTAssertEqual(decoded[1], source[1])
        let reopened = TranscriptEditDraft(text: draft.text, utterances: decoded)
        XCTAssertFalse(reopened.hasChanges)
        XCTAssertEqual(reopened.segments.map(\.text), ["Review the design.\nKeep the purple branding.", "Ship on Friday."])
        XCTAssertEqual(reopened.segments.first?.start, source.first?.start)
        XCTAssertEqual(reopened.segments.first?.end, source.first?.end)
        XCTAssertEqual(reopened.segments.last, source.last)
    }

    func testBracketedTextParsesBackIntoEditableTimestampedRows() {
        let source = [
            TranscriptUtterance(id: "first", text: "First line.", start: 2.3, end: 4, speaker: 1),
            TranscriptUtterance(id: "second", text: "Second line.", start: 15.4, end: 19, speaker: 2)
        ]
        var draft = TranscriptEditDraft(text: "First line. Second line.", utterances: source)
        XCTAssertEqual(draft.editorText, "[00:02]\nFirst line.\n[00:15]\nSecond line.")
        draft.editorText = "Untimed preface.\n\n[00:02]\nFirst corrected line.\n[00:15]\nSecond line.\nExtra line."
        XCTAssertEqual(draft.savedUtterances.map(\.start), [nil, 2.3, 15.4])
        XCTAssertEqual(draft.savedUtterances.map(\.speaker), [nil, 1, 2])
        XCTAssertEqual(draft.savedUtterances.last?.text, "Second line.\nExtra line.")
        XCTAssertEqual(TranscriptUtterance.fallbackUtterances(from: draft.editorText).map(\.start), [nil, 2, 15])
        XCTAssertEqual(draft.matchCount(for: .init(text: "00:02")), 0)
        XCTAssertFalse(draft.text.contains("[00:02]"))
    }

    func testUntimedLegacyTextGetsReadableBreaksWithoutFabricatedTimestamps() {
        let text = String(repeating: "This is an older transcript with no saved timing. ", count: 40)
        var draft = TranscriptEditDraft(text: text, utterances: [])
        XCTAssertGreaterThan(draft.segments.count, 10)
        XCTAssertTrue(draft.segments.allSatisfy { $0.start == nil && $0.end == nil })
        XCTAssertFalse(draft.hasChanges)
        XCTAssertEqual(draft.editorText, text)
        draft.segments[0].text += "Corrected."
        XCTAssertTrue(draft.text.contains("\n\n"))
        XCTAssertTrue(draft.savedUtterances.allSatisfy { $0.timestampLabel == nil })
    }

    func testExplicitParagraphsAndEmptySegmentDeletionKeepOtherAnchors() {
        XCTAssertEqual(TranscriptUtterance.fallbackUtterances(from: "One.\nTwo.\n\nThree.").map(\.text), ["One.", "Two.", "Three."])
        let source = [TranscriptUtterance(text: "One.", start: 0, end: 1), TranscriptUtterance(text: "Two.", start: 10, end: 11)]
        var draft = TranscriptEditDraft(text: "One. Two.", utterances: source)
        draft.segments[0].text = "  \n"
        XCTAssertEqual(draft.text, "Two.")
        XCTAssertEqual(draft.savedUtterances.first?.start, 10)
        let display = TranscriptUtterance.displayParagraphs(source)
        XCTAssertEqual(display.map(\.text), ["One.", "Two."])
        XCTAssertEqual(display.map(\.timestampLabel), ["00:00", "00:10"])
    }

    func testTimestampFormattingRejectsCorruptTiming() {
        XCTAssertEqual(TranscriptUtterance(text: "Hour", start: 3661.9).timestampLabel, "61:01")
        for value in [Double.nan, .infinity, -.infinity, -1, Double.greatestFiniteMagnitude] {
            XCTAssertNil(TranscriptUtterance(text: "Invalid", start: value).timestampLabel)
        }
    }

    func testDisplayKeepsTimestampsAcrossPausesAndSpeakerChanges() {
        let source = [
            TranscriptUtterance(text: "Hello there.", start: 0, end: 2, speaker: 1),
            TranscriptUtterance(text: "Welcome back.", start: 25, end: 27, speaker: 1),
            TranscriptUtterance(text: "Thanks.", start: 27.5, end: 28, speaker: 2),
            TranscriptUtterance(text: "Let's start.", start: 28.2, end: 29, speaker: 2)
        ]
        let paragraphs = TranscriptUtterance.coalescedForDisplay(source)
        XCTAssertEqual(paragraphs.map(\.text), ["Hello there.", "Welcome back.", "Thanks. Let's start."])
        XCTAssertEqual(paragraphs.map(\.timestampLabel), ["00:00", "00:25", "00:27"])
    }

    func testExplicitBreaksAndRepeatedUntimedLinesSurviveRendering() {
        let multiline = TranscriptUtterance(text: "First line.\n\nSecond line.", start: 12)
        let rows = TranscriptUtterance.coalescedForDisplay([multiline])
        XCTAssertEqual(rows.map(\.text), ["First line.", "Second line."])
        XCTAssertEqual(rows.map(\.timestampLabel), ["00:12", nil])

        let legacy = TranscriptUtterance.fallbackUtterances(from: "Same line.\nSame line.")
        XCTAssertEqual(TranscriptUtterance.coalescedForDisplay(legacy), legacy)
    }
}
