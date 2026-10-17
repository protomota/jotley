import XCTest
import AVFoundation
import CoreData
import CloudKit
import Speech
@testable import jotley

final class LocalCoreTests: XCTestCase {
    func testAutoTagsReuseBucketsAndLimitDistinctTopics() {
        let library = [LocalTagCandidate(name: "AI", usageCount: 40), LocalTagCandidate(name: "Design", usageCount: 20), LocalTagCandidate(name: "Project-Planning", usageCount: 5)]
        XCTAssertEqual(LocalNoteTags.resolvedNames(["artificial intelligence", "AI Tools", "ai", "Design", "Project Planning", "Research", "Work", "Extra"], library: library),
                       ["AI", "Design", "Project-Planning", "Research", "Work"])
        XCTAssertEqual(LocalNoteTags.resolvedNames(["###", "  ", "A sentence with far too many words for a topic", "design"], library: library), ["Design"])
        let many = (0..<500).map { LocalTagCandidate(name: "Topic-\($0)", usageCount: 500 - $0) }
            + [LocalTagCandidate(name: "Gardening", usageCount: 1)]
        let candidates = LocalNoteTags.candidates(for: "Gardening plans", library: many, byteLimit: 400)
        XCTAssertEqual(candidates.first, "Gardening")
        XCTAssertLessThanOrEqual(candidates.reduce(0) { $0 + $1.utf8.count + 4 }, 400)
        XCTAssertEqual(Set(candidates.map(LocalNoteTags.key)).count, candidates.count)
    }

