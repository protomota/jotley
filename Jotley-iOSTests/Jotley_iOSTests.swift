import CoreData
import Testing
import Foundation
import AVFoundation
import UIKit
import Speech
import FoundationModels
import XCTest
@testable import Jotley_iOS

@Suite(.serialized)
struct Jotley_iOSTests {
    @MainActor @Test func summaryEditsPersistMarkdownWithoutChangingTranscriptAndRejectStaleDrafts() throws {
        let store = try SharedPersistenceController(root: FileManager.default.temporaryDirectory.appendingPathComponent("JotleySummaryEditing-" + UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try #require(store.create(title: "Edited summary", text: "Original spoken words.") as? Note)
        let original = "# Decisions\n- Original decision."
        note.summary = original
        note.setTranscriptUtterances([TranscriptUtterance(id: "original", text: "Original spoken words.", start: 4, end: 6)])
        try store.context.save()
        let timing = note.value(forKey: "transcriptUtterancesJSON") as? String
        let edited = "# Decisions\n- **Approved** decision.\n  - Follow up Friday."
        try note.saveEditedSummary(edited, original: original, in: store)
        #expect(note.summary == edited)
        #expect(note.transcription == "Original spoken words.")
        #expect(note.value(forKey: "transcriptUtterancesJSON") as? String == timing)
        #expect(throws: (any Error).self) { try note.saveEditedSummary("Stale edit", original: original, in: store) }
        let id = note.objectID
        store.context.reset()
        let reloaded = try #require(store.context.existingObject(with: id) as? Note)
        #expect(reloaded.summary == edited)
        #expect(reloaded.transcription == "Original spoken words.")
        #expect(reloaded.value(forKey: "transcriptUtterancesJSON") as? String == timing)
    }

    @MainActor @Test func summaryMarkdownRendersListsAndPreservesInlineFormatting() throws {
        let source = "# Decisions\n- **Keep** the transcript.\n  - Nested task.\n* Another task.\n+ Last task.\n1. First step.\n2) Second step.\nA - dash in prose.\n\\- Escaped dash."
        let parsed = ParsedNoteMarkdown.rendering(source)
        #expect(parsed.lines[0].heading)
        #expect(parsed.lines[1...4].allSatisfy { $0.marker == "•" })
        #expect(parsed.lines[1].text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(String(parsed.lines[1].text.characters) == "Keep the transcript.")
        #expect(parsed.lines[2].indentation == 2)
        #expect(parsed.lines[5].marker == "1." && parsed.lines[6].marker == "2.")
        #expect(parsed.lines[7].marker == nil && parsed.lines[8].marker == nil)
        #expect(ParsedNoteMarkdown.rendering(source) === parsed)
    }

    @Test func askAIConversationExportsEveryTurnInOrder() {
        let messages = [LocalChatMessage(role: "user", content: "Who owns onboarding?"),
                        LocalChatMessage(role: "assistant", content: "- Maya finishes the onboarding screens.\n")]
        let text = LocalNoteChat.conversationMarkdown(title: "Weekly Design Review", messages: messages)
        #expect(text == "# Ask AI: Weekly Design Review\n\n**You**\n\nWho owns onboarding?\n\n**Jotley**\n\n- Maya finishes the onboarding screens.")
        #expect(LocalNoteChat.conversationMarkdown(title: nil, messages: []) == "# Ask AI: Untitled")
    }

    @MainActor @Test func structuredSummaryGroupsOverviewSectionsAndLabels() throws {
        let source = "## Summary\nThe team agreed to ship Friday.\n\n## Key Points\n- **Launch date**: Friday at 10:00.\n  - Room booked.\n- Keep the transcript simple.\n\n## Action Items\n- **Maya**: Finish onboarding.\n- Check https://example.com today.\n\n## Open Questions\n- Who owns widgets?"
        let summary = StructuredSummary(ParsedNoteMarkdown.rendering(source))
        let overview = try #require(summary.overview)
        #expect(String(overview.paragraphs[0].text.characters) == "The team agreed to ship Friday.")
        #expect(summary.sections.map(\.title) == ["Key Points", "Action Items", "Open Questions"])
        #expect(summary.sections.map(\.style) == [.numbered, .checklist, .questions])
        let points = summary.sections[0].items
        #expect(points[0].label.map { String($0.characters) } == "Launch date")
        #expect(String(points[0].body.characters) == "Friday at 10:00.")
        #expect(StructuredSummaryView.groups(points).map(\.count) == [2, 1])
        #expect(summary.sections[1].items[0].label.map { String($0.characters) } == "Maya")
        #expect(summary.sections[1].items[1].label == nil)
        let french = StructuredSummary(ParsedNoteMarkdown.rendering("## Résumé\nLancement vendredi.\n\n## Actions\n- Tester."))
        #expect(french.overview != nil && french.sections.count == 1)
        let legacy = StructuredSummary(ParsedNoteMarkdown.rendering("The team reviewed the launch.\n**Key Points:**\n- Ship Friday.\n**Action Items**\n- **Maya**: Finish onboarding.\nA **bold** word in prose."))
        #expect(legacy.overview.map { String($0.paragraphs[0].text.characters) } == "The team reviewed the launch.")
        #expect(legacy.sections.map(\.title) == ["Key Points", "Action Items"])
        #expect(legacy.sections[1].style == .checklist && legacy.sections[1].paragraphs.count == 1)
        let untitled = StructuredSummary(ParsedNoteMarkdown.rendering("# Decisions\n- Keep it."))
        #expect(untitled.overview == nil && untitled.sections.count == 1)
    }

    @MainActor @Test func transcriptEditsPersistWithoutReplacingSummaryAndRejectStaleDrafts() throws {
        let store = try SharedPersistenceController(root: FileManager.default.temporaryDirectory.appendingPathComponent("JotleyTranscriptEditing-" + UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try #require(store.create(title: "Edited note", text: "Original words.") as? Note)
        note.summary = "Keep this summary."
        note.sourceURL = "local://existing-mac-recording"
        note.setTranscriptUtterances([TranscriptUtterance(id: "original", text: "Original words.", start: 4, end: 6)])
        try store.context.save()
        let originalPayload = note.value(forKey: "transcriptUtterancesJSON") as? String
        try note.saveEditedTranscript("Original words.", original: "Original words.", in: store)
        #expect(note.value(forKey: "transcriptUtterancesJSON") as? String == originalPayload)
        try note.saveEditedTranscript("Corrected words.\n\nSecond paragraph.", original: "Original words.", in: store)
        #expect(note.transcriptUtterances.map(\.text) == ["Corrected words.", "Second paragraph."])
        #expect(note.transcriptUtterances.allSatisfy { $0.start == nil && $0.end == nil })
        #expect(note.summary == "Keep this summary.")
        #expect(note.sourceURL == "local://existing-mac-recording")
        #expect(throws: (any Error).self) {
            try note.saveEditedTranscript("Stale changes.", original: "Original words.", in: store)
        }
        let id = note.objectID
        store.context.reset()
        let reloaded = try #require(store.context.existingObject(with: id) as? Note)
        #expect(reloaded.transcription == "Corrected words.\n\nSecond paragraph.")
        #expect(reloaded.transcriptUtterances.map(\.text) == ["Corrected words.", "Second paragraph."])
        #expect(reloaded.summary == "Keep this summary.")
        #expect(reloaded.sourceURL == "local://existing-mac-recording")
    }
    @Test func widgetLinksAcceptTranscriptionAndInstalledWidgetAliases() throws {
        let id = UUID()
        #expect(MobileTranscriptionAction(url: try #require(URL(string: "jotley://startrecording"))) == .start)
        #expect(MobileTranscriptionAction(url: try #require(URL(string: "jotley://stoprecording?id=\(id.uuidString)"))) == .stop(id))
        #expect(MobileTranscriptionAction(url: try #require(URL(string: "jotley://pauserecording?id=\(id.uuidString)"))) == .pause(id))
        #expect(MobileTranscriptionAction(url: try #require(URL(string: "jotley://starttranscription"))) == .start)
        #expect(MobileTranscriptionAction(url: try #require(URL(string: "jotley://stoptranscription?id=\(id.uuidString)"))) == .stop(id))
        #expect(MobileTranscriptionAction(url: try #require(URL(string: "jotley://pausetranscription?id=\(id.uuidString)"))) == .pause(id))
        #expect(MobileTranscriptionAction(url: try #require(URL(string: "jotley://transcription?id=\(id.uuidString)"))) == .open(id))
        for invalid in ["https://startrecording", "jotley://stoprecording", "jotley://pauserecording?id=invalid", "jotley://recording?id=\(id.uuidString)&id=\(id.uuidString)", "jotley://other?id=\(id.uuidString)"] {
            #expect(MobileTranscriptionAction(url: try #require(URL(string: invalid))) == nil)
        }
    }
    @Test func askAISelectsEvidenceBeyondBeginningAndBoundsHistory() throws {
        let source = String(repeating: "Routine introduction. ", count: 500) + " The launch owner is Mina; shipping is Friday."
        let history = [LocalChatMessage(role: "assistant", content: String(repeating: "old answer ", count: 1000))]
        let prompt = try LocalNoteChat.prompt(source: source, question: "Who is the launch owner?", history: history)
        #expect(prompt.contains("launch owner is Mina"))
        #expect(prompt.utf8.count < 4000)
        #expect(prompt.contains("selected excerpts"))
        #expect(throws: (any Error).self) { try LocalNoteChat.prompt(source: "", question: "Who?", history: []) }
        #expect(throws: (any Error).self) { try LocalNoteChat.prompt(source: "A note", question: String(repeating: "x", count: 801), history: []) }
    }
    @MainActor @Test func askAIHistoryIsNoteScopedAndSurvivesReloadAndDeletion() throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = try store.create(title: "First", text: "Mina ships Friday")
        let second = try store.create(title: "Second")
        let firstID = try #require(first.localNoteID), secondID = try #require(second.localNoteID)
        let question = LocalChatMessage(role: "user", content: "Who ships?")
        let answer = LocalChatMessage(role: "assistant", content: "Mina.", timestamp: question.timestamp)
        try store.saveChatMessage(question, noteID: firstID)
        try store.saveChatMessage(answer, noteID: firstID)
        let loaded = try store.chatMessages(noteID: firstID)
        #expect(loaded.map(\.id) == [question.id, answer.id])
        #expect(loaded.map(\.content) == [question.content, answer.content])
        #expect(loaded.map(\.role) == ["user", "assistant"])
        #expect(abs((loaded.first?.timestamp ?? .distantPast).timeIntervalSince(question.timestamp)) < 0.000001)
        #expect(try store.chatMessages(noteID: secondID).isEmpty)
        store.context.reset()
        let reloaded = try store.chatMessages(noteID: firstID)
        #expect(reloaded.map(\.id) == [question.id, answer.id])
        #expect(reloaded.map(\.content) == [question.content, answer.content])
        try store.clearChat(noteID: secondID)
        #expect(try store.chatMessages(noteID: firstID).count == 2)
        let note = try #require(store.notes().first { $0.localNoteID == firstID })
        try store.deleteNoteAndAudio(note)
        #expect(try store.chatMessages(noteID: firstID).isEmpty)
        #expect(throws: (any Error).self) { try store.saveChatMessage(answer, noteID: firstID) }
    }
    @Test func microphoneKeepsListeningThroughSilenceWhileBuffersArrive() {
        let progress = MicrophoneCaptureProgress(startedAt: 100)
        // Ten seconds of microphone buffers (which may contain silence) still
        // count as delivery. Silence must never trigger a disconnected-input alert.
        for second in 100...110 { progress.received(frames: 48000, at: Double(second)) }
        #expect(!progress.snapshot(at: 110).stalled)
        #expect(progress.snapshot(at: 110).frames == 528000)
        #expect(progress.snapshot(at: 113).stalled)
    }
    @Test func microphoneFailuresExplainRecoveryInsteadOfShowingOSStatusText() {
        let message = LiveTranscriptionManager.microphoneErrorMessage(NSError(domain: NSOSStatusErrorDomain, code: -10851))
        #expect(message.contains("Settings → Apps → Jotley"))
        #expect(message.contains("preserved"))
        #expect(!message.contains("-10851"))
        #expect(LiveTranscriptionManager.microphoneErrorMessage(LocalError.message("The microphone is muted.")) == "The microphone is muted.")
    }


    @Test func microphoneProgressDistinguishesSilenceFromMissingBuffers() {
        let progress = MicrophoneCaptureProgress(startedAt: 100)
        #expect(progress.snapshot(at: 102).frames == 0)
        #expect(!progress.snapshot(at: 102).stalled)
        #expect(progress.snapshot(at: 103).stalled)
        // Zero-amplitude PCM still arrives as frames and must keep transcribing.
        progress.received(frames: 48000, at: 103)
        #expect(progress.snapshot(at: 105).frames == 48000)
        #expect(!progress.snapshot(at: 105).stalled)
        progress.received(frames: 0, at: 105)
        #expect(progress.snapshot(at: 106).stalled)
        progress.received(frames: 24000, at: 106)
        #expect(progress.snapshot(at: 106).frames == 72000)
        #expect(!progress.snapshot(at: 106).stalled)
    }
    @MainActor @Test func unsupportedSpeechStopsBeforeMicrophoneCaptureAndCreatesNoAudio() async throws {
        let previous = UserDefaults.standard.string(forKey: "transcriptionLanguage")
        UserDefaults.standard.set("zxx", forKey: "transcriptionLanguage")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "transcriptionLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "transcriptionLanguage") }
        }
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let service = LiveTranscriptionManager(store: store)
        let note = try service.createNote(text: "Keep existing words")
        note.summary = "Keep existing summary"; try store.save()
        await service.startTranscription(note: note)
        #expect(!service.isTranscribing && service.canStart && service.activeNoteID == nil)
        #expect(service.transcriptionDuration == 0)
        #expect(service.errorMessage?.contains("unavailable") == true)
        #expect(note.sourceURL == nil && note.transcription == "Keep existing words")
        #expect(note.summary == "Keep existing summary")
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("Recordings").path))
        let lease = try store.beginRecording(note); store.endRecording(lease: lease)
    }
    @MainActor @Test func upgradeDeletesLegacyAudioAndPreservesNotesAndUnrelatedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SharedPersistenceController(root: root)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let note = try #require(store.create(title: "Keep this note", text: "Existing spoken words.") as? Note)
        note.summary = "Existing summary."
        note.sourceURL = "Recordings/legacy"
        try store.save()
        for name in ["Recordings", "DeletedRecordings"] {
            let directory = root.appendingPathComponent(name).appendingPathComponent("legacy/take")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent("audio.caf"))
        }
        let unrelated = root.appendingPathComponent("Keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let manager = LiveTranscriptionManager(store: store)
        #expect(manager.errorMessage == nil)
        for name in ["Recordings", "DeletedRecordings"] {
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
        #expect(try Data(contentsOf: unrelated) == Data("keep".utf8))
        store.context.reset()
        let reloaded = try #require(store.notes().first as? Note)
        #expect(reloaded.title == "Keep this note")
        #expect(reloaded.transcription == "Existing spoken words.")
        #expect(reloaded.summary == "Existing summary.")
        try LegacyMobileAudioCleanup.remove(in: root) // Repeated launches are harmless.
    }
    @MainActor @Test func liveCheckpointPersistsVolatileRevisionsAndFinalWordsWithoutAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SharedPersistenceController(root: root)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let note = try #require(store.create(title: "Checkpoint", text: "Previous words") as? Note)
        note.setTranscriptUtterances([TranscriptUtterance(text: "Previous words", start: 0, end: 100)])
        note.summary = "Previous summary"
        let checkpoint = MobileTranscriptCheckpoint(baseText: note.transcription ?? "", baseUtterances: note.transcriptUtterances, offset: 100)
        var value = LocalTranscript()
        value.accept(text: "Mina ship", start: 0, end: 2, final: false)
        _ = try checkpoint.save(value, to: note, in: store)
        store.context.refresh(note, mergeChanges: false)
        #expect(note.transcription == "Previous words Mina ship")
        #expect(note.transcriptUtterances.last?.end == 102)
        value.accept(text: "Mina ships Friday", start: 0, end: 3, final: false)
        _ = try checkpoint.save(value, to: note, in: store)
        #expect(note.transcription == "Previous words Mina ships Friday")
        value.accept(text: "Mina ships Friday.", start: 0, end: 3, final: true)
        _ = try checkpoint.save(value, to: note, in: store)
        store.context.reset()
        let reloaded = try #require(store.notes().first as? Note)
        #expect(reloaded.transcription == "Previous words Mina ships Friday.")
        #expect(reloaded.transcriptUtterances.map(\.text).joined(separator: " ") == "Previous words Mina ships Friday.")
        #expect(reloaded.transcriptUtterances.last?.end == 103)
        #expect(reloaded.summary == "Previous summary")
        #expect(reloaded.sourceURL == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Recordings").path))
    }
    @Test func encryptedStoreAllowsNoteCheckpointsAfterFirstUnlock() throws {
        let description = try NoteSyncMode.localOnly.storeDescription(at: URL(fileURLWithPath: "/tmp/unused-check.sqlite"), inMemory: false)
        #expect(description.options[NSPersistentStoreFileProtectionKey] as? String == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
    }
    @Test func websiteTipEligibilityFailsClosedOutsidePermittedStorefront() {
        #expect(JotleyWebsiteTipPolicy.allowsTips(countryCode: "USA"))
        for country in [nil, "", "GBR", "CAN", "DEU", "CHN", "US"] as [String?] {
            #expect(!JotleyWebsiteTipPolicy.allowsTips(countryCode: country))
        }
    }

    @MainActor @Test func engagementWaitsForSuccessAndIdleAndNeverRepeats() throws {
        let suite = "JotleyEngagementTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = JotleyEngagement(defaults: defaults)
        progress.completedSummary(result: "   \n")
        #expect(progress.completedActions == 0)
        #expect(progress.claimPrompt(isIdle: true) == nil)
        for _ in 0..<4 { progress.completedSummary(result: "Saved summary") }
        #expect(progress.claimPrompt(isIdle: true) == nil)
        progress.completedSummary(result: "Saved summary")
        #expect(progress.claimPrompt(isIdle: false) == nil)
        progress.beginProcessing()
        #expect(progress.claimPrompt(isIdle: true) == nil)
        progress.endProcessing()
        #expect(progress.claimPrompt(isIdle: true) == .review)
        #expect(progress.claimPrompt(isIdle: true) == nil)
        let relaunched = JotleyEngagement(defaults: defaults)
        #expect(relaunched.completedActions == 5)
        #expect(relaunched.claimPrompt(isIdle: true) == nil)
        for _ in 0..<3 { relaunched.completedSummary(result: "Another saved result") }
        #expect(relaunched.claimPrompt(isIdle: true) == nil)
        #expect(relaunched.claimPrompt(isIdle: true) == nil)
        let afterDismissal = JotleyEngagement(defaults: defaults)
        afterDismissal.completedSummary(result: "Later summary")
        #expect(afterDismissal.claimPrompt(isIdle: true) == nil)
    }
    @MainActor @Test func engagementUsesOnlyNativeReviewEvenAfterSixCompletions() throws {
        let suite = "JotleyEngagementTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(6, forKey: JotleyEngagement.countKey)
        let progress = JotleyEngagement(defaults: defaults)
        #expect(progress.claimPrompt(isIdle: true) == .review)
        #expect(progress.claimPrompt(isIdle: true) == nil)
        progress.completedSummary(result: "Next successful action")
        #expect(progress.claimPrompt(isIdle: true) == nil)
    }

    @MainActor @Test func unchangedSummaryRenderingReusesParsedMarkdownAndTracksEdits() throws {
        let marker = UUID().uuidString
        let content = "# " + marker + "\n" + (0..<1000).map { "- **Point \($0)**: recorded words with *emphasis* and [a link](https://example.com)." }.joined(separator: "\n")
        let start = Date()
        let parsed = ParsedNoteMarkdown.rendering(content)
        let cold = Date().timeIntervalSince(start)
        #expect(parsed.lines.count == 1001)
        #expect(parsed.lines[0].heading)
        #expect(String(parsed.lines[0].text.characters) == marker)
        let warmStart = Date()
        for _ in 0..<100 { #expect(ParsedNoteMarkdown.rendering(content) === parsed) }
        print("Summary rendering: cold \(cold)s; 100 unchanged lookups \(Date().timeIntervalSince(warmStart))s")
        let edited = ParsedNoteMarkdown.rendering("# Updated heading\n**Fresh words**")
        #expect(edited !== parsed)
        #expect(String(edited.lines[0].text.characters) == "Updated heading")
        #expect(String(edited.lines[1].text.characters) == "Fresh words")
        let fenced = ParsedNoteMarkdown.rendering("```markdown\n# Fenced heading\nBody\n```")
        #expect(fenced.lines.count == 2 && fenced.lines[0].heading)
    }
    @Test func speechSetupSelection() async throws {
        #expect(LocalSpeech.preferredIndex(statuses: [.supported, .installed]) == 1)
        #expect(LocalSpeech.preferredIndex(statuses: [.supported, .downloading]) == 0)
        #expect(LocalSpeech.preferredIndex(statuses: [.unsupported, .supported]) == 1)
        #expect(LocalSpeech.preferredIndex(statuses: [.unsupported]) == 0)
        #expect(LocalSpeech.preferredIndex(statuses: []) == nil)
        let locale = Locale(identifier: "en_US")
        #expect(LocalSpeech.exactLocale(Locale(identifier: "en-US"), in: [locale]) == locale)
        #expect(LocalSpeech.exactLocale(Locale(identifier: "en-GB"), in: [locale]) == nil)
        let module = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
        let notReady = LocalSpeech.Readiness(configuration: .init(module: module, engine: .dictation, locale: locale), status: .unsupported)
        #expect(notReady.needsSetup)
        #expect(notReady.message.contains("Set Up On-Device Speech"))
        let installed = LocalSpeech.Readiness(configuration: .init(module: module, engine: .dictation, locale: locale), status: .installed)
        let selected = try LocalSpeech.configuration(from: installed)
        #expect(selected.engine == .dictation && selected.locale == locale)
        #expect((selected.module as? DictationTranscriber) === module)
        do {
            _ = try LocalSpeech.configuration(from: notReady)
            Issue.record("An unready configuration must not be accepted for transcription")
        } catch { #expect(error.localizedDescription.contains("Set Up On-Device Speech")) }
        let ready = await LocalSpeech.readiness(locale: Locale(identifier: "zxx"))
        #expect(ready.status == .unsupported)
        #expect(!ready.needsSetup)
        do {
            try await LocalSpeech.setUp(locale: Locale(identifier: "zxx")) { _ in
                Issue.record("Unsupported speech must not start setup or report download progress")
            }
            Issue.record("Unsupported speech setup must fail before installation")
        } catch {
            #expect(error.localizedDescription.contains("unavailable for the selected language"))
        }
    }
    @MainActor @Test func transcriptDisplayTracksRevisionsAndIndependentContexts() throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let context = store.context
        let note = try #require(store.create(title: "Generated display fixture") as? Note)
        for revision in 0..<100 {
            let text = "Revision \(revision) " + String(repeating: "你好📝", count: 128)
            note.transcription = text
            note.setTranscriptUtterances([TranscriptUtterance(id: "fixture", text: text, start: 12, end: 14, speaker: 3, confidence: 0.88)])
            let display = try #require(note.transcriptUtterances.first)
            #expect(note.transcriptUtterances.count == 1)
            #expect(display.text == text && display.start == 12 && display.end == 14)
            #expect(display.speaker == 3 && display.confidence == 0.88)
        }
        try context.save()
        let expected = note.transcriptUtterances
        let otherContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        otherContext.persistentStoreCoordinator = context.persistentStoreCoordinator
        let other = try #require(otherContext.existingObject(with: note.objectID) as? Note)
        other.transcription = "Unsaved text from another context."
        other.setTranscriptUtterances([TranscriptUtterance(text: other.transcription!, start: 42, end: 44)])
        #expect(other.transcriptUtterances.first?.start == 42)
        #expect(note.transcriptUtterances == expected)
        note.transcription = "Fresh manual fallback."
        note.setTranscriptUtterances([])
        #expect(note.transcriptUtterances.map(\.text) == ["Fresh manual fallback."])
        note.transcription = "Updated fallback after unreadable metadata."
        note.setValue("{", forKey: "transcriptUtterancesJSON")
        #expect(note.transcriptUtterances.map(\.text) == [note.transcription!])
        context.rollback()
        #expect(note.transcriptUtterances == expected)
    }
    @Test func appleIntelligenceHardwareEligibilityDoesNotRejectPendingSetup() {
        #expect(JotleyAppleIntelligenceEligibility.supports(availability: .available))
        #expect(JotleyAppleIntelligenceEligibility.supports(availability: .unavailable(.appleIntelligenceNotEnabled)))
        #expect(JotleyAppleIntelligenceEligibility.supports(availability: .unavailable(.modelNotReady)))
        #expect(!JotleyAppleIntelligenceEligibility.supports(availability: .unavailable(.deviceNotEligible)))
    }
    @Test func microphoneStereoMixPreservesSamples() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        let channels = try #require(buffer.floatChannelData)
        for (index, value) in [Float(0.2), 0.4, -0.6].enumerated() { channels[0][index] = value }
        for (index, value) in [Float(0.6), -0.4, -0.2].enumerated() { channels[1][index] = value }
        let data = try LiveTranscriptionManager.monoPCM(buffer)
        #expect(try LiveTranscriptionManager.monoPCM(AVReadOnlyAudioPCMBuffer(copying: buffer)) == data)
        let actual = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(actual.count == 3)
        #expect(abs(actual[0] - 0.4) < 0.00001)
        #expect(abs(actual[1]) < 0.00001)
        #expect(abs(actual[2] + 0.4) < 0.00001)
    }


}

