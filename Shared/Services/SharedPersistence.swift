import Foundation
import CoreData
import Combine
import CloudKit

/// CloudKit uses signed app entitlements and the user's iCloud account, never API keys.
public enum NoteSyncMode: Equatable {
    case localOnly
    case privateICloud(containerIdentifier: String)

    public static let preferenceKey = "jotleyPrivateICloudSyncEnabled"
    public static let containerInfoKey = "JotleyCloudKitContainerIdentifier"

    public static func configuredIdentifier(in info: [String: Any]) -> String? {
        guard !LocalPaths.isIsolatedTest(info: info),
              let value = info[containerInfoKey] as? String,
              value.hasPrefix("iCloud."), value.count > 7,
              value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) }) else { return nil }
        return value
    }
    public static func application(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
                                   defaults: UserDefaults = .standard) -> NoteSyncMode {
        // A missing preference enables sync; an explicit user opt-out survives upgrades.
        let enabled = defaults.object(forKey: preferenceKey) as? Bool ?? true
        guard enabled, let identifier = configuredIdentifier(in: info) else { return .localOnly }
        return .privateICloud(containerIdentifier: identifier)
    }
    public var isEnabled: Bool { if case .privateICloud = self { return true }; return false }

    public func storeDescription(at url: URL, inMemory: Bool) throws -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        if inMemory { description.type = NSInMemoryStoreType }
        else {
            #if os(iOS)
            // A session starts on an unlocked device. Keep encrypted note writes
            // available after that first unlock while the microphone runs locked.
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                                  forKey: NSPersistentStoreFileProtectionKey)
            #endif
            // Keep history while local-only so re-enabling sync uses the same store.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if case .privateICloud(let identifier) = self {
                guard Self.configuredIdentifier(in: [Self.containerInfoKey: identifier]) != nil else {
                    throw LocalError.message("The iCloud container identifier is invalid. No store was opened.")
                }
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: identifier)
                options.databaseScope = .private
                description.cloudKitContainerOptions = options
            }
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        return description
    }
}

public enum LocalError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