    @MainActor func testSummaryTagsReplaceRelationshipsReuseEntitiesAndKeepOtherNotes() throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try store.create(title: "Summary", text: "AI and design")
        let other = try store.create(title: "Other", text: "AI")
        try store.saveNoteChanges(other, values: [:], replacingTags: ["AI", "Design"])
        try store.saveNoteChanges(note, values: [:], replacingTags: ["Outdated", "Temporary"])
        let before = (other.value(forKey: "tags") as? Set<NSManagedObject>) ?? []
        let ai = try XCTUnwrap(before.first { $0.text("name") == "AI" })
        try store.saveNoteChanges(note, values: ["summary": "Final summary"], replacingTags: ["Artificial Intelligence", "AI Tools", "Design", "Research", "Planning", "Meetings", "Overflow"])
        let tags = (note.value(forKey: "tags") as? Set<NSManagedObject>) ?? []
        XCTAssertEqual(tags.count, 5)
        XCTAssertTrue(tags.contains(ai))
        XCTAssertFalse(tags.contains { ["Outdated", "Temporary", "Overflow"].contains($0.text("name")) })
        XCTAssertEqual((other.value(forKey: "tags") as? Set<NSManagedObject>), before)
        XCTAssertEqual(try store.tagLibrary().filter { LocalNoteTags.key($0.name) == "ai" }.count, 1)
        // A tagging failure supplies nil and preserves the old relationships.
        try store.saveNoteChanges(note, values: ["summary": "Another summary"], replacingTags: nil)
        XCTAssertEqual((note.value(forKey: "tags") as? Set<NSManagedObject>), tags)
        try store.saveNoteChanges(note, values: [:], replacingTags: [])
        XCTAssertEqual((note.value(forKey: "tags") as? NSSet)?.count, 0)
        XCTAssertEqual((other.value(forKey: "tags") as? Set<NSManagedObject>), before)
    }

    @MainActor func testRejectedSummaryRestoresTagsWithoutLeavingNewEntities() throws {
        let seed = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let model = try XCTUnwrap(seed.container.managedObjectModel.copy() as? NSManagedObjectModel)
        model.entitiesByName["Note"]?.managedObjectClassName = NSStringFromClass(GeneratedContentRefusedNote.self)
        let store = try SharedPersistenceController(inMemory: true, model: model)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try store.create(title: "Keep tags", text: "Original")
        try store.saveNoteChanges(note, values: ["summary": "Original summary"], replacingTags: ["Existing"])
        let other = try store.create(title: "Other")
        other.setValue("Unrelated unsaved edit", forKey: "title")
        XCTAssertThrowsError(try store.saveNoteChanges(note, values: ["summary": "Rejected output"], replacingTags: ["New tag"]))
        XCTAssertEqual(note.text("summary"), "Original summary")
        XCTAssertEqual((note.value(forKey: "tags") as? Set<NSManagedObject>)?.map { $0.text("name") }, ["Existing"])
        XCTAssertEqual(try store.tagLibrary().map(\.name), ["Existing"])
        XCTAssertEqual(other.text("title"), "Unrelated unsaved edit")
    }

    func testInstalledTagModelReusesExistingBroadBuckets() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_TAG_TESTS"] == "1" else { throw XCTSkip("Installed Apple tag model test is opt-in") }
        let locale = Locale(identifier: "en-US")
        if let reason = LocalSummary.readiness(locale: locale) { throw XCTSkip(reason) }
        let library = [LocalTagCandidate(name: "AI", usageCount: 50), LocalTagCandidate(name: "Design", usageCount: 20), LocalTagCandidate(name: "Gardening", usageCount: 5)]
        let tags = try await LocalNoteTags.generate(from: "The design team adopted artificial intelligence tools. Designers use generative AI to explore interface layouts and prototype product ideas.", library: library, locale: locale)
        XCTAssertTrue(tags.contains("AI"), tags.description)
        XCTAssertTrue(tags.contains("Design"), tags.description)
        XCTAssertFalse(tags.contains("Gardening"), tags.description)
        XCTAssertLessThanOrEqual(tags.count, 5)
        XCTAssertEqual(Set(tags.map(LocalNoteTags.key)).count, tags.count)
        let cancelled = Task { try await LocalNoteTags.generate(from: "AI", library: library, locale: locale) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled tagging must not finish") } catch is CancellationError { }
        print("Verified installed Apple model tags:", tags)
    }

    @MainActor func testChatHistoryRoundTrip() throws {
        let store = try SharedPersistenceController(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try store.create(title: "Chat", text: "Mina ships Friday")
        let id = try XCTUnwrap(note.localNoteID)
        let question = LocalChatMessage(role: "user", content: "Who ships?")
        let answer = LocalChatMessage(role: "assistant", content: "Mina.")
        try store.saveChatMessage(question, noteID: id)
        try store.saveChatMessage(answer, noteID: id)
        XCTAssertEqual(try store.chatMessages(noteID: id).map(\.id), [question.id, answer.id])
        store.context.reset()
        XCTAssertEqual(try store.chatMessages(noteID: id).map(\.id), [question.id, answer.id])
        let saved = try XCTUnwrap(store.notes().first)
        try store.deleteNoteAndAudio(saved)
        XCTAssertTrue(try store.chatMessages(noteID: id).isEmpty)
    }

    func testInstalledAskAIAnswersFromNoteAndCancelsWithoutCloudFallback() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_CHAT_TESTS"] == "1" else { throw XCTSkip("Installed Apple model test is opt-in") }
        let locale = Locale(identifier: "en-US")
        if let reason = LocalSummary.readiness(locale: locale) { throw XCTSkip(reason) }
        let answer = try await LocalNoteChat.answer(source: "Mina is responsible for the launch. The team ships Friday.",
            question: "Who is responsible for launch?", history: [], locale: locale) { _ in }
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("Mina"), answer)
        let cancelled = Task {
            try await LocalNoteChat.answer(source: "Mina ships Friday.", question: "When?", history: [], locale: locale) { _ in }
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled answers must not finish") }
        catch is CancellationError { }
    }

    func testOriginalAndMigrationTemplateKeysRemainUsableOffline() {
        let originals = ["default-summary", "lecture", "meetings/general", "meetings/1-1",
            "meetings/all-hands", "meetings/brainstorming", "meetings/networking",
            "meetings/project-kickoff", "meetings/sprint-planning", "meetings/stand-up",
            "meetings/weekly-project-status"]
        for key in originals {
            let template = LocalSummaryTemplate.resolve(key)
            XCTAssertEqual(template.key, key, "An original note must retain its template")
            XCTAssertFalse(template.prompt.isEmpty)
        }
        XCTAssertEqual(LocalSummaryTemplate.resolve(nil), .auto)
        XCTAssertEqual(LocalSummaryTemplate.resolve("Meeting"), .meeting)
        XCTAssertEqual(LocalSummaryTemplate.resolve("Concise"), .concise)
        XCTAssertEqual(LocalSummaryTemplate.resolve("Study"), .study)
        XCTAssertNotEqual(LocalSummaryTemplate.auto.prompt, LocalSummaryTemplate.concise.prompt)
        XCTAssertFalse(LocalSummaryTemplate.allCases.contains { $0.key == "youtube" })
    }

    @MainActor func testActiveRecordingCannotBeDeletedOrReleasedByAnotherOwner() throws {
        let root = try temporaryDirectory()
        let store = try SharedPersistenceController(root: root)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: store.context)
        let id = UUID(); note.setValue(id, forKey: "id"); note.setValue("Active", forKey: "title")
        let lease = try store.beginRecording(note)
        XCTAssertFalse(note.objectID.isTemporaryID)
        try store.save()
        let other = try store.create(title: "Other")
        let directory = root.appendingPathComponent("Recordings/\(id.uuidString)/segment")
        let writer = try DurableAudioWriter(directory: directory, noteID: id, sampleRate: 16000)
        try writer.append(Data(repeating: 0, count: 400))
        XCTAssertThrowsError(try store.deleteNoteAndAudio(note))
        XCTAssertThrowsError(try store.beginRecording(other))
        store.endRecording(lease: UUID())
        XCTAssertThrowsError(try store.deleteNoteAndAudio(note))
        XCTAssertEqual(try store.notes().count, 2)
        XCTAssertFalse(note.isDeleted)
        XCTAssertEqual(try DurableAudioWriter.frameCount(at: directory), 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("DeletedRecordings/\(id.uuidString)").path))
        // Unrelated notes remain deletable while the recording is protected.
        try store.deleteNoteAndAudio(other)
        try writer.append(Data(repeating: 0, count: 400)); try writer.close()
        store.endRecording(lease: lease)
        let next = try store.create(title: "Next")
        let nextLease = try store.beginRecording(next)
        store.endRecording(lease: lease) // A stale owner cannot release the next session.
        XCTAssertThrowsError(try store.deleteNoteAndAudio(next))
        try store.deleteNoteAndAudio(note)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        store.endRecording(lease: nextLease)
        try store.deleteNoteAndAudio(next)
        XCTAssertThrowsError(try store.beginRecording(next))
        XCTAssertTrue(try store.notes().isEmpty)
    }
    func testRecordedDurationIncludesSilentSegmentsAndRetainsCorruptAudio() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(try DurableAudioWriter.recordedDuration(in: root.appendingPathComponent("missing")), 0)
        let id = UUID()
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        for (segment, rate, seconds) in [(first, 16000.0, 10.0), (second, 48000.0, 3.25)] {
            let writer = try DurableAudioWriter(directory: segment, noteID: id, sampleRate: rate)
            try writer.append(Data(repeating: 0, count: Int(rate * seconds) * 4))
            try writer.close()
        }
        // A crash's partial final sample cannot lengthen the timeline.
        let raw = second.appendingPathComponent("audio.float32")
        let handle = try FileHandle(forWritingTo: raw)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([1, 2])); try handle.close()
        try Data([0]).write(to: root.appendingPathComponent("unrelated.txt"))
        XCTAssertEqual(try DurableAudioWriter.recordedDuration(in: root), 13.25, accuracy: 0.0001)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.appendingPathComponent("audio.caf").path))
        let original = try Data(contentsOf: raw)
        var manifest = try DurableAudioWriter.manifest(at: second)
        manifest.sampleRate = 0
        try JSONEncoder().encode(manifest).write(to: second.appendingPathComponent("recording.json"), options: .atomic)
        XCTAssertThrowsError(try DurableAudioWriter.recordedDuration(in: root))
        XCTAssertEqual(try Data(contentsOf: raw), original)
    }
    func testCloudSyncDefaultsOnWithConfiguredIdentifierAndHonorsOptOut() throws {
        let suite = "JotleySyncTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let info = [NoteSyncMode.containerInfoKey: "iCloud.org.example.JotleyTests"]
        XCTAssertEqual(NoteSyncMode.application(info: info, defaults: defaults), .privateICloud(containerIdentifier: "iCloud.org.example.JotleyTests"))
        XCTAssertNil(defaults.object(forKey: NoteSyncMode.preferenceKey))
        defaults.set(true, forKey: NoteSyncMode.preferenceKey)
        XCTAssertEqual(NoteSyncMode.application(info: [:], defaults: defaults), .localOnly)
        XCTAssertEqual(NoteSyncMode.application(info: [NoteSyncMode.containerInfoKey: "https://example.com"], defaults: defaults), .localOnly)
        XCTAssertEqual(NoteSyncMode.application(info: info, defaults: defaults), .privateICloud(containerIdentifier: "iCloud.org.example.JotleyTests"))
        defaults.set(false, forKey: NoteSyncMode.preferenceKey)
        XCTAssertEqual(NoteSyncMode.application(info: info, defaults: defaults), .localOnly)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(NoteSyncMode.application(info: info, defaults: reopened), .localOnly)
        defaults.removeObject(forKey: NoteSyncMode.preferenceKey)
        XCTAssertEqual(NoteSyncMode.application(info: info, defaults: defaults), .privateICloud(containerIdentifier: "iCloud.org.example.JotleyTests"))
    }
    @MainActor
    func testCloudSyncConfigurationIsPrivateAndCannotMirrorPreviewStores() throws {
        let mode = NoteSyncMode.privateICloud(containerIdentifier: "iCloud.org.example.JotleyTests")
        let url = URL(fileURLWithPath: "/tmp/JotleySyncConfiguration.sqlite")
        let description = try mode.storeDescription(at: url, inMemory: false)
        XCTAssertEqual(description.cloudKitContainerOptions?.containerIdentifier, "iCloud.org.example.JotleyTests")
        XCTAssertEqual(description.cloudKitContainerOptions?.databaseScope, .private)
        XCTAssertEqual(description.options[NSPersistentHistoryTrackingKey] as? NSNumber, true)
        XCTAssertEqual(description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber, true)
        XCTAssertNil(try NoteSyncMode.localOnly.storeDescription(at: url, inMemory: false).cloudKitContainerOptions)
        XCTAssertThrowsError(try NoteSyncMode.privateICloud(containerIdentifier: "invalid").storeDescription(at: url, inMemory: false))
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = try SharedPersistenceController(root: root, inMemory: true, syncMode: mode)
        XCTAssertTrue(preview.ready)
        XCTAssertEqual(preview.syncMode, .localOnly)
        XCTAssertFalse(preview.container is NSPersistentCloudKitContainer)
        XCTAssertNil(preview.container.persistentStoreDescriptions.first?.cloudKitContainerOptions)
        _ = try preview.create(title: "Preview only")
        XCTAssertEqual(try preview.notes().count, 1)
    }
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("JotleyTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testTentativeAndFinalSpeechDoNotDuplicate() {
        var transcript = LocalTranscript()
        transcript.accept(text: "hello", start: 0, end: 1, final: false)
        transcript.accept(text: "hello world", start: 0, end: 2, final: false)
        XCTAssertEqual(transcript.displayText, "hello world")
        XCTAssertEqual(transcript.text, "")
        transcript.accept(text: "hello world", start: 0, end: 2, final: true)
        transcript.accept(text: "hello world!", start: 0, end: 2, final: true)
        XCTAssertEqual(transcript.text, "hello world!")
        XCTAssertEqual(transcript.utterances.count, 1)
        XCTAssertEqual(transcript.tentative, "")
    }
    func testLongUnicodeTranscriptChunksWithoutDroppingText() {
        let text = String(repeating: "日本語の会議。 Action: call Sam.\n", count: 2000)
        let chunks = LocalSummary.chunks(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 2400 })
        XCTAssertGreaterThan(chunks.count, 2)
    }
    func testInterruptedCaptureCanBeRecoveredWithoutClosingWriter() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try DurableAudioWriter(directory: directory, noteID: UUID(), sampleRate: 16000)
        let samples = [Float](repeating: 0.25, count: 16000)
        try writer.append(samples.withUnsafeBufferPointer { Data(buffer: $0) })
        XCTAssertFalse(try DurableAudioWriter.manifest(at: directory).complete)
        let url = try DurableAudioWriter.recover(at: directory)
        let audio = try AVAudioFile(forReading: url)
        XCTAssertEqual(audio.length, 16000)
        XCTAssertEqual(try DurableAudioWriter.frameCount(at: directory), 16000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio.float32").path))
        try writer.close()
        XCTAssertTrue(try DurableAudioWriter.manifest(at: directory).complete)
    }
    func testExistingCaptureCannotBeOverwritten() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try DurableAudioWriter(directory: directory, noteID: UUID(), sampleRate: 16000)
        try writer.append(Data(repeating: 0, count: 400))
        XCTAssertThrowsError(try DurableAudioWriter(directory: directory, noteID: UUID(), sampleRate: 16000))
        XCTAssertEqual(try DurableAudioWriter.frameCount(at: directory), 100)
        try writer.close()
    }
    @MainActor
    func testIsolatedStorePersistsAcrossRelaunchAndUsesVersionSixModel() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try SharedPersistenceController(root: root)
        XCTAssertTrue(first.ready)
        XCTAssertTrue(first.container.managedObjectModel.entitiesByName["Folder"] != nil)
        XCTAssertTrue(first.container.managedObjectModel.entitiesByName["Note"]?.attributesByName["transcriptUtterancesJSON"] != nil)
        let note = try first.create(title: "Retain", text: "Existing content")
        let id = note.localNoteID
        for store in first.container.persistentStoreCoordinator.persistentStores {
            try first.container.persistentStoreCoordinator.remove(store)
        }
        let second = try SharedPersistenceController(root: root)
        let saved = try XCTUnwrap(second.notes().first)
        XCTAssertEqual(saved.localNoteID, id)
        XCTAssertEqual(saved.text("transcription"), "Existing content")
        XCTAssertNil(second.container.persistentStoreDescriptions.first?.cloudKitContainerOptions)
        XCTAssertTrue(second.container.persistentStoreDescriptions.first!.url!.path.hasPrefix(root.path))
    }
    @MainActor
    func testCorruptStorePreservedOnLoadFailure() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("JotleyNotes.sqlite")
        let original = Data("not a database".utf8)
        try original.write(to: url)
        let store = try SharedPersistenceController(root: root)
        XCTAssertFalse(store.ready)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.create(title: "Must fail"))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    @MainActor
    func testBackgroundNoteChangesMergeAndDeletionCannotBeOverwritten() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SharedPersistenceController(root: root)
        let note = try store.create(title: "Existing", text: "Original transcript")
        let objectID = note.objectID
        let background = store.container.newBackgroundContext()
        try await background.perform {
            let imported = try background.existingObject(with: objectID)
            imported.setValue("Imported transcript", forKey: "transcription")
            imported.setValue("Imported summary", forKey: "summary")
            let folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: background)
            folder.setValue(UUID(), forKey: "id"); folder.setValue("Imported folder", forKey: "name")
            imported.setValue(folder, forKey: "folder")
            try background.save()
        }
        for _ in 0..<200 {
            if note.text("transcription") == "Imported transcript" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(note.text("transcription"), "Imported transcript")
        XCTAssertEqual(note.text("summary"), "Imported summary")
        XCTAssertEqual((note.value(forKey: "folder") as? NSManagedObject)?.text("name"), "Imported folder")
        // Preserve a local edit to a different field while another import arrives.
        note.setValue("Pending local title", forKey: "title")
        try await background.perform {
            let imported = try background.existingObject(with: objectID)
            imported.setValue("Second imported summary", forKey: "summary")
            try background.save()
        }
        for _ in 0..<200 {
            if note.text("summary") == "Second imported summary" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(note.text("summary"), "Second imported summary")
        XCTAssertEqual(note.text("title"), "Pending local title")
        try store.save()
        // A new import context reads the current row after the local title commit.
        let deletionContext = store.container.newBackgroundContext()
        try await deletionContext.perform {
            deletionContext.delete(try deletionContext.existingObject(with: objectID)); try deletionContext.save()
        }
        for _ in 0..<200 {
            if note.isDeleted || note.managedObjectContext == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(note.isDeleted || note.managedObjectContext == nil)
        XCTAssertThrowsError(try store.saveNoteChanges(note, values: ["transcription": "Late generated words"]))
        XCTAssertTrue(try store.notes().isEmpty)
        let reopened = try SharedPersistenceController(root: root)
        XCTAssertTrue(try reopened.notes().isEmpty)
    }
}

private actor LiveResultProbe {
    var snapshotCount = 0
    var text = ""
    func accept(_ value: LocalTranscript) { snapshotCount += 1; text = value.displayText }
    func count() -> Int { snapshotCount }
}

extension LocalCoreTests {
    func testUnsupportedLanguageRemainsUnavailableWithoutModelInstallation() async {
        do {
            _ = try await LocalSpeech.configuration(locale: Locale(identifier: "zxx"))
            XCTFail("A language with no linguistic content must not select a speech model")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("unavailable for the selected language"))
        }
    }

    func testSpeechSelectionDistinguishesMissingAssetsFromUnsupportedLanguage() {
        XCTAssertEqual(LocalSpeech.preferredIndex(statuses: [.supported, .installed]), 1)
        XCTAssertEqual(LocalSpeech.preferredIndex(statuses: [.installed, .installed]), 0)
        XCTAssertEqual(LocalSpeech.preferredIndex(statuses: [.supported, .supported]), 0)
        XCTAssertEqual(LocalSpeech.preferredIndex(statuses: [.unsupported, .downloading]), 1)
        XCTAssertEqual(LocalSpeech.preferredIndex(statuses: [.unsupported, .unsupported]), 0)
        XCTAssertNil(LocalSpeech.preferredIndex(statuses: []))
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(LocalSpeech.exactLocale(Locale(identifier: "en-US"), in: [locale]), locale)
        XCTAssertNil(LocalSpeech.exactLocale(Locale(identifier: "en-GB"), in: [locale]))
        let module = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
        let pending = LocalSpeech.Readiness(configuration: .init(module: module, engine: .dictation, locale: locale), status: .unsupported)
        XCTAssertTrue(pending.needsSetup, "An unready supported-locale module must remain available for explicit setup")
        XCTAssertTrue(pending.message.contains("Set Up On-Device Speech"))
        XCTAssertThrowsError(try LocalSpeech.configuration(from: pending))
        let installed = LocalSpeech.Readiness(configuration: .init(module: module, engine: .dictation, locale: locale), status: .installed)
        let selected = try? LocalSpeech.configuration(from: installed)
        XCTAssertEqual(selected?.engine, .dictation)
        XCTAssertEqual(selected?.locale, locale)
        XCTAssertTrue((selected?.module as? DictationTranscriber) === module,
                      "Recording must use the same installed configuration Settings selected")
    }

    func testExplicitSetupReusesInstalledAppleSpeech() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Opt in to exercise this host's installed speech assets.")
        }
        let locale = Locale(identifier: "en-US")
        // Require the asset first so this integration test cannot initiate a download.
        let before = try await LocalSpeech.configuration(locale: locale)
        try await LocalSpeech.setUp(locale: locale) { _ in }
        let after = try await LocalSpeech.configuration(locale: locale)
        XCTAssertEqual(before.engine, after.engine)
        XCTAssertEqual(before.locale, after.locale)
        let ready = await LocalSpeech.readiness(locale: locale)
        XCTAssertFalse(ready.needsSetup)
        XCTAssertEqual(ready.configuration?.engine, after.engine)
        XCTAssertEqual(ready.configuration?.locale, after.locale)
    }

    func testEmptySavedRecordingReturnsWithoutSpeechSetup() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try DurableAudioWriter(directory: root.appendingPathComponent("empty"), noteID: UUID(), sampleRate: 16000)
        try writer.close()
        let file = try DurableAudioWriter.audioFile(at: writer.directory)
        let before = try Data(contentsOf: file)
        let result = try await LocalSpeech.transcribe(files: [file], locale: Locale(identifier: "zxx")) { _ in
            XCTFail("An empty file must not produce a speech snapshot")
        }
        XCTAssertTrue(result.text.isEmpty && result.utterances.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    @MainActor func testInstalledModelTranscribesSavedRecordingAndAppendedSegments() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Use locally generated speech fixtures and already installed Apple assets.")
        }
        let root = try temporaryDirectory()
        let store = try SharedPersistenceController(root: root)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let note = try store.create(title: "Saved recording", text: "Previous text", noteType: "voice")
        let id = try XCTUnwrap(note.localNoteID)
        let sources: [String?] = [nil, "/tmp/jotley-local-live-speech.aiff", nil,
                                 "/tmp/jotley-local-appended-speech-48k.aiff", nil]
        var files: [URL] = [], originalAudio: [Data] = [], firstDuration = 0.0
        for (index, source) in sources.enumerated() {
            let directory = root.appendingPathComponent("Recordings/\(id.uuidString)/segment-\(index)")
            let sampleRate = index == 3 ? 48000.0 : 16000.0
            let writer = try DurableAudioWriter(directory: directory, noteID: id, sampleRate: sampleRate)
            if let source {
                let audio = try AVAudioFile(forReading: URL(fileURLWithPath: source), commonFormat: .pcmFormatFloat32, interleaved: false)
                XCTAssertEqual(audio.processingFormat.sampleRate, sampleRate)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: UInt32(audio.length)))
                try audio.read(into: buffer)
                let samples = try XCTUnwrap(buffer.floatChannelData?[0])
                try writer.append(Data(bytes: samples, count: Int(buffer.frameLength) * 4))
                if index == 1 { firstDuration = Double(audio.length) / 16000 }
            }
            try writer.close()
            let file = try DurableAudioWriter.audioFile(at: directory)
            files.append(file); originalAudio.append(try Data(contentsOf: file))
        }
        let recognition = Task { try await LocalSpeech.transcribe(files: files, locale: Locale(identifier: "en-US")) { _ in } }
        let timeout = Task {
            try await Task.sleep(for: .seconds(30))
            recognition.cancel()
        }
        defer { timeout.cancel() }
        let result = try await recognition.value
        let text = result.text.lowercased()
        let first = try XCTUnwrap(text.range(of: "purple bicycle"), text)
        let last = try XCTUnwrap(text.range(of: "silver mountain"), text)
        XCTAssertLessThan(first.lowerBound, last.lowerBound, "Append segments must be transcribed in recording order")
        XCTAssertTrue(result.utterances.contains { $0.start >= firstDuration && $0.text.lowercased().contains("silver mountain") },
                      "Appended speech timestamps must include the preceding audio duration")
        try store.saveNoteChanges(note, values: ["transcription": result.text,
            "transcriptUtterancesJSON": String(decoding: try JSONEncoder().encode(result.utterances), as: UTF8.self)])
        store.context.refresh(note, mergeChanges: false)
        XCTAssertEqual(note.text("transcription"), result.text)
        XCTAssertEqual(try JSONDecoder().decode([LocalUtterance].self,
            from: Data(note.text("transcriptUtterancesJSON").utf8)), result.utterances)
        for (file, before) in zip(files, originalAudio) { XCTAssertEqual(try Data(contentsOf: file), before) }
    }

    /// Opt-in integration check against this Mac's installed Apple speech assets.
    /// Feed audio progressively and require visible speech before ending the stream.
    func testInstalledModelTranscribesLiveInputBeforeStopAndKeepsFinalWords() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Enable explicitly with a locally generated speech fixture and installed Apple assets.")
        }
        let audio = try AVAudioFile(forReading: URL(fileURLWithPath: "/tmp/jotley-local-live-speech.aiff"), commonFormat: .pcmFormatFloat32, interleaved: false)
        let probe = LiveResultProbe()
        let session = try await LiveSpeechSession.start(locale: Locale(identifier: "en-US")) { await probe.accept($0) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 2048) else { return XCTFail("Audio buffer unavailable") }
        while audio.framePosition < audio.length {
            try audio.read(into: buffer)
            guard let channels = buffer.floatChannelData else { return XCTFail("Audio samples unavailable") }
            var samples = [Float](repeating: 0, count: Int(buffer.frameLength))
            for i in samples.indices {
                for channel in 0..<Int(buffer.format.channelCount) { samples[i] += channels[channel][i] / Float(buffer.format.channelCount) }
            }
            session.append(samples.withUnsafeBufferPointer { Data(buffer: $0) }, sampleRate: buffer.format.sampleRate)
            try await Task.sleep(for: .milliseconds(35))
        }
        for _ in 0..<100 {
            if await probe.count() > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let countBeforeStop = await probe.count()
        XCTAssertGreaterThan(countBeforeStop, 0, "Speech must arrive while the input stream is still open")
        let result = try await session.finish()
        XCTAssertTrue(result.text.lowercased().contains("audio source"), result.text)
        XCTAssertTrue(result.text.lowercased().contains("purple bicycle"), "Stop must retain the final spoken words: \(result.text)")
        XCTAssertFalse(result.utterances.isEmpty)
    }
}