extension Jotley_iOSTests {


    @MainActor @Test func localExportsKeepOriginalFormatsAndIsolateTemporaryFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SharedPersistenceController(root: root)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let recorder = LiveTranscriptionManager(store: store)
        let text = "Café 日本語 🎙️\nFinal words retained."
        let note = try recorder.createNote(text: text, title: "Meeting/with:team")
        note.summary = "Decision: local processing."; try store.save()
        let full = LocalNoteExport.content(note: note, format: .markdown)
        #expect(full.contains("## Summary\n\nDecision: local processing.") && full.contains("## Transcript\n\n" + text))
        #expect(LocalNoteExport.content(note: note, format: .plainText).contains("TRANSCRIPT\n----------\n" + text))
        #expect(!LocalNoteExport.content(note: note, format: .summary).contains(text))
        #expect(!LocalNoteExport.content(note: note, format: .transcript).contains("Decision: local processing."))
        let first = try LocalNoteExport.file(note: note, format: .markdown, temporaryRoot: root)
        let second = try LocalNoteExport.file(note: note, format: .markdown, temporaryRoot: root)
        #expect(first != second && first.lastPathComponent == "Meeting-with-team.md")
        #expect(try String(contentsOf: first, encoding: .utf8) == full)
        note.title = String(repeating: "👩🏽‍💻", count: 100); try store.save()
        let longName = try LocalNoteExport.file(note: note, format: .transcript, temporaryRoot: root)
        #expect(longName.lastPathComponent.utf8.count < 255)
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data([1]).write(to: blocker)
        #expect(throws: (any Error).self) { try LocalNoteExport.file(note: note, format: .markdown, temporaryRoot: blocker) }
        #expect(note.transcription == text && note.summary == "Decision: local processing.")
        #expect(try String(contentsOf: first, encoding: .utf8) == full)
        let retained = root.appendingPathComponent("Saved Export.txt")
        try full.write(to: retained, atomically: true, encoding: .utf8)
        let unrelated = root.appendingPathComponent("JotleyExport-keep-this-folder")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("JotleyExport-\(UUID())")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)
        let ordinaryFile = root.appendingPathComponent("JotleyExport-\(UUID())")
        try Data([1]).write(to: ordinaryFile)
        try LocalNoteExport.cleanupStaleExports(temporaryRoot: root)
        for file in [first, second, longName] {
            #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        }
        #expect(try String(contentsOf: retained, encoding: .utf8) == full)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try Data(contentsOf: ordinaryFile) == Data([1]))
        #expect(try store.notes().count == 1 && note.transcription == text)
        try LocalNoteExport.cleanupStaleExports(temporaryRoot: root) // Relaunch cleanup is idempotent.
    }


}


