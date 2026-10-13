import Foundation
import CoreData
import Combine
import AVFoundation
import CloudKit

/// CloudKit uses signed app entitlements and the user's iCloud account, never API keys.
public enum NoteSyncMode: Equatable {
    case localOnly
    case privateICloud(containerIdentifier: String)

    public static let preferenceKey = "jotleyPrivateICloudSyncEnabled"
    public static let containerInfoKey = "JotleyCloudKitContainerIdentifier"

    public static func configuredIdentifier(in info: [String: Any]) -> String? {
        guard let value = info[containerInfoKey] as? String,
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
    public static func root() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask, appropriateFor: nil, create: true)
        let root = base.appendingPathComponent("JotleyLocalDevelopment", isDirectory: true)
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

    public init(root: URL? = nil, inMemory: Bool = false, model: NSManagedObjectModel? = nil,
                syncMode: NoteSyncMode = .localOnly) throws {
        self.syncMode = inMemory ? .localOnly : syncMode
        self.root = try root ?? (inMemory ? FileManager.default.temporaryDirectory.appendingPathComponent("JotleyPreview-\(UUID().uuidString)") : LocalPaths.root())
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        let resolvedModel: NSManagedObjectModel
        if let model { resolvedModel = model }
        else {
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            guard let url = bundle.url(forResource: "JotleyNotes", withExtension: "momd"),
                  let bundled = NSManagedObjectModel(contentsOf: url) else {
                throw LocalError.message("The bundled notes model could not be loaded. No data was changed.")
            }
            resolvedModel = bundled
        }
        if self.syncMode.isEnabled {
            container = NSPersistentCloudKitContainer(name: "JotleyNotes", managedObjectModel: resolvedModel)
        } else {
            container = NSPersistentContainer(name: "JotleyNotes", managedObjectModel: resolvedModel)
        }
        let description = try self.syncMode.storeDescription(at: self.root.appendingPathComponent("JotleyNotes.sqlite"), inMemory: inMemory)
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
        if ready && !inMemory { try resolveRecordingDeletions() }
    }

    /// One capture owner per store, independent of which window initiated it.
    public func beginRecording(_ note: NSManagedObject) throws -> UUID {
        guard ready, note.managedObjectContext === context, !note.isDeleted else {
            throw LocalError.message("This note is unavailable.")
        }
        guard activeRecording == nil else { throw LocalError.message("Finish the current recording first.") }
        if note.objectID.isTemporaryID { try context.obtainPermanentIDs(for: [note]) }
        let lease = UUID()
        activeRecording = (note.objectID, lease)
        return lease
    }
    public func endRecording(lease: UUID) {
        if activeRecording?.lease == lease { activeRecording = nil }
    }