@objc(JotleyDeletionRefusedNote)
private final class DeletionRefusedNote: NSManagedObject {
    override func validateForDelete() throws {
        throw NSError(domain: "JotleyDeletionTests", code: 1)
    }
}

extension LocalCoreTests {
    @MainActor func testDeletedRecordingCannotResurrectAndUnrelatedEditsPersist() throws {
        let root = try temporaryDirectory()
        let store = try SharedPersistenceController(root: root)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let target = try store.create(title: "Delete")
        let keep = try store.create(title: "Keep", text: "Original")
        let id = try XCTUnwrap(target.localNoteID)
        let audio = root.appendingPathComponent("Recordings/\(id.uuidString)/segment")
        let writer = try DurableAudioWriter(directory: audio, noteID: id, sampleRate: 16000)
        try writer.append(Data(repeating: 0, count: 400)); try writer.close()
        keep.setValue("Edited content", forKey: "transcription")
        try store.deleteNoteAndAudio(target)
        try store.resolveRecordingDeletions()
        XCTAssertEqual(try store.notes().count, 1)
        XCTAssertEqual(keep.text("transcription"), "Edited content")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("DeletedRecordings/\(id.uuidString)").path))
    }
    @MainActor func testRecordingDeletionJournalRestoresBeforeCommitAndPurgesAfterCommit() throws {
        let root = try temporaryDirectory()
        let first = try SharedPersistenceController(root: root)
        let note = try first.create(title: "Crash before deletion")
        let id = try XCTUnwrap(note.localNoteID)
        let source = root.appendingPathComponent("Recordings/\(id.uuidString)")
        let pending = root.appendingPathComponent("DeletedRecordings/\(id.uuidString)")
        let writer = try DurableAudioWriter(directory: source.appendingPathComponent("segment"), noteID: id, sampleRate: 16000)
        try writer.append(Data(repeating: 0, count: 400)); try writer.close()
        try FileManager.default.createDirectory(at: pending.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: pending)
        for item in first.container.persistentStoreCoordinator.persistentStores { try first.container.persistentStoreCoordinator.remove(item) }
        let second = try SharedPersistenceController(root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        let restored = try XCTUnwrap(second.notes().first)
        try FileManager.default.moveItem(at: source, to: pending)
        second.context.delete(restored); try second.save()
        for item in second.container.persistentStoreCoordinator.persistentStores { try second.container.persistentStoreCoordinator.remove(item) }
        let third = try SharedPersistenceController(root: root)
        defer {
            for item in third.container.persistentStoreCoordinator.persistentStores { try? third.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertTrue(try third.notes().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
    }
    @MainActor func testFailedDeletionCommitRestoresNoteAndCapturedAudio() throws {
        let root = try temporaryDirectory()
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription(); entity.name = "Note"
        entity.managedObjectClassName = NSStringFromClass(DeletionRefusedNote.self)
        entity.properties = [("id", NSAttributeType.UUIDAttributeType), ("timestamp", .dateAttributeType),
                             ("title", .stringAttributeType), ("transcription", .stringAttributeType), ("noteType", .stringAttributeType)].map { name, type in
            let attribute = NSAttributeDescription(); attribute.name = name; attribute.attributeType = type; attribute.isOptional = true; return attribute
        }
        model.entities = [entity]
        let store = try SharedPersistenceController(root: root, model: model)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let note = try store.create(title: "Keep after failure", text: "Final transcript")
        let id = try XCTUnwrap(note.localNoteID)
        let audio = root.appendingPathComponent("Recordings/\(id.uuidString)/segment")
        let writer = try DurableAudioWriter(directory: audio, noteID: id, sampleRate: 16000)
        try writer.append(Data(repeating: 0, count: 400)); try writer.close()
        XCTAssertThrowsError(try store.deleteNoteAndAudio(note))
        XCTAssertEqual(try store.notes().count, 1)
        XCTAssertEqual(note.text("transcription"), "Final transcript")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.appendingPathComponent("audio.float32").path))
        XCTAssertEqual(try DurableAudioWriter.frameCount(at: audio), 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("DeletedRecordings/\(id.uuidString)").path))
    }
}

