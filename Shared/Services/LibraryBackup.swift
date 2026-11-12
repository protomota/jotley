import Foundation
import CoreData
import CryptoKit

public struct LibraryBackupItem: Codable, Equatable, Sendable {
    public var entity: String
    public var id: UUID
    public var text: [String: String]
    public var dates: [String: Date]
    public var numbers: [String: Double]
    public var noteID: UUID?
    public var folderID: UUID?
    public var tagIDs: [UUID]
}

public struct LibraryBackup: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var createdAt: Date
    public var items: [LibraryBackupItem]
    public var templates: [CustomSummaryTemplate]
    public var noteCount: Int { items.filter { $0.entity == "Note" }.count }
}

public struct LibraryRestoreResult: Equatable, Sendable {
    public let notesAdded: Int
    public let recordsAdded: Int
    public let templatesAdded: Int
    public let recordsKept: Int
}

/// Portable text data only. No database files, device paths, credentials,
/// support sessions or microphone state enter this format.
public enum LibraryBackupService {
    public static let byteLimit = 256 * 1024 * 1024
    private struct Fields {
        var text: Set<String> = []
        var dates: Set<String> = []
        var numbers: [String: ClosedRange<Double>] = [:]
        var ownsNote = false
    }
    private static let schema: [String: Fields] = [
        "Folder": Fields(text: ["name"], dates: ["createdAt"], numbers: ["sortOrder": Double(Int32.min)...Double(Int32.max)]),
        "Tag": Fields(text: ["name", "canonicalName"], dates: ["createdAt"]),
        "Note": Fields(text: ["title", "transcription", "cleantranscription", "summary", "summaryType", "notes", "noteType", "sourceDescription", "sourceURL", "transcriptUtterancesJSON"], dates: ["timestamp"]),
        "NoteChatMessage": Fields(text: ["role", "content"], dates: ["timestamp"], ownsNote: true),
        "RecordingMarker": Fields(text: ["label"], numbers: ["timestamp": 0...Double.greatestFiniteMagnitude], ownsNote: true)
    ]

    public static func decode(_ data: Data) throws -> LibraryBackup {
        guard data.count <= byteLimit else { throw LocalError.message("Choose a Jotley backup smaller than 256 MB.") }
        let backup: LibraryBackup
        do { backup = try JSONDecoder().decode(LibraryBackup.self, from: data) }
        catch { throw LocalError.message("This file is not a readable Jotley library backup. No data was changed.") }
        try validate(backup)
        return backup
    }

    public static func encode(_ backup: LibraryBackup) throws -> Data {
        try validate(backup)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(backup)
        guard data.count <= byteLimit else { throw LocalError.message("This library exceeds the 256 MB portable backup limit.") }
        return data
    }

    public static func validate(_ backup: LibraryBackup) throws {
        guard backup.format == "ai.jotley.library-backup", backup.version == 1,
              backup.createdAt.timeIntervalSinceReferenceDate.isFinite, backup.items.count <= 500_000,
              backup.templates.count <= 100 else { throw invalid() }
        var ids: [String: Set<UUID>] = [:]
        for item in backup.items {
            guard let fields = schema[item.entity], ids[item.entity, default: []].insert(item.id).inserted,
                  Set(item.text.keys).isSubset(of: fields.text), Set(item.dates.keys).isSubset(of: fields.dates),
                  Set(item.numbers.keys).isSubset(of: Set(fields.numbers.keys)),
                  item.dates.values.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
                  Set(item.tagIDs).count == item.tagIDs.count else { throw invalid() }
            for (key, value) in item.numbers {
                guard value.isFinite, fields.numbers[key]?.contains(value) == true,
                      key != "sortOrder" || value.rounded() == value else { throw invalid() }
            }
            guard fields.ownsNote == (item.noteID != nil),
                  item.entity == "Note" || (item.folderID == nil && item.tagIDs.isEmpty) else { throw invalid() }
            if item.entity == "NoteChatMessage", !["user", "assistant"].contains(item.text["role"] ?? "") { throw invalid() }
        }
        for item in backup.items {
            if let id = item.noteID, ids["Note"]?.contains(id) != true { throw invalid() }
            if let id = item.folderID, ids["Folder"]?.contains(id) != true { throw invalid() }
            if item.tagIDs.contains(where: { ids["Tag"]?.contains($0) != true }) { throw invalid() }
        }
        var templateIDs = Set<UUID>()
        for record in backup.templates {
            guard templateIDs.insert(record.id).inserted, !record.deleted,
                  !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.name.count <= 60,
                  !record.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.instructions.utf8.count <= 2000,
                  record.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  record.updatedAt.timeIntervalSinceReferenceDate.isFinite else { throw invalid() }
        }
    }