extension Jotley_iOSTests {

}

/// Actual model checks: never substitute fixtures for recognized/generated output.
/// These skip explicitly when Apple does not expose the required model in Simulator.
final class SimulatorModelAcceptanceTests: XCTestCase {

    @MainActor func testLiveSpeechRecognizesAudioSourceAndCheckpointsWithoutSavingAudio() async throws {
        let locale = Locale(identifier: "en-US")
        let ready = await LocalSpeech.readiness(locale: locale)
        guard ready.status == .installed, let config = ready.configuration,
              !(await config.module.availableCompatibleAudioFormats).isEmpty else {
            throw XCTSkip("Apple exposes no usable on-device speech model here. Actual live recognition is unverified; checkpoint fixtures do not substitute for inference.")
        }
        let fixture = URL(fileURLWithPath: "/tmp/jotley-local-live-speech.aiff")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Spoken-audio source fixture is unavailable") }
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try XCTUnwrap(store.create(title: "Live acceptance") as? Note)
        let checkpoint = MobileTranscriptCheckpoint(baseText: "", baseUtterances: [], offset: 0)
        let session = try await LiveSpeechSession.start(locale: locale) { value in
            await MainActor.run { _ = try? checkpoint.save(value, to: note, in: store) }
        }
        let source = try AVAudioFile(forReading: fixture, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 2400))
        while source.framePosition < source.length {
            try source.read(into: buffer)
            session.append(try LiveTranscriptionManager.monoPCM(buffer), sampleRate: source.processingFormat.sampleRate)
            try await Task.sleep(for: .milliseconds(150))
        }
        let result = try await session.finish()
        _ = try checkpoint.save(result, to: note, in: store)
        XCTAssertTrue(result.text.lowercased().contains("purple bicycle"), result.text)
        XCTAssertTrue(note.transcription?.lowercased().contains("audio source") == true)
        XCTAssertNil(note.sourceURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("Recordings").path))
    }
    @MainActor func testSummaryAndAutomaticTitleUsingSimulatorAppleModel() async throws {
        #if targetEnvironment(simulator)
        let previousLanguage = UserDefaults.standard.string(forKey: "transcriptionLanguage")
        UserDefaults.standard.set("en-US", forKey: "transcriptionLanguage")
        defer {
            if let previousLanguage { UserDefaults.standard.set(previousLanguage, forKey: "transcriptionLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "transcriptionLanguage") }
        }
        let locale = Locale(identifier: "en-US")
        if let reason = LocalSummary.readiness(locale: locale) {
            let diagnostics = XCTAttachment(string: reason)
            diagnostics.name = "Actual simulator summary readiness"; diagnostics.lifetime = .keepAlways; add(diagnostics)
            print("SIMULATOR_SUMMARY: \(reason)")
            throw XCTSkip("Apple summary model unavailable in Simulator: \(reason)")
        }
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let recorder = LiveTranscriptionManager(store: store)
        let note = try recorder.createNote(text: "We agreed to keep recordings offline. Maya will test the microphone and Sam will verify the summary templates.", title: "Untitled")
        recorder.summarize(note, template: .auto)
        for _ in 0..<1200 {
            if recorder.summaryNoteID == nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        if recorder.summaryNoteID != nil { recorder.cancelProcessing(); XCTFail("Summary did not finish within 60 seconds") }
        XCTAssertNil(recorder.errorMessage)
        XCTAssertTrue(Note.isMeaningfulSummaryText(note.summary))
        XCTAssertNotEqual(note.title, "Untitled")
        XCTAssertEqual(note.summaryType, "default-summary")
        #else
        throw XCTSkip("This acceptance check targets Simulator")
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
private actor TranscriptionTestGate {
    private var entered = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuations: [CheckedContinuation<Void, Never>] = []
    func hold() async {
        entered = true
        arrivalContinuations.forEach { $0.resume() }; arrivalContinuations.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }
    func waitUntilHeld() async {
        if entered { return }
        await withCheckedContinuation { arrivalContinuations.append($0) }
    }
    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
}

@MainActor private final class LifecycleTestSpeech: MobileSpeechSession {
    var snapshot: (@Sendable (LocalTranscript) async -> Void)?
    var final = LocalTranscript()
    var finishGate: TranscriptionTestGate?
    var finishError: Error?
    var finishCount = 0
    var cancelCount = 0
    nonisolated func append(_ data: Data, sampleRate: Double) {}
    @MainActor func finish() async throws -> LocalTranscript {
        finishCount += 1
        if let finishGate { await finishGate.hold() }
        if let finishError { throw finishError }
        return final
    }
    @MainActor func cancel() async { cancelCount += 1 }
    func publish(_ text: String, start: Double = 0, final: Bool = false) async {
        var value = LocalTranscript()
        value.accept(text: text, start: start, end: start + 1, final: final)
        await snapshot?(value)
        // Production intentionally coalesces live text/checkpoints to 4 Hz.
        try? await Task.sleep(for: .milliseconds(275))
    }
}

extension Jotley_iOSTests {
    @MainActor @Test func stoppingDrainsFinalWordsAndRejectsLateSnapshots() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote()
        let session = LifecycleTestSpeech()
        manager.simulatedSpeechStart = { snapshot in session.snapshot = snapshot; return session }
        await manager.startTranscription(note: note)
        await session.publish("Provisional words")
        session.final.accept(text: "Final words before Stop.", start: 0, end: 1, final: true)
        await manager.stopTranscription()
        #expect(!manager.isTranscribing && !manager.busy && manager.activeNoteID == nil && manager.canStart)
        #expect(session.finishCount == 1 && session.cancelCount == 0)
        #expect(note.transcription == "Final words before Stop.")
        #expect(manager.audioLevel == 0)
        await session.publish("Late words after Stop")
        #expect(note.transcription == "Final words before Stop.")
        #expect(manager.liveTranscript == "Final words before Stop.")
        #expect(manager.liveUtterances.map(\.text) == ["Final words before Stop."])
        store.context.refresh(note, mergeChanges: false)
        #expect(note.transcription == "Final words before Stop.")
    }

    @MainActor @Test func simultaneousStopRequestsWaitForOneFinalization() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote()
        let session = LifecycleTestSpeech(), gate = TranscriptionTestGate()
        session.finishGate = gate
        session.final.accept(text: "Saved once.", start: 0, end: 1, final: true)
        manager.simulatedSpeechStart = { snapshot in session.snapshot = snapshot; return session }
        await manager.startTranscription(note: note)
        var firstFinished = false, secondRequested = false, secondFinished = false
        let first = Task { await manager.stopTranscription(); firstFinished = true }
        await gate.waitUntilHeld()
        let second = Task { secondRequested = true; await manager.stopTranscription(); secondFinished = true }
        while !secondRequested { await Task.yield() }
        #expect(!firstFinished && !secondFinished && manager.busy && !manager.canStart)
        await session.publish("Queued callback during finalization")
        #expect(note.transcription != "Queued callback during finalization")
        await gate.release()
        await first.value; await second.value
        #expect(firstFinished && secondFinished && session.finishCount == 1)
        #expect(note.transcription == "Saved once." && manager.canStart)
    }

    @MainActor @Test func closeDuringSpeechPreparationWaitsAndNeverOpensMicrophone() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote(text: "Existing words.")
        let session = LifecycleTestSpeech(), gate = TranscriptionTestGate()
        manager.simulatedSpeechStart = { snapshot in
            session.snapshot = snapshot
            await gate.hold()
            return session
        }
        let start = Task { await manager.startTranscription(note: note) }
        await gate.waitUntilHeld()
        var closeRequested = false, closeFinished = false
        let close = Task { closeRequested = true; await manager.stopTranscription(); closeFinished = true }
        while !closeRequested { await Task.yield() }
        #expect(!closeFinished && manager.busy)
        await gate.release()
        await start.value; await close.value
        #expect(closeFinished && !manager.busy && !manager.isTranscribing && manager.activeNoteID == nil)
        #expect(manager.transcriptionDuration == 0 && session.cancelCount == 1 && session.finishCount == 0)
        #expect(note.transcription == "Existing words." && manager.errorMessage == nil && manager.canStart)
        await session.publish("After cancelled preparation")
        #expect(note.transcription == "Existing words.")
    }

    @MainActor @Test func pausedStopAndContinuationFenceEarlierSession() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote()
        let first = LifecycleTestSpeech(), second = LifecycleTestSpeech()
        first.final.accept(text: "First session.", start: 0, end: 4, final: true)
        second.final.accept(text: "Continued words.", start: 0, end: 3, final: true)
        manager.simulatedSpeechStart = { snapshot in first.snapshot = snapshot; return first }
        await manager.startTranscription(note: note)
        manager.pauseTranscription()
        #expect(manager.transcriptionState == .paused)
        await manager.stopTranscription()
        manager.simulatedSpeechStart = { snapshot in second.snapshot = snapshot; return second }
        await manager.startTranscription(note: note)
        await first.publish("Old session must not overwrite continuation")
        #expect(note.transcription == "First session.")
        await second.publish("New words", start: 0)
        #expect(manager.liveUtterances.map(\.start) == [0, 4])
        manager.pauseTranscription(); await manager.resumeTranscription()
        await manager.stopTranscription()
        #expect(note.transcription == "First session. Continued words.")
        // Saved cards use the existing Mac-style short-utterance coalescing.
        #expect(note.transcriptUtterances.map(\.text).joined(separator: " ") == "First session. Continued words.")
        #expect(note.transcriptUtterances.first?.start == 0)
        #expect(note.transcriptUtterances.last?.end == 7)
        await second.publish("Late continued words")
        #expect(note.transcription == "First session. Continued words.")
    }

    @MainActor @Test func closeDuringResumeWaitsForMicrophoneTransition() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote()
        let session = LifecycleTestSpeech(), gate = TranscriptionTestGate()
        session.final.accept(text: "Words before resuming.", start: 0, end: 1, final: true)
        manager.simulatedSpeechStart = { snapshot in session.snapshot = snapshot; return session }
        await manager.startTranscription(note: note)
        manager.pauseTranscription()
        manager.simulatedCaptureStart = { await gate.hold() }
        let resume = Task { await manager.resumeTranscription() }
        await gate.waitUntilHeld()
        var closeRequested = false, closeFinished = false
        let close = Task { closeRequested = true; await manager.stopTranscription(); closeFinished = true }
        while !closeRequested { await Task.yield() }
        #expect(manager.busy && !closeFinished)
        await gate.release()
        await resume.value; await close.value
        #expect(closeFinished && manager.canStart && !manager.isTranscribing && manager.activeNoteID == nil)
        #expect(note.transcription == "Words before resuming." && session.finishCount == 1)
        await session.publish("Late words after interrupted Resume")
        #expect(note.transcription == "Words before resuming.")
    }

    @MainActor @Test func failedFinalizationStopsAndPreservesCheckpointedWords() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote()
        let session = LifecycleTestSpeech()
        session.finishError = LocalError.message("Test finalization failure")
        manager.simulatedSpeechStart = { snapshot in session.snapshot = snapshot; return session }
        await manager.startTranscription(note: note)
        await session.publish("Keep the received words.")
        await manager.stopTranscription()
        #expect(!manager.isTranscribing && manager.activeNoteID == nil && manager.canStart)
        #expect(manager.errorMessage?.contains("Test finalization failure") == true)
        #expect(note.transcription == "Keep the received words.")
        await session.publish("Must be rejected")
        #expect(note.transcription == "Keep the received words.")
    }

    @MainActor @Test func liveCardsKeepIdentityWhenTentativeWordsBecomeFinal() {
        let checkpoint = MobileTranscriptCheckpoint(baseText: "", baseUtterances: [], offset: 12)
        var value = LocalTranscript()
        value.accept(text: "First card.", start: 0, end: 2, final: true)
        value.accept(text: "Second…", start: 3, end: 4, final: false)
        let initial = checkpoint.utterances(for: value)
        value.accept(text: "Second card.", start: 3, end: 5, final: true)
        let final = checkpoint.utterances(for: value)
        #expect(initial.map(\.id) == final.map(\.id))
        #expect(final.map(\.start) == [12, 15] && final.map(\.end) == [14, 17])
        #expect(initial.last?.isInterim == true && final.last?.isInterim == false)
        #expect(final.map(\.text) == ["First card.", "Second card."])
    }

    @Test func waveformRevealsQuietInputAndRetainsLoudInputHeadroom() {
        let samples: [Float] = [0, 0.001, 0.005, 0.01, 0.03, 0.1, 0.3, 0.6, 0.9, 1]
        let levels = samples.map(LiveWaveformResponse.level)
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $0 < $1 })
        #expect(LiveWaveformResponse.level(for: 0.01) > 0.09)
        #expect(LiveWaveformResponse.level(for: 0.9) < LiveWaveformResponse.level(for: 1))
        #expect(LiveWaveformResponse.level(for: 1) < 0.93)
        #expect(LiveWaveformResponse.level(for: .nan) == 0.04)
        #expect(LiveWaveformResponse.level(for: -.infinity) == 0.04)
        #expect(LiveWaveformResponse.level(for: -1) == 0.04)
    }
}
#endif