extension LocalCoreTests {
    func testSavedAudioReusesValidCAFAndRebuildsAfterRawChanges() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try DurableAudioWriter(directory: directory, noteID: UUID(), sampleRate: 16000)
        try writer.append(Data(repeating: 0, count: 64000))
        let caf = try DurableAudioWriter.audioFile(at: directory)
        let inode = try FileManager.default.attributesOfItem(atPath: caf.path)[.systemFileNumber] as? NSNumber
        XCTAssertEqual(try DurableAudioWriter.audioFile(at: directory), caf)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: caf.path)[.systemFileNumber] as? NSNumber, inode,
                       "Playback should reuse a valid CAF rather than rewrite long recordings")
        try writer.append(Data(repeating: 0, count: 400))
        let updated = try AVAudioFile(forReading: DurableAudioWriter.audioFile(at: directory))
        XCTAssertEqual(updated.length, 16100)
        XCTAssertEqual(try DurableAudioWriter.frameCount(at: directory), 16100)
        try writer.close()
    }
}

@objc(JotleyGeneratedContentRefusedNote)
private final class GeneratedContentRefusedNote: NSManagedObject {
    override func validateForUpdate() throws {
        if value(forKey: "summary") as? String == "Rejected output" {
            throw NSError(domain: "JotleyGeneratedContentTests", code: 1)
        }
        try super.validateForUpdate()
    }
}