public enum LocalPaths {
    public static let bundleID = "com.protomota.jotley.local-development"
    static func isIsolatedTest(info: [String: Any]) -> Bool {
        info["JotleyIsolatedLocalTest"] as? Bool == true
    }
    static func libraryDirectoryName(info: [String: Any]) -> String {
        isIsolatedTest(info: info) ? "JotleySignedLocalTest" : "JotleyLocalDevelopment"
    }
    public static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask, appropriateFor: nil, create: true)
        let root = base.appendingPathComponent(libraryDirectoryName(info: Bundle.main.infoDictionary ?? [:]), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

/// Never opens the installed cloud app's store. No automatic repair or destructive recovery.
@MainActor
public final class SharedPersistenceController: ObservableObject {
    public let container: NSPersistentContainer
    public let root: URL
    public let syncMode: NoteSyncMode
    @Published public private(set) var ready = false
    @Published public private(set) var errorMessage: String?
    private var activeRecording: (noteID: NSManagedObjectID, lease: UUID)?
    private var noteOperations: [UUID: NSManagedObjectID] = [:]

    private static let bundledModel: NSManagedObjectModel? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "JotleyNotes", withExtension: "momd") else { return nil }
        return NSManagedObjectModel(contentsOf: url)
    }()

    public init(root: URL? = nil, inMemory: Bool = false, model: NSManagedObjectModel? = nil,
                syncMode: NoteSyncMode = .localOnly) throws {
        self.syncMode = inMemory ? .localOnly : syncMode
        self.root = try root ?? (inMemory ? FileManager.default.temporaryDirectory.appendingPathComponent("JotleyPreview-\(UUID().uuidString)") : LocalPaths.root())
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        guard let resolvedModel = model ?? Self.bundledModel else {
            throw LocalError.message("The bundled notes model could not be loaded. No data was changed.")
        }
        if self.syncMode.isEnabled {
            container = NSPersistentCloudKitContainer(name: "JotleyNotes", managedObjectModel: resolvedModel)
        } else {
            container = NSPersistentContainer(name: "JotleyNotes", managedObjectModel: resolvedModel)
        }
        let storeURL = self.root.appendingPathComponent("JotleyNotes.sqlite")
        let isNewLibrary = !FileManager.default.fileExists(atPath: storeURL.path)
        let description = try self.syncMode.storeDescription(at: storeURL, inMemory: inMemory)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { [weak self] _, error in
            // Synchronous completion on the initiating main thread.
            MainActor.assumeIsolated {
                self?.errorMessage = error.map { "Unable to open local notes: \($0.localizedDescription). The store was preserved." }
                self?.ready = error == nil
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = UndoManager()
        if ready && !inMemory {
            if isNewLibrary, resolvedModel.entitiesByName["Folder"] != nil {
                for name in ["Personal", "Study", "Work"] {
                    // Resolve against this store's model, including isolated test
                    // stores, rather than Core Data's global subclass lookup.
                    let folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: context)
                    folder.setValue(UUID(), forKey: "id")
                    folder.setValue(name, forKey: "name")
                    folder.setValue(Date(), forKey: "createdAt")
                    folder.setValue(0, forKey: "sortOrder")
                }
                try save()
            }
        }
    }

    /// One capture owner per store, independent of which window initiated it.
    public func beginRecording(_ note: NSManagedObject) throws -> UUID {
        guard ready, note.managedObjectContext === context, !note.isDeleted else {
            throw LocalError.message("This note is unavailable.")
        }
        guard activeRecording == nil else { throw LocalError.message("Finish the current transcription first.") }
        guard !noteOperations.values.contains(note.objectID) else { throw LocalError.message("Finish generating this note's content before recording it.") }
        if note.objectID.isTemporaryID { try context.obtainPermanentIDs(for: [note]) }
        let lease = UUID()
        activeRecording = (note.objectID, lease)
        return lease
    }
    public func endRecording(lease: UUID) {
        if activeRecording?.lease == lease { activeRecording = nil }
    }

    /// Track asynchronous generation across windows; external edits must not
    /// race a result that will be saved after an await.
    public func beginNoteOperation(for noteID: NSManagedObjectID) -> UUID {
        let lease = UUID()
        noteOperations[lease] = noteID
        return lease
    }
    public func endNoteOperation(lease: UUID) { noteOperations.removeValue(forKey: lease) }

    public func requireLibraryBackupAccess() throws {
        guard ready else { throw LocalError.message(errorMessage ?? "The notes library is unavailable.") }
        guard activeRecording == nil, noteOperations.isEmpty else {
            throw LocalError.message("Finish transcription and content generation before backing up or restoring notes.")
        }
    }

    public func requireExternalWriteAccess(to note: NSManagedObject) throws {
        guard ready, note.managedObjectContext === context, !note.isDeleted else {
            throw LocalError.message("This note is unavailable.")
        }
        guard activeRecording?.noteID != note.objectID else {
            throw LocalError.message("Finish recording this note before modifying it through MCP.")
        }
        guard !noteOperations.values.contains(note.objectID) else {
            throw LocalError.message("Finish generating this note's content before modifying it through MCP.")
        }
    }

    public func deleteNote(_ note: NSManagedObject) throws {
        guard note.managedObjectContext === context, !note.isDeleted else {
            throw LocalError.message("This note is unavailable.")
        }
        guard activeRecording?.noteID != note.objectID else {
            throw LocalError.message("Stop this transcription before deleting its note.")
        }
        try save() // Rollback below must not discard unrelated pending edits.
        var children: [NSManagedObject] = []
        for entity in ["NoteChatMessage", "RecordingMarker"] where container.managedObjectModel.entitiesByName[entity] != nil {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "noteId == %@", (note.localNoteID ?? UUID()) as CVarArg)
            children += try context.fetch(request)
        }
        for child in children { context.delete(child) }
        context.delete(note)
        do { try save() }
        catch { context.rollback(); throw error }
    }

    public var context: NSManagedObjectContext { container.viewContext }
    public func chatMessages(noteID: UUID) throws -> [LocalChatMessage] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "NoteChatMessage")
        request.predicate = NSPredicate(format: "noteId == %@", noteID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return try context.fetch(request).compactMap { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let role = object.value(forKey: "role") as? String,
                  ["user", "assistant"].contains(role),
                  let text = object.value(forKey: "content") as? String else { return nil }
            return LocalChatMessage(id: id, role: role, content: text,
                timestamp: object.value(forKey: "timestamp") as? Date ?? .distantPast)
        }
    }
    public func saveChatMessage(_ message: LocalChatMessage, noteID: UUID) throws {
        let noteRequest = NSFetchRequest<NSManagedObject>(entityName: "Note")
        noteRequest.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)
        noteRequest.fetchLimit = 1
        guard ready, ["user", "assistant"].contains(message.role), !message.content.isEmpty,
              try !context.fetch(noteRequest).isEmpty else {
            throw LocalError.message("This note is unavailable. The answer was not saved.")
        }
        // Date() can have identical values for quick successive messages,
        // particularly in Simulator. Preserve append order after a reload.
        let lastRequest = NSFetchRequest<NSManagedObject>(entityName: "NoteChatMessage")
        lastRequest.predicate = NSPredicate(format: "noteId == %@", noteID as CVarArg)
        lastRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        lastRequest.fetchLimit = 1
        let previous = try context.fetch(lastRequest).first?.value(forKey: "timestamp") as? Date
        let timestamp = previous.map { max(message.timestamp, $0.addingTimeInterval(0.001)) } ?? message.timestamp
        let object = NSEntityDescription.insertNewObject(forEntityName: "NoteChatMessage", into: context)
        object.setValue(message.id, forKey: "id"); object.setValue(noteID, forKey: "noteId")
        object.setValue(message.role, forKey: "role"); object.setValue(message.content, forKey: "content")
        object.setValue(timestamp, forKey: "timestamp")
        do { try save() } catch { context.delete(object); throw error }
    }
    public func clearChat(noteID: UUID) throws {
        try save()
        let request = NSFetchRequest<NSManagedObject>(entityName: "NoteChatMessage")
        request.predicate = NSPredicate(format: "noteId == %@", noteID as CVarArg)
        for object in try context.fetch(request) { context.delete(object) }
        do { try save() } catch { context.rollback(); throw error }
    }
    public func notes() throws -> [NSManagedObject] {
        guard ready else { throw LocalError.message(errorMessage ?? "Local store is unavailable.") }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        return try context.fetch(request)
    }
    public func create(title: String, text: String = "", id: UUID = UUID(), noteType: String = "local") throws -> NSManagedObject {
        guard ready else { throw LocalError.message("Local store is unavailable.") }
        let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
        note.setValue(id, forKey: "id")
        note.setValue(Date(), forKey: "timestamp")
        note.setValue(title, forKey: "title")
        note.setValue(text, forKey: "transcription")
        note.setValue(noteType, forKey: "noteType")
        do { try save() }
        catch { context.delete(note); throw error }
        return note
    }
    /// Commit generated content together, restoring all affected values if the
    /// store rejects the save. Preserve other pending edits in the context.
    public func tagLibrary() throws -> [LocalTagCandidate] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Tag")
        request.relationshipKeyPathsForPrefetching = ["notes"]
        return try context.fetch(request).compactMap { tag in
            guard let name = tag.value(forKey: "name") as? String, !name.isEmpty else { return nil }
            return LocalTagCandidate(name: name, usageCount: (tag.value(forKey: "notes") as? NSSet)?.count ?? 0)
        }
    }
    public func saveNoteChanges(_ note: NSManagedObject, values: [String: Any], replacingTags: [String]? = nil) throws {
        try saveNoteChanges(note, values: values, replacingTags: replacingTags, autoFolder: nil)
    }

    func saveNoteChanges(_ note: NSManagedObject, values: [String: Any], replacingTags: [String]?,
                         autoFolder: LocalNoteFolder?) throws {
        guard ready, note.managedObjectContext === context, !note.isDeleted else {
            throw LocalError.message("This note is unavailable.")
        }
        guard values.keys.allSatisfy({ note.entity.attributesByName[$0] != nil }) else {
            throw LocalError.message("Generated content contains an unsupported note field.")
        }
        let previous = values.keys.map { ($0, note.value(forKey: $0)) }
        var previousTags: NSSet?
        var createdTags: [NSManagedObject] = []
        var createdFolder: NSManagedObject?
        var assignedFolder = false
        do {
            if let replacingTags {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Tag")
                request.relationshipKeyPathsForPrefetching = ["notes"]
                let existing = try context.fetch(request).sorted {
                    let lhs = ($0.value(forKey: "notes") as? NSSet)?.count ?? 0
                    let rhs = ($1.value(forKey: "notes") as? NSSet)?.count ?? 0
                    if lhs != rhs { return lhs > rhs }
                    return $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString
                }
                let library = existing.compactMap { tag -> LocalTagCandidate? in
                    guard let name = tag.value(forKey: "name") as? String else { return nil }
                    return LocalTagCandidate(name: name, usageCount: (tag.value(forKey: "notes") as? NSSet)?.count ?? 0)
                }
                var selected: [NSManagedObject] = []
                for name in LocalNoteTags.resolvedNames(replacingTags, library: library) {
                    if let tag = existing.first(where: { LocalNoteTags.key($0.text("name")) == LocalNoteTags.key(name) }) {
                        selected.append(tag)
                    } else {
                        let tag = NSEntityDescription.insertNewObject(forEntityName: "Tag", into: context)
                        tag.setValue(UUID(), forKey: "id"); tag.setValue(name, forKey: "name")
                        tag.setValue(name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined(), forKey: "canonicalName")
                        tag.setValue(Date(), forKey: "createdAt")
                        createdTags.append(tag); selected.append(tag)
                    }
                }
                previousTags = (note.value(forKey: "tags") as? NSSet)?.copy() as? NSSet ?? NSSet()
                note.setValue(NSSet(array: selected), forKey: "tags")
            }
            if let name = autoFolder?.name, note.value(forKey: "folder") == nil {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Folder")
                request.predicate = NSPredicate(format: "name ==[cd] %@", name)
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                request.fetchLimit = 1
                let folder: NSManagedObject
                if let existing = try context.fetch(request).first {
                    folder = existing
                } else {
                    folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: context)
                    folder.setValue(UUID(), forKey: "id")
                    folder.setValue(name, forKey: "name")
                    folder.setValue(Date(), forKey: "createdAt")
                    createdFolder = folder
                }
                note.setValue(folder, forKey: "folder")
                assignedFolder = true
            }
            for (key, value) in values { note.setValue(value, forKey: key) }
            try save()
        } catch {
            for (key, value) in previous { note.setValue(value, forKey: key) }
            if let previousTags { note.setValue(previousTags, forKey: "tags") }
            for tag in createdTags { context.delete(tag) }
            if assignedFolder { note.setValue(nil, forKey: "folder") }
            if let createdFolder { context.delete(createdFolder) }
            throw error
        }
    }
    public func save() throws {
        guard ready else { throw LocalError.message("Local store is unavailable; no changes were saved.") }
        if context.hasChanges { try context.save() }
    }
}