    /// Move audio out of recovery's namespace before committing deletion. A crash
    /// before the database commit restores it; after commit, launch purges it.
    public func deleteNoteAndAudio(_ note: NSManagedObject) throws {
        guard note.managedObjectContext === context, !note.isDeleted else {
            throw LocalError.message("This note is unavailable.")
        }
        guard activeRecording?.noteID != note.objectID else {
            throw LocalError.message("Stop this recording before deleting its note.")
        }
        try save() // Rollback below must not discard unrelated pending edits.
        let id = note.localNoteID
        let chatRequest = NSFetchRequest<NSManagedObject>(entityName: "NoteChatMessage")
        chatRequest.predicate = NSPredicate(format: "noteId == %@", (id ?? UUID()) as CVarArg)
        let chat = container.managedObjectModel.entitiesByName["NoteChatMessage"] == nil ? [] : try context.fetch(chatRequest)
        let source = id.map { root.appendingPathComponent("Recordings/\($0.uuidString)") }
        let pending = id.map { root.appendingPathComponent("DeletedRecordings/\($0.uuidString)") }
        var moved = false
        if let source, let pending, FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.createDirectory(at: pending.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: pending)
            moved = true
        }
        for message in chat { context.delete(message) }
        context.delete(note)
        do { try save() }
        catch {
            context.rollback()
            if moved, let source, let pending {
                do { try FileManager.default.moveItem(at: pending, to: source) }
                catch {
                    throw LocalError.message("Note deletion failed. Its audio is preserved in local recovery storage and will be restored on launch: \(error.localizedDescription)")
                }
            }
            throw error
        }
        if moved, let pending {
            do { try FileManager.default.removeItem(at: pending) }
            catch { throw LocalError.message("The note was deleted. Audio cleanup remains pending locally and will retry on launch: \(error.localizedDescription)") }
        }
    }
    public func resolveRecordingDeletions() throws {
        let pendingRoot = root.appendingPathComponent("DeletedRecordings")
        guard FileManager.default.fileExists(atPath: pendingRoot.path) else { return }
        for pending in try FileManager.default.contentsOfDirectory(at: pendingRoot, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: pending.lastPathComponent) else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if try context.fetch(request).isEmpty {
                try FileManager.default.removeItem(at: pending)
            } else {
                let source = root.appendingPathComponent("Recordings/\(id.uuidString)")
                guard !FileManager.default.fileExists(atPath: source.path) else {
                    throw LocalError.message("Recording recovery found two copies for one note. Both were preserved for review.")
                }
                try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: pending, to: source)
            }
        }
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
    public func saveNoteChanges(_ note: NSManagedObject, values: [String: Any]) throws {
        guard ready, note.managedObjectContext === context, !note.isDeleted else {
            throw LocalError.message("This note is unavailable.")
        }
        guard values.keys.allSatisfy({ note.entity.attributesByName[$0] != nil }) else {
            throw LocalError.message("Generated content contains an unsupported note field.")
        }
        let previous = values.keys.map { ($0, note.value(forKey: $0)) }
        for (key, value) in values { note.setValue(value, forKey: key) }
        do { try save() }
        catch {
            for (key, value) in previous { note.setValue(value, forKey: key) }
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

public struct LocalRecordingManifest: Codable, Sendable {
    public let noteID: UUID
    public let createdAt: Date
    public var sampleRate: Double
    public var complete: Bool
    public init(noteID: UUID, sampleRate: Double) {
        self.noteID = noteID; self.createdAt = Date(); self.sampleRate = sampleRate; self.complete = false
    }
}

/// Persist PCM first. Audio reconstruction and inference can fail without destroying capture.
/// A crash leaves a recoverable raw file; its actual byte count is the authoritative duration.
public final class DurableAudioWriter: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private var manifest: LocalRecordingManifest
    private var lastSync = Date()
    public init(directory: URL, noteID: UUID, sampleRate: Double) throws {
        self.directory = directory
        manifest = LocalRecordingManifest(noteID: noteID, sampleRate: sampleRate)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let raw = directory.appendingPathComponent("audio.float32")
        // Never truncate an existing recording.
        guard !FileManager.default.fileExists(atPath: raw.path) else {
            throw LocalError.message("Recording already exists; it was preserved.")
        }
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("recording.json"), options: .atomic)
        guard FileManager.default.createFile(atPath: raw.path, contents: nil) else {
            throw LocalError.message("Unable to create local audio file.")
        }
        handle = try FileHandle(forWritingTo: raw)
    }
    public func append(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw LocalError.message("Recording is closed.") }
        try handle.write(contentsOf: data)
        if Date().timeIntervalSince(lastSync) >= 1 { try handle.synchronize(); lastSync = Date() }
    }
    public func close() throws {
        lock.lock(); defer { lock.unlock() }
        if let handle { try handle.synchronize(); try handle.close(); self.handle = nil }
        manifest.complete = true
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("recording.json"), options: .atomic)
    }
    deinit { try? handle?.close() }

    public static func manifest(at directory: URL) throws -> LocalRecordingManifest {
        try JSONDecoder().decode(LocalRecordingManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("recording.json")))
    }
    public static func frameCount(at directory: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("audio.float32").path)
        return ((attributes[.size] as? NSNumber)?.int64Value ?? 0) / 4
    }
    /// Includes silence and every saved segment without reconstructing derived audio.
    public static func recordedDuration(in directory: URL) throws -> TimeInterval {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try children.reduce(0) { duration, segment in
            guard FileManager.default.fileExists(atPath: segment.appendingPathComponent("recording.json").path) else { return duration }
            let info = try manifest(at: segment)
            guard info.sampleRate.isFinite, info.sampleRate > 0 else {
                throw LocalError.message("Recording has an invalid audio format; raw audio was preserved.")
            }
            return duration + Double(try frameCount(at: segment)) / info.sampleRate
        }
    }
    /// A valid derived CAF is reusable. Rebuild only when raw capture has changed
    /// or the derived file is missing/corrupt, avoiding full copies during playback.
    public static func audioFile(at directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent("audio.caf")
        let info = try manifest(at: directory)
        if let audio = try? AVAudioFile(forReading: destination),
           audio.length == (try frameCount(at: directory)),
           audio.processingFormat.sampleRate == info.sampleRate,
           audio.processingFormat.channelCount == 1 {
            return destination
        }
        return try recover(at: directory)
    }
    /// Rebuild into a temporary CAF and atomically replace only the derived file on success.
    /// The raw capture and manifest are always retained, including on failure.
    public static func recover(at directory: URL) throws -> URL {
        let info = try manifest(at: directory)
        guard info.sampleRate.isFinite, info.sampleRate > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: info.sampleRate, channels: 1, interleaved: false) else {
            throw LocalError.message("Recording has an invalid audio format; raw audio was preserved.")
        }
        let raw = try FileHandle(forReadingFrom: directory.appendingPathComponent("audio.float32"))
        defer { try? raw.close() }
        let temporary = directory.appendingPathComponent("recovered-\(UUID().uuidString).caf")
        let destination = directory.appendingPathComponent("audio.caf")
        do {
            // Closing AVAudioFile before rename flushes the CAF header.
            do {
                let output = try AVAudioFile(forWriting: temporary, settings: format.settings)
                while let data = try raw.read(upToCount: 65536), !data.isEmpty {
                    let frames = data.count / 4 // Ignore a partial final sample after a crash.
                    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(frames)),
                          let pointer = buffer.floatChannelData?[0] else { continue }
                    buffer.frameLength = UInt32(frames)
                    data.withUnsafeBytes { bytes in
                        if let base = bytes.baseAddress { memcpy(pointer, base, frames * 4) }
                    }
                    try output.write(from: buffer)
                }
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: destination) }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