@objc(JotleyCreationRefusedNote)
private final class CreationRefusedNote: NSManagedObject {
    override func validateForInsert() throws {
        if value(forKey: "title") as? String == "Rejected note" {
            throw NSError(domain: "JotleyCreationTests", code: 1)
        }
        try super.validateForInsert()
    }
}

extension LocalCoreTests {
    @MainActor func testFailedCreationRemovesOnlyInsertedNoteAndKeepsPendingEdits() throws {
        let root = try temporaryDirectory()
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription(); entity.name = "Note"
        entity.managedObjectClassName = NSStringFromClass(CreationRefusedNote.self)
        entity.properties = [("id", NSAttributeType.UUIDAttributeType), ("timestamp", .dateAttributeType),
                             ("title", .stringAttributeType), ("transcription", .stringAttributeType), ("noteType", .stringAttributeType)].map { name, type in
            let attribute = NSAttributeDescription(); attribute.name = name; attribute.attributeType = type; attribute.isOptional = true; return attribute
        }
        model.entities = [entity]
        let store = try SharedPersistenceController(root: root, model: model)
        defer {
            for item in store.container.persistentStoreCoordinator.persistentStores { try? store.container.persistentStoreCoordinator.remove(item) }
            try? FileManager.default.removeItem(at: root)
        }
        let keep = try store.create(title: "Existing", text: "Keep existing content")
        keep.setValue("Pending local edit", forKey: "title")
        XCTAssertThrowsError(try store.create(title: "Rejected note", text: "Should never persist", noteType: "voice"))
        XCTAssertEqual(try store.notes().count, 1)
        XCTAssertEqual(keep.text("title"), "Pending local edit")
        XCTAssertEqual(keep.text("transcription"), "Keep existing content")
        try store.save()
        let imported = try store.create(title: "Accepted note", text: "Complete text", noteType: "voice")
        XCTAssertEqual(imported.text("noteType"), "voice")
        let reopened = try SharedPersistenceController(root: root, model: model)
        let notes = try reopened.notes()
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains { $0.text("title") == "Pending local edit" })
        XCTAssertTrue(notes.contains { $0.text("title") == "Accepted note" && $0.text("noteType") == "voice" })
        XCTAssertFalse(notes.contains { $0.text("title") == "Rejected note" })
    }
}