private actor SummaryTestLog {
    var limits: [Int] = []
    var snapshots: [String] = []
    var progress: [LocalSummaryProgress] = []
    var checkpoint: LocalSummaryCheckpoint?
    var sources: [String] = []
    func save(_ value: LocalSummaryCheckpoint) { checkpoint = value }
    func visit(_ text: String) { sources.append(text) }
    func recordProgress(_ value: LocalSummaryProgress) { progress.append(value) }
    func record(limit: Int) { limits.append(limit) }
    func publish(_ text: String) { snapshots.append(text) }
}

extension Jotley_iOSTests {
    @Test func longSourceProducesOneFinalSummaryInsteadOfAppendingPartSummaries() async throws {
        let log = SummaryTestLog()
        let source = String(repeating: "Maya will review Friday. Sam owns testing. ", count: 180)
        let result = try await LocalSummary.run(source, template: .auto, infer: { _, _, limit, update in
            await log.record(limit: limit)
            if limit == 128 {
                await update("Internal extraction must stay hidden")
                return "Maya reviews Friday. Sam tests."
            }
            await update("One final summary")
            return "One final summary: Maya reviews Friday; Sam tests."
        }, progress: { await log.recordProgress($0) }, snapshot: { await log.publish($0) })
        let progress = await log.progress
        #expect(progress.first == .preparing && progress.last == .writing)
        let count = LocalSummary.chunks(source).count
        #expect(progress.contains(.reading(completed: 0, total: count, pass: 0)))
        #expect(progress.contains(.reading(completed: count, total: count, pass: 0)))
        #expect(LocalSummaryProgress.reading(completed: 2, total: 4, pass: 0).fraction == 0.5)
        let limits = await log.limits, snapshots = await log.snapshots
        #expect(limits.filter { $0 == 512 }.count == 1)
        #expect(limits.filter { $0 == 128 }.count > 1)
        #expect(snapshots == ["One final summary"])
        #expect(!result.contains("Part") && result == "One final summary: Maya reviews Friday; Sam tests.")
    }
    @Test func nonshrinkingSummaryReductionStopsWithoutRetryingForever() async {
        let log = SummaryTestLog()
        do {
            _ = try await LocalSummary.run(String(repeating: "Long source words. ", count: 250), template: .auto,
                infer: { text, _, limit, _ in await log.record(limit: limit); return text }, snapshot: { _ in })
            Issue.record("A nonshrinking reduction must stop")
        } catch { #expect(error.localizedDescription.contains("Generation stopped")) }
        #expect(await log.limits.count == 2)
    }
    @Test func repetitionGuardKeepsOneCopyAndNormalRecurringWords() {
        let sentence = "Maya will review the final milestones with Sam on Friday."
        let repeated = "## Decisions\n\n" + Array(repeating: sentence, count: 3).joined(separator: "\n\n")
        #expect(LocalSummary.withoutRepeatingTail(repeated) == "## Decisions\n\n" + sentence)
        #expect(LocalSummary.withoutRepeatingTail("Maya reviews Friday. Sam reviews Monday. Maya and Sam review together.") == nil)
        #expect(LocalSummary.withoutRepeatingTail(String(repeating: "word ", count: 40)) == nil)
    }
    @Test func boundedSummaryStopsStalledWorkAndPropagatesCancellation() async {
        do {
            _ = try await LocalSummary.bounded({ try await Task.sleep(for: .seconds(60)); return "Must never finish" }, timeout: .milliseconds(25))
            Issue.record("A stalled summary must time out")
        } catch { #expect(error.localizedDescription.contains("too long")) }
        let task = Task { try await LocalSummary.bounded { try await Task.sleep(for: .seconds(60)); return "Must not save" } }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled summaries must throw") }
        catch { #expect(error is CancellationError) }
    }
    @MainActor @Test func waveformAnimatesNativeLayersWithoutPublishingSwiftUIFrames() {
        let view = LiveWaveformLayerView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        view.update(levelProvider: { 0.3 }, listening: true, paused: false, color: .purple)
        view.layoutIfNeeded(); view.advanceWaveform()
        let layers = view.layer.sublayers ?? []
        #expect(layers.count == 50)
        #expect(layers.allSatisfy { $0.animation(forKey: "liveLevel") is CABasicAnimation })
        #expect((layers.last?.bounds.height ?? 0) > 6)
        view.update(levelProvider: { 0 }, listening: false, paused: false, color: .gray)
        view.layoutIfNeeded()
        #expect(layers.allSatisfy { $0.animationKeys()?.isEmpty != false })
        #expect(layers.allSatisfy { abs($0.bounds.height - 6) < 0.01 })
    }
}

#if DEBUG && targetEnvironment(simulator)
extension Jotley_iOSTests {
    @MainActor @Test func summaryRunsOnceForRepeatedTapsAndReturnsToIdleAfterSaving() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote(text: "Maya reviews Friday.", title: "Meeting")
        var calls = 0
        manager.simulatedSummaryGeneration = { update in
            calls += 1
            await update("One summary in progress")
            try await Task.sleep(for: .milliseconds(50))
            return "One completed summary."
        }
        manager.summarize(note, template: .auto)
        manager.summarize(note, template: .auto)
        try await Task.sleep(for: .milliseconds(200))
        #expect(calls == 1 && note.summary == "One completed summary.")
        #expect(manager.summaryNoteID == nil && manager.summaryPreview.isEmpty && manager.canStart)
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls == 1)
    }
}
#endif

extension SimulatorModelAcceptanceTests {
    @MainActor func testActualLongSourceSavesOneConsolidatedSummaryAndFinishes() async throws {
        let locale = Locale(identifier: "en-US")
        if let reason = LocalSummary.readiness(locale: locale) { throw XCTSkip(reason) }
        let paragraphs = (1...64).map { index in
            "Review \(index): Maya owns accessibility testing for the native notes app. Sam will check that transcripts remain on the device. The team agreed to review the completed checklist on Friday and keep all features free."
        }.joined(separator: "\n\n")
        XCTAssertGreaterThan(LocalSummary.chunks(paragraphs).count, 1)
        let log = SummaryTestLog()
        let began = Date()
        let result = try await LocalSummary.generate(paragraphs, template: .concise, locale: locale,
            progress: { await log.recordProgress($0) }, snapshot: { await log.publish($0) })
        let progress = await log.progress, snapshots = await log.snapshots
        XCTAssertTrue(progress.contains(.preparing))
        XCTAssertEqual(progress.last, .writing)
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertEqual(snapshots.last, result)
        XCTAssertTrue(result.localizedCaseInsensitiveContains("Maya"))
        let trace = XCTAttachment(string: "Model context: \(SystemLanguageModel.default.contextSize) tokens\nElapsed: \(Date().timeIntervalSince(began)) seconds\nProgress: \(progress)\nLive snapshots: \(snapshots.count)\nFirst live text: \(snapshots.first ?? "")")
        trace.name = "Actual Apple model preparation and live summary trace"; trace.lifetime = .keepAlways; add(trace)
        XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(result.contains("## Part "))
        XCTAssertNil(LocalSummary.withoutRepeatingTail(result))
        let attachment = XCTAttachment(string: result)
        attachment.name = "Actual Apple model consolidated a long note once"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

#if DEBUG && targetEnvironment(simulator)
extension Jotley_iOSTests {
    @Test func tokenPackingKeepsEveryByteAndUsesLargerCompleteSections() async throws {
        let input = String(repeating: "Maya has café notes. 漢字🙂 ", count: 600)
        let parts = try await LocalSummary.packedSections(input, fits: { $0.utf8.count <= 9000 })
        #expect(parts.joined() == input)
        #expect(parts.allSatisfy { $0.utf8.count <= 9000 })
        #expect(parts.count < LocalSummary.chunks(input).count)
        let dense = try await LocalSummary.packedSections(input, fits: { $0.utf8.count <= 700 })
        #expect(dense.joined() == input && dense.allSatisfy { $0.utf8.count <= 700 })
    }
    @Test func summaryRecoverySkipsCompletedSectionsAndKeepsSourceOrder() async throws {
        let input = (1...8).map { "Section \($0). " + String(repeating: "Evidence words. ", count: 200) }.joined()
        let log = SummaryTestLog()
        let infer: LocalSummary.Inference = { source, _, limit, update in
            await log.visit(source)
            if limit == 128 { return "Reviewed: " + String(source.prefix(30)) }
            await update("Final summary")
            return "Final summary"
        }
        do {
            _ = try await LocalSummary.run(input, template: .auto, infer: infer, checkpoint: { state in
                await log.save(state)
                if state.facts.count == 2 { throw CancellationError() }
            }, snapshot: { _ in })
            Issue.record("Expected a system interruption")
        } catch is CancellationError { }
        let saved = try #require(await log.checkpoint)
        #expect(saved.facts.count == 2)
        let encoded = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode(LocalSummaryCheckpoint.self, from: encoded)
        let result = try await LocalSummary.run(input, template: .auto, infer: infer, resuming: restored,
            checkpoint: { await log.save($0) }, snapshot: { _ in })
        let visited = await log.sources
        #expect(Array(visited.dropLast()) == LocalSummary.chunks(input))
        #expect(result == "Final summary")
        // Title recovery uses the finished result without running inference again.
        let completed = try #require(await log.checkpoint)
        _ = try await LocalSummary.run(input, template: .auto, infer: { _, _, _, _ in
            Issue.record("Completed summary must not be regenerated for title recovery"); return "Unexpected"
        }, resuming: completed, snapshot: { _ in })
    }
    @MainActor @Test func leavingNoteDoesNotCancelSummaryAndExplicitCancelRemovesRecovery() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote(text: "Maya reviews Friday.", title: "Review")
        note.summary = "Original summary"
        manager.simulatedSummaryGeneration = { update in
            await update("New summary in progress")
            try await Task.sleep(for: .milliseconds(150))
            return "Completed new summary"
        }
        manager.summarize(note, template: .auto)
        manager.saveEdits() // The exact app background lifecycle action.
        #expect(FileManager.default.fileExists(atPath: try #require(manager.summaryRecoveryURL).path))
        try await Task.sleep(for: .milliseconds(300))
        #expect(note.summary == "Completed new summary" && manager.summaryNoteID == nil)
        #expect(!FileManager.default.fileExists(atPath: try #require(manager.summaryRecoveryURL).path))
        manager.simulatedSummaryGeneration = { _ in try await Task.sleep(for: .seconds(5)); return "Cancelled" }
        manager.summarize(note, template: .auto)
        manager.cancelProcessing()
        try await Task.sleep(for: .milliseconds(100))
        #expect(note.summary == "Completed new summary" && manager.summaryNoteID == nil)
        #expect(!FileManager.default.fileExists(atPath: try #require(manager.summaryRecoveryURL).path))
    }
    @MainActor @Test func pendingSummaryResumesFromDiskWithoutReplacingExistingNoteUntilComplete() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try #require(store.create(title: "Existing title", text: "Maya reviews Friday.") as? Note)
        note.summary = "Original summary"
        try store.save()
        var checkpoint = LocalSummaryCheckpoint(input: note.transcription ?? "", template: .auto)
        checkpoint.result = "Recovered completed summary"
        let job = MobileSummaryJob(noteID: try #require(note.id), templateKey: LocalSummaryTemplate.auto.key,
            localeIdentifier: "en-US", checkpoint: checkpoint)
        let url = store.root.appendingPathComponent("SummaryGeneration.json")
        try JSONEncoder().encode(job).write(to: url, options: .atomic)
        let manager = LiveTranscriptionManager(store: store)
        #expect(note.summary == "Original summary")
        manager.resumePendingSummary(applicationState: .active)
        try await Task.sleep(for: .milliseconds(250))
        #expect(note.summary == "Recovered completed summary")
        #expect(note.title == "Existing title" && !FileManager.default.fileExists(atPath: url.path))
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
extension Jotley_iOSTests {
    @MainActor @Test func systemExpirationKeepsRecoveryAndResumesInsteadOfCancellingTheJob() async throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let manager = LiveTranscriptionManager(store: store)
        let note = try manager.createNote(text: "Maya reviews Friday.", title: "Review")
        note.summary = "Original summary"
        var calls = 0
        manager.simulatedSummaryGeneration = { update in
            calls += 1
            if calls == 1 { try await Task.sleep(for: .seconds(5)) }
            try await Task.sleep(for: .milliseconds(100))
            await update("Summary resumed")
            return "Summary resumed"
        }
        manager.summarize(note, template: .auto)
        try await Task.sleep(for: .milliseconds(20))
        let url = try #require(manager.summaryRecoveryURL)
        // Simulator has no data-protection attribute. Verify the durable job,
        // not a filesystem-encryption property that requires physical hardware.
        let saved = try JSONDecoder().decode(MobileSummaryJob.self, from: Data(contentsOf: url))
        #expect(saved.noteID == note.id && saved.checkpoint.input == note.transcription)
        manager.pauseSummaryForSystem()
        #expect(FileManager.default.fileExists(atPath: url.path) && note.summary == "Original summary")
        try await Task.sleep(for: .milliseconds(30))
        manager.resumePendingSummary(applicationState: .active)
        try await Task.sleep(for: .milliseconds(250))
        #expect(calls == 2 && note.summary == "Summary resumed" && manager.summaryNoteID == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
#endif