    @MainActor public static func export(from store: SharedPersistenceController,
                                          templates: SummaryTemplateStore) throws -> LibraryBackup {
        try store.requireLibraryBackupAccess()
        let templateRecords = try templates.backupRecords()
        try store.save()
        var items: [LibraryBackupItem] = []
        for entity in schema.keys.sorted() {
            guard let fields = schema[entity], store.container.managedObjectModel.entitiesByName[entity] != nil else { throw invalid() }
            let expectedFields = fields.text.union(fields.dates).union(fields.numbers.keys).union(["id"]).union(fields.ownsNote ? ["noteId"] : [])
            guard Set(store.container.managedObjectModel.entitiesByName[entity]!.attributesByName.keys) == expectedFields else {
                throw LocalError.message("This version of the library needs a newer backup format. No data was changed.")
            }
            let objects = try store.context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))
            for object in objects {
                let text = fields.text.reduce(into: [String: String]()) { if let value = object.value(forKey: $1) as? String { $0[$1] = value } }
                let dates = fields.dates.reduce(into: [String: Date]()) { if let value = object.value(forKey: $1) as? Date { $0[$1] = value } }
                let numbers = fields.numbers.keys.reduce(into: [String: Double]()) { if let value = object.value(forKey: $1) as? NSNumber { $0[$1] = value.doubleValue } }
                let folder = entity == "Note" ? object.value(forKey: "folder") as? NSManagedObject : nil
                let tags = entity == "Note" ? object.value(forKey: "tags") as? Set<NSManagedObject> ?? [] : []
                items.append(LibraryBackupItem(entity: entity, id: identifier(object), text: text, dates: dates, numbers: numbers,
                    noteID: fields.ownsNote ? object.value(forKey: "noteId") as? UUID : nil,
                    folderID: folder.map(identifier), tagIDs: tags.map(identifier).sorted { $0.uuidString < $1.uuidString }))
            }
        }
        let result = LibraryBackup(format: "ai.jotley.library-backup", version: 1, createdAt: Date(),
            items: items.sorted { ($0.entity, $0.id.uuidString) < ($1.entity, $1.id.uuidString) }, templates: templateRecords)
        try validate(result)
        return result
    }

    /// Merge-only restore: matching IDs always keep the current user's data.
    /// All validation/template capacity checks precede the Core Data transaction.
    @MainActor public static func restore(_ backup: LibraryBackup, to store: SharedPersistenceController,
                                           templates: SummaryTemplateStore) throws -> LibraryRestoreResult {
        try validate(backup)
        try store.requireLibraryBackupAccess()
        let templatePlan = try templates.prepareBackupImport(backup.templates)
        try store.save() // A failed restore must not roll back unrelated edits.
        var existing: [String: [UUID: NSManagedObject]] = [:]
        for entity in schema.keys {
            guard store.container.managedObjectModel.entitiesByName[entity] != nil else { throw invalid() }
            for object in try store.context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)) {
                let id = identifier(object)
                guard existing[entity]?[id] == nil else { throw LocalError.message("The current library contains duplicate identifiers. No backup was restored.") }
                existing[entity, default: [:]][id] = object
            }
        }
        var added: [(LibraryBackupItem, NSManagedObject)] = []
        do {
            // A fresh installation already has Personal/Study/Work folders.
            // Reuse unambiguous matching names instead of duplicating them.
            for item in backup.items where ["Folder", "Tag"].contains(item.entity) && existing[item.entity]?[item.id] == nil {
                let name = normalizedName(item.text["name"] ?? "")
                let matches = existing[item.entity, default: [:]].values.filter { normalizedName($0.text("name")) == name }
                if !name.isEmpty, matches.count == 1 { existing[item.entity, default: [:]][item.id] = matches.first }
            }
            for item in backup.items where existing[item.entity]?[item.id] == nil {
                let object = NSEntityDescription.insertNewObject(forEntityName: item.entity, into: store.context)
                object.setValue(item.id, forKey: "id")
                for (key, value) in item.text { object.setValue(value, forKey: key) }
                for (key, value) in item.dates { object.setValue(value, forKey: key) }
                for (key, value) in item.numbers { object.setValue(NSNumber(value: value), forKey: key) }
                if let noteID = item.noteID { object.setValue(noteID, forKey: "noteId") }
                existing[item.entity, default: [:]][item.id] = object
                added.append((item, object))
            }
            for (item, object) in added where item.entity == "Note" {
                if let id = item.folderID { object.setValue(existing["Folder"]?[id], forKey: "folder") }
                object.setValue(NSSet(array: item.tagIDs.compactMap { existing["Tag"]?[$0] }), forKey: "tags")
            }
            try store.save()
        } catch {
            store.context.rollback()
            throw LocalError.message("The backup could not be restored. Your existing notes were preserved.")
        }
        templates.applyBackupImport(templatePlan)
        return LibraryRestoreResult(notesAdded: added.filter { $0.0.entity == "Note" }.count,
            recordsAdded: added.count, templatesAdded: templatePlan.added, recordsKept: backup.items.count - added.count)
    }

    @MainActor private static func identifier(_ object: NSManagedObject) -> UUID {
        if let id = object.value(forKey: "id") as? UUID { return id }
        // Legacy nil IDs get a repeatable portable identity without modifying
        // the source library merely to export it.
        let digest = SHA256.hash(data: Data(object.objectID.uriRepresentation().absoluteString.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func invalid() -> LocalError {
        .message("This backup has an unsupported format, invalid fields or broken note relationships. No data was changed.")
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