extension LocalCoreTests {
    func testLargeCombiningSequenceStillRespectsSummaryByteLimit() {
        let text = "Start " + "a" + String(repeating: "\u{0301}", count: 4000) + " 👩🏽‍💻 End"
        let parts = LocalSummary.chunks(text)
        XCTAssertEqual(parts.joined(), text)
        XCTAssertTrue(parts.allSatisfy { $0.utf8.count <= 2400 })
        XCTAssertGreaterThan(parts.count, 3)
    }
    @MainActor func testRejectedGeneratedContentRestoresAllFieldsAndPreservesOtherEdits() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription(); entity.name = "Note"
        entity.managedObjectClassName = NSStringFromClass(GeneratedContentRefusedNote.self)
        entity.properties = [("id", NSAttributeType.UUIDAttributeType), ("timestamp", .dateAttributeType),
            ("title", .stringAttributeType), ("transcription", .stringAttributeType), ("noteType", .stringAttributeType),
            ("summary", .stringAttributeType), ("summaryType", .stringAttributeType)].map { name, type in
                let attribute = NSAttributeDescription(); attribute.name = name; attribute.attributeType = type; attribute.isOptional = true; return attribute
            }
        model.entities = [entity]
        let store = try SharedPersistenceController(root: root, model: model)
        let note = try store.create(title: "Generated content", text: "Original transcript")
        try store.saveNoteChanges(note, values: ["summary": "Original summary"])
        let other = try store.create(title: "Other note")
        other.setValue("Edited title", forKey: "title")
        XCTAssertThrowsError(try store.saveNoteChanges(note, values: ["summary": "Rejected output", "summaryType": "Meeting", "transcription": "Replacement transcript"]))
        XCTAssertEqual(note.text("summary"), "Original summary")
        XCTAssertEqual(note.text("transcription"), "Original transcript")
        XCTAssertNil(note.value(forKey: "summaryType"))
        XCTAssertEqual(other.text("title"), "Edited title")
        XCTAssertThrowsError(try store.saveNoteChanges(note, values: ["unknownField": "Must not mutate"]))
        try store.save()
        for persistent in store.container.persistentStoreCoordinator.persistentStores { try store.container.persistentStoreCoordinator.remove(persistent) }
        let reopened = try SharedPersistenceController(root: root, model: model)
        defer { for persistent in reopened.container.persistentStoreCoordinator.persistentStores { try? reopened.container.persistentStoreCoordinator.remove(persistent) } }
        let notes = try reopened.notes()
        XCTAssertTrue(notes.contains { $0.text("title") == "Edited title" })
        let original = try XCTUnwrap(notes.first { $0.text("title") == "Generated content" })
        XCTAssertEqual(original.text("summary"), "Original summary")
        XCTAssertNil(original.value(forKey: "summaryType"))
    }
    func testCancelledSummaryStopsBeforeCheckingAssetsOrProducingSnapshots() async throws {
        let probe = SummaryProbe()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await LocalSummary.generate("Retain this note", template: .concise, locale: Locale(identifier: "en-US")) { await probe.accept($0) }
        }
        do { _ = try await task.value; XCTFail("Cancelled summary should not start") }
        catch is CancellationError { }
        let count = await probe.count()
        XCTAssertEqual(count, 0)
    }
    func testInstalledSummaryModelCancelsDuringStreamingAndCanGenerateAgain() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_MODEL_TESTS"] == "1" else { throw XCTSkip("Installed-model integration is opt-in") }
        let locale = Locale(identifier: "en-US")
        if let reason = LocalSummary.readiness(locale: locale) { throw XCTSkip(reason) }
        let probe = SummaryProbe()
        let source = String(repeating: "Meeting decision: Keep notes and microphone recordings offline. Sam will test crash recovery. Nina will review the interface. No dates were agreed.\n", count: 60)
        let generation = Task {
            try await LocalSummary.generate(source, template: .meeting, locale: locale) { await probe.accept($0) }
        }
        var began = false
        for _ in 0..<300 {
            if await probe.hasGeneratedBody() { began = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        generation.cancel()
        do { _ = try await generation.value; XCTFail("Cancellation during streaming must not return generated content") }
        catch is CancellationError { }
        XCTAssertTrue(began, "Installed model must generate body text before cancellation")
        let countAtCancellation = await probe.count()
        try await Task.sleep(for: .milliseconds(200))
        let countAfterCancellation = await probe.count()
        XCTAssertEqual(countAfterCancellation, countAtCancellation)
        let restarted = SummaryProbe()
        let result = try await LocalSummary.generate("Meeting decision: Keep all notes offline. Sam owns crash recovery testing.", template: .auto, locale: locale) { await restarted.accept($0) }
        XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let last = await restarted.last()
        XCTAssertEqual(last, result, "Streaming publishes complete snapshots, not repeated deltas")
    }
}

