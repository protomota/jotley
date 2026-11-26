import XCTest
import CoreData
@testable import jotley

final class LibraryBackupTests: XCTestCase {
    func testSignedLocalTestUsesSeparateLibraryAndCannotSync() {
        let ordinary: [String: Any] = [NoteSyncMode.containerInfoKey: "iCloud.org.example.JotleyTests"]
        var isolated = ordinary
        isolated["JotleyIsolatedLocalTest"] = true
        XCTAssertEqual(NoteSyncMode.configuredIdentifier(in: ordinary), "iCloud.org.example.JotleyTests")
        XCTAssertNil(NoteSyncMode.configuredIdentifier(in: isolated))
        XCTAssertNotEqual(LocalPaths.libraryDirectoryName(info: isolated), LocalPaths.libraryDirectoryName(info: ordinary))
    }

    @MainActor private func catalog() -> (SummaryTemplateStore, UserDefaults, String) {
        let name = "JotleyBackupTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        return (SummaryTemplateStore(defaults: defaults), defaults, name)
    }

    @MainActor func testPortableRoundTripPreservesAllNoteFieldsRelationshipsAndTemplates() throws {
        let source = try SharedPersistenceController(inMemory: true)
        let target = try SharedPersistenceController(inMemory: true)
        let (templates, defaults, suite) = catalog()
        let (restoredTemplates, restoredDefaults, restoredSuite) = catalog()
        defer {
            defaults.removePersistentDomain(forName: suite)
            restoredDefaults.removePersistentDomain(forName: restoredSuite)
            try? FileManager.default.removeItem(at: source.root)
            try? FileManager.default.removeItem(at: target.root)
        }
        let template = try templates.save(name: "Follow-up", instructions: "List decisions and next steps.")
        let note = try source.create(title: "Café 日本語", text: "Original transcript", noteType: "meeting")
        let date = Date(timeIntervalSince1970: 1_600_000_000.125)
        for (key, value) in ["summary": "## Decisions\n- Ship", "notes": "Personal notes", "cleantranscription": "Clean copy", "sourceDescription": "Imported meeting", "sourceURL": "https://example.com/notes", "summaryType": template.key, "transcriptUtterancesJSON": "[]"] {
            note.setValue(value, forKey: key)
        }
        note.setValue(date, forKey: "timestamp")
        let folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: source.context)
        folder.setValue(UUID(), forKey: "id"); folder.setValue("Projects", forKey: "name")
        folder.setValue(date, forKey: "createdAt"); folder.setValue(12, forKey: "sortOrder")
        note.setValue(folder, forKey: "folder")
        try source.saveNoteChanges(note, values: [:], replacingTags: ["Design", "Planning"])
        let marker = NSEntityDescription.insertNewObject(forEntityName: "RecordingMarker", into: source.context)
        marker.setValue(UUID(), forKey: "id"); marker.setValue(note.localNoteID, forKey: "noteId")
        marker.setValue("Decision", forKey: "label"); marker.setValue(14.5, forKey: "timestamp")
        try source.saveChatMessage(LocalChatMessage(id: UUID(), role: "user", content: "What next?", timestamp: date), noteID: note.localNoteID!)
        let backup = try LibraryBackupService.export(from: source, templates: templates)
        let decoded = try LibraryBackupService.decode(LibraryBackupService.encode(backup))
        XCTAssertEqual(decoded, backup)
        let result = try LibraryBackupService.restore(decoded, to: target, templates: restoredTemplates)
        XCTAssertEqual(result.notesAdded, 1)
        XCTAssertEqual(result.templatesAdded, 1)
        let restored = try LibraryBackupService.export(from: target, templates: restoredTemplates)
        XCTAssertEqual(restored.items, backup.items)
        XCTAssertEqual(restored.templates, backup.templates)
        XCTAssertEqual(try target.chatMessages(noteID: note.localNoteID!).map(\.content), ["What next?"])
        let text = String(decoding: try LibraryBackupService.encode(backup), as: UTF8.self)
        XCTAssertFalse(text.contains("Keychain"))
        XCTAssertFalse(text.contains("access_token"))
        XCTAssertFalse(text.contains(source.root.path))
    }

    @MainActor func testRepeatedRestoreKeepsNewerEditsAndDoesNotDuplicateNotesOrPrompts() throws {
        let store = try SharedPersistenceController(inMemory: true)
        let (templates, defaults, suite) = catalog()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: store.root) }
        let original = try templates.save(name: "Recap", instructions: "Original format")
        let note = try store.create(title: "Original", text: "Original source")
        let backup = try LibraryBackupService.export(from: store, templates: templates)
        note.setValue("Newer edit", forKey: "title")
        _ = try templates.save(id: original.id, name: "Recap", instructions: "New format", expectedRevision: original.revision)
        for _ in 0..<2 {
            let result = try LibraryBackupService.restore(backup, to: store, templates: templates)
            XCTAssertEqual(result.notesAdded, 0)
            XCTAssertEqual(result.templatesAdded, 0)
        }
        XCTAssertEqual(try store.notes().count, 1)
        XCTAssertEqual(note.text("title"), "Newer edit")
        XCTAssertEqual(templates.templates.first?.instructions, "New format")
    }

    @MainActor func testMalformedBackupAndActiveOperationsLeaveLibraryUnchanged() throws {
        let store = try SharedPersistenceController(inMemory: true)
        let (templates, defaults, suite) = catalog()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: store.root) }
        let note = try store.create(title: "Keep")
        let backup = try LibraryBackupService.export(from: store, templates: templates)
        var invalid = backup
        invalid.items[0].folderID = UUID()
        XCTAssertThrowsError(try LibraryBackupService.restore(invalid, to: store, templates: templates))
        invalid = backup; invalid.items.append(invalid.items[0])
        XCTAssertThrowsError(try LibraryBackupService.restore(invalid, to: store, templates: templates))
        invalid = backup; invalid.items[0].text["unsupportedField"] = "Rejected"
        XCTAssertThrowsError(try LibraryBackupService.restore(invalid, to: store, templates: templates))
        invalid = backup; invalid.version = 99
        XCTAssertThrowsError(try LibraryBackupService.restore(invalid, to: store, templates: templates))
        let lease = try store.beginRecording(note)
        XCTAssertThrowsError(try LibraryBackupService.export(from: store, templates: templates))
        XCTAssertThrowsError(try LibraryBackupService.restore(backup, to: store, templates: templates))
        store.endRecording(lease: lease)
        let operation = store.beginNoteOperation(for: note.objectID)
        XCTAssertThrowsError(try LibraryBackupService.restore(backup, to: store, templates: templates))
        store.endNoteOperation(lease: operation)
        XCTAssertEqual(try store.notes().map { $0.text("title") }, ["Keep"])
    }

    @MainActor func testRestoredDataSurvivesDatabaseAndTemplateStoreReopen() throws {
        let seed = try SharedPersistenceController(inMemory: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JotleyBackupReopen-\(UUID())")
        let (templates, defaults, suite) = catalog()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: seed.root); try? FileManager.default.removeItem(at: root) }
        _ = try seed.create(title: "Portable note", text: "Stored content")
        _ = try templates.save(name: "Recovery", instructions: "Concise")
        let backup = try LibraryBackupService.export(from: seed, templates: templates)
        var target: SharedPersistenceController? = try SharedPersistenceController(root: root)
        _ = try LibraryBackupService.restore(backup, to: target!, templates: templates)
        for store in target!.container.persistentStoreCoordinator.persistentStores {
            try target!.container.persistentStoreCoordinator.remove(store)
        }
        target = nil
        let reopened = try SharedPersistenceController(root: root)
        XCTAssertEqual(try reopened.notes().map { $0.text("transcription") }, ["Stored content"])
        XCTAssertEqual(SummaryTemplateStore(defaults: defaults).templates.first?.name, "Recovery")
    }

    @MainActor func testFreshInstallReusesDefaultFoldersAndTemplateNameCollisionsStayDistinct() throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent("JotleyBackupSource-\(UUID())")
        let targetRoot = FileManager.default.temporaryDirectory.appendingPathComponent("JotleyBackupTarget-\(UUID())")
        let source = try SharedPersistenceController(root: sourceRoot)
        let target = try SharedPersistenceController(root: targetRoot)
        let (templates, defaults, suite) = catalog()
        let (targetTemplates, targetDefaults, targetSuite) = catalog()
        defer {
            defaults.removePersistentDomain(forName: suite); targetDefaults.removePersistentDomain(forName: targetSuite)
            try? FileManager.default.removeItem(at: sourceRoot); try? FileManager.default.removeItem(at: targetRoot)
        }
        let note = try source.create(title: "Work note")
        let request = NSFetchRequest<NSManagedObject>(entityName: "Folder")
        note.setValue(try source.context.fetch(request).first { $0.text("name") == "Work" }, forKey: "folder")
        _ = try templates.save(name: "Recap", instructions: "Backup instructions")
        _ = try targetTemplates.save(name: "Recap", instructions: "Keep current instructions")
        let backup = try LibraryBackupService.export(from: source, templates: templates)
        for _ in 0..<2 { _ = try LibraryBackupService.restore(backup, to: target, templates: targetTemplates) }
        XCTAssertEqual(try target.context.count(for: request), 3)
        XCTAssertEqual((try target.notes().first?.value(forKey: "folder") as? NSManagedObject)?.text("name"), "Work")
        XCTAssertEqual(targetTemplates.templates.map(\.name), ["Recap", "Recap (restored)"])
        XCTAssertEqual(try targetTemplates.resolve(templates.templates[0].key).prompt, "Backup instructions")
    }

    @MainActor func testTemplateCapacityFailureCannotPartiallyRestoreNotes() throws {
        let source = try SharedPersistenceController(inMemory: true)
        let target = try SharedPersistenceController(inMemory: true)
        let (templates, defaults, suite) = catalog()
        let (targetTemplates, targetDefaults, targetSuite) = catalog()
        defer {
            defaults.removePersistentDomain(forName: suite); targetDefaults.removePersistentDomain(forName: targetSuite)
            try? FileManager.default.removeItem(at: source.root); try? FileManager.default.removeItem(at: target.root)
        }
        _ = try source.create(title: "Do not partially import")
        _ = try templates.save(name: "Incoming", instructions: "Backup")
        let backup = try LibraryBackupService.export(from: source, templates: templates)
        for index in 0..<100 { _ = try targetTemplates.save(name: "Existing \(index)", instructions: "Keep") }
        XCTAssertThrowsError(try LibraryBackupService.restore(backup, to: target, templates: targetTemplates))
        XCTAssertTrue(try target.notes().isEmpty)
        XCTAssertEqual(targetTemplates.templates.count, 100)
    }
}