public extension NSManagedObject {
    func text(_ key: String) -> String { value(forKey: key) as? String ?? "" }
    var localNoteID: UUID? { value(forKey: "id") as? UUID }
}

public struct LocalUtterance: Codable, Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) {
        self.text = text; self.start = start; self.end = end
    }
}

/// Tentative results replace one another; only final results enter the durable transcript.
public struct LocalTranscript: Sendable {
    public private(set) var utterances: [LocalUtterance] = []
    public private(set) var tentative = ""
    public private(set) var tentativeStart: Double?
    public private(set) var tentativeEnd: Double?
    public init() {}
    public mutating func accept(text: String, start: Double, end: Double, final: Bool) {
        if final {
            tentative = ""; tentativeStart = nil; tentativeEnd = nil
            // A repeated final range replaces that range, rather than duplicating text.
            if let index = utterances.firstIndex(where: { abs($0.start - start) < 0.001 }) {
                utterances[index] = .init(text: text, start: start, end: end)
            } else { utterances.append(.init(text: text, start: start, end: end)) }
            utterances.sort { $0.start < $1.start }
        } else { tentative = text; tentativeStart = start; tentativeEnd = end }
    }
    public var text: String { utterances.map(\.text).joined(separator: " ") }
    public var displayText: String { [text, tentative].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// Jotley never saves audio. Removes audio left by earlier versions, confined to
/// the two legacy audio directories. Notes, transcripts and the database stay intact.
public enum LegacyAudioCleanup {
    public static func remove(in root: URL, fileManager: FileManager = .default) throws {
        for directory in ["Recordings", "DeletedRecordings"] {
            let url = root.appendingPathComponent(directory, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }
}