private actor SummaryProbe {
    private var snapshots: [String] = []
    func accept(_ text: String) { snapshots.append(text) }
    func count() -> Int { snapshots.count }
    func last() -> String? { snapshots.last }
    func hasGeneratedBody() -> Bool {
        guard let text = snapshots.last else { return false }
        return text.replacingOccurrences(of: "## Part 1\n", with: "").trimmingCharacters(in: .whitespacesAndNewlines).count >= 32
    }
}

extension LocalCoreTests {
    func testTwoHoursOfPCMReconstructsFirstAndFinalSamples() throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_AUDIO_STRESS"] == "1" else { throw XCTSkip("Large local audio reconstruction is opt-in") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try DurableAudioWriter(directory: directory, noteID: UUID(), sampleRate: 16000)
        let framesPerSecond = 16000
        let firstSecond = [Float](repeating: -0.5, count: framesPerSecond).withUnsafeBytes { Data($0) }
        let followingSecond = [Float](repeating: 0.25, count: framesPerSecond).withUnsafeBytes { Data($0) }
        try writer.append(firstSecond)
        for _ in 1..<7200 { try writer.append(followingSecond) }
        // Recover incomplete capture without closing/finalizing its manifest.
        let caf = try DurableAudioWriter.recover(at: directory)
        let audio = try AVAudioFile(forReading: caf)
        XCTAssertEqual(audio.length, Int64(7200 * framesPerSecond))
        XCTAssertFalse(try DurableAudioWriter.manifest(at: directory).complete)
        let sample = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 1))
        try audio.read(into: sample, frameCount: 1)
        XCTAssertEqual(try XCTUnwrap(sample.floatChannelData?[0][0]), -0.5)
        audio.framePosition = audio.length - 1
        try audio.read(into: sample, frameCount: 1)
        XCTAssertEqual(try XCTUnwrap(sample.floatChannelData?[0][0]), 0.25)
        XCTAssertEqual(try DurableAudioWriter.frameCount(at: directory), audio.length)
        try writer.close()
    }
    func testRecoveryFailurePreservesRawAndExistingCAFAndIgnoresCrashTail() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try DurableAudioWriter(directory: directory, noteID: UUID(), sampleRate: 16000)
        try writer.append([Float](repeating: 0.5, count: 100).withUnsafeBytes { Data($0) }); try writer.close()
        let raw = directory.appendingPathComponent("audio.float32")
        let handle = try FileHandle(forWritingTo: raw)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([1, 2, 3])); try handle.close()
        let caf = try DurableAudioWriter.recover(at: directory)
        XCTAssertEqual(try AVAudioFile(forReading: caf).length, 100)
        let savedRaw = try Data(contentsOf: raw); let savedCAF = try Data(contentsOf: caf)
        var manifest = try DurableAudioWriter.manifest(at: directory); manifest.sampleRate = 0
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("recording.json"), options: .atomic)
        XCTAssertThrowsError(try DurableAudioWriter.recover(at: directory))
        XCTAssertEqual(try Data(contentsOf: raw), savedRaw)
        XCTAssertEqual(try Data(contentsOf: caf), savedCAF)
    }
}


extension LocalCoreTests {
    func testMalformedLivePCMReportsFailureAndPreservesDurableCapture() async throws {
        guard ProcessInfo.processInfo.environment["JOTLEY_RUN_MODEL_TESTS"] == "1" else { throw XCTSkip("Installed-model integration is opt-in") }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try DurableAudioWriter(directory: directory, noteID: UUID(), sampleRate: 16000)
        try writer.append([Float](repeating: 0.25, count: 100).withUnsafeBytes { Data($0) })
        let session = try await LiveSpeechSession.start(locale: Locale(identifier: "en-US"), snapshot: { _ in })
        session.append(Data([1, 2, 3]), sampleRate: 16000)
        do { _ = try await session.finish(); XCTFail("Partial PCM sample must fail safely") }
        catch { XCTAssertTrue(error.localizedDescription.contains("incomplete PCM sample"), error.localizedDescription) }
        XCTAssertEqual(try DurableAudioWriter.frameCount(at: directory), 100)
        try writer.close()
        XCTAssertEqual(try AVAudioFile(forReading: DurableAudioWriter.audioFile(at: directory)).length, 100)
    }
}
