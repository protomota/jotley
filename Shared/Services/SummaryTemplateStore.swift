import Foundation
import Combine
import CryptoKit

/// A detached definition is captured when generation starts, so editing a
/// template cannot change an in-flight or recovered summary.
public struct SummaryTemplateDefinition: Codable, Equatable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let prompt: String
    public var id: String { key }
    public var isCustom: Bool { key.hasPrefix("custom/") }
    public init(key: String, title: String, prompt: String) {
        self.key = key; self.title = title; self.prompt = prompt
    }
    public init(_ builtIn: LocalSummaryTemplate) {
        self.init(key: builtIn.key, title: builtIn.title, prompt: builtIn.prompt)
    }
}

public struct CustomSummaryTemplate: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var instructions: String
    public let createdAt: Date
    public var updatedAt: Date
    public var deleted: Bool
    public var key: String { "custom/" + id.uuidString.lowercased() }
    public var definition: SummaryTemplateDefinition { .init(key: key, title: name, prompt: instructions) }
    public var revision: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}

/// Small user-authored preferences use native iCloud key/value sync, one key
/// per template. Local copies and deletion tombstones survive offline edits.
/// The note database and its CloudKit schema are unchanged.
@MainActor
public final class SummaryTemplateStore: NSObject, ObservableObject {
    public static let shared = SummaryTemplateStore(
        defaults: .standard,
        cloud: NoteSyncMode.application().isEnabled ? .default : nil)
    public static let nameLimit = 60
    public static let instructionByteLimit = 2000
    public static let templateLimit = 100
    private static let localKey = "jotleyCustomSummaryTemplates.v1"
    private static let cloudPrefix = "jotley.summary-template."
    @Published public private(set) var templates: [CustomSummaryTemplate] = []
    @Published public private(set) var storageError: String?
    public let syncEnabled: Bool
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var records: [CustomSummaryTemplate] = []
    private var unreadable = false

    public init(defaults: UserDefaults, cloud: NSUbiquitousKeyValueStore? = nil) {
        self.defaults = defaults; self.cloud = cloud; self.syncEnabled = cloud != nil
        super.init()
        if let data = defaults.data(forKey: Self.localKey) {
            do { records = try JSONDecoder().decode([CustomSummaryTemplate].self, from: data) }
            catch { unreadable = true; storageError = "Your saved templates could not be read. The original data was preserved." }
        }
        refresh()
        if let cloud {
            NotificationCenter.default.addObserver(self, selector: #selector(cloudChanged(_:)),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud)
            cloud.synchronize()
            mergeCloud()
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    public var definitions: [SummaryTemplateDefinition] {
        LocalSummaryTemplate.allCases.map(SummaryTemplateDefinition.init) + templates.map(\.definition)
    }
    public func resolve(_ key: String?) throws -> SummaryTemplateDefinition {
        if let key, key.hasPrefix("custom/") {
            guard let value = templates.first(where: { $0.key == key }) else {
                throw LocalError.message("This custom template is unavailable. Choose another template; the saved summary is unchanged.")
            }
            return value.definition
        }
        return .init(LocalSummaryTemplate.resolve(key))
    }
    public func title(for key: String?) -> String {
        (try? resolve(key).title) ?? "Template unavailable"
    }
    @discardableResult
    public func save(id: UUID? = nil, name: String, instructions: String, expectedRevision: String? = nil) throws -> CustomSummaryTemplate {
        guard !unreadable else { throw LocalError.message(storageError ?? "The saved template library could not be read.") }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= Self.nameLimit else { throw LocalError.message("Enter a template name of 1–\(Self.nameLimit) characters.") }
        guard !instructions.isEmpty, instructions.utf8.count <= Self.instructionByteLimit else {
            throw LocalError.message("Enter instructions of 1–\(Self.instructionByteLimit) UTF-8 bytes. Short instructions leave room for your note in the on-device model.")
        }
        guard !templates.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            throw LocalError.message("A template with this name already exists.")
        }
        let old: CustomSummaryTemplate?
        if let id {
            guard let found = templates.first(where: { $0.id == id }), found.revision == expectedRevision else {
                throw LocalError.message("This template changed or was deleted. Reopen it before saving.")
            }
            old = found
        } else {
            guard templates.count < Self.templateLimit else { throw LocalError.message("You can save up to \(Self.templateLimit) custom templates.") }
            guard records.count < 900 else { throw LocalError.message("The template library has reached its iCloud storage limit. Edit an existing template instead.") }
            old = nil
        }
        let now = Date()
        let record = CustomSummaryTemplate(id: old?.id ?? UUID(), name: name, instructions: instructions,
            createdAt: old?.createdAt ?? now, updatedAt: now, deleted: false)
        try replace(record)
        return record
    }
    public func delete(id: UUID, expectedRevision: String) throws {
        guard var record = templates.first(where: { $0.id == id }), record.revision == expectedRevision else {
            throw LocalError.message("This template changed or was deleted. Reopen it before deleting.")
        }
        record.deleted = true; record.updatedAt = Date()
        // Retain only a small tombstone, not the deleted instructions. This
        // prevents stale devices resurrecting deletions without using the
        // iCloud quota for the full history of removed prompts.
        record.name = ""; record.instructions = ""
        try replace(record)
    }
    private func replace(_ record: CustomSummaryTemplate) throws {
        var next = records.filter { $0.id != record.id }; next.append(record)
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.localKey)
        records = next; refresh()
        if let cloud {
            cloud.set(try JSONEncoder().encode(record), forKey: Self.cloudPrefix + record.id.uuidString.lowercased())
            cloud.synchronize()
        }
    }
    private func refresh() {
        templates = records.filter { !$0.deleted }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    struct BackupImport {
        let records: [CustomSummaryTemplate]
        let data: Data
        let added: Int
    }

    func backupRecords() throws -> [CustomSummaryTemplate] {
        guard !unreadable else { throw LocalError.message("Your saved templates could not be read. The original data was preserved.") }
        return templates
    }

    /// Prepare before saving the note transaction. Existing IDs (including
    /// deletion tombstones) win; no current prompt is replaced by an import.
    func prepareBackupImport(_ incoming: [CustomSummaryTemplate]) throws -> BackupImport {
        guard !unreadable else { throw LocalError.message(storageError ?? "The saved template library could not be read.") }
        var merged = records
        let existingIDs = Set(records.map(\.id))
        var names = templates.map(\.name)
        var added = 0
        for var record in incoming where !existingIDs.contains(record.id) {
            let original = record.name
            var suffix = 1
            while names.contains(where: { $0.compare(record.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                let ending = suffix == 1 ? " (restored)" : " (restored \(suffix))"
                record.name = String(original.prefix(Self.nameLimit - ending.count)) + ending
                suffix += 1
            }
            names.append(record.name); merged.append(record); added += 1
        }
        guard merged.filter({ !$0.deleted }).count <= Self.templateLimit, merged.count < 900 else {
            throw LocalError.message("Restoring these templates would exceed the template library limit. No data was changed.")
        }
        return BackupImport(records: merged, data: try JSONEncoder().encode(merged), added: added)
    }

    func applyBackupImport(_ plan: BackupImport) {
        defaults.set(plan.data, forKey: Self.localKey)
        records = plan.records
        refresh()
        if let cloud {
            for record in records {
                if let data = try? JSONEncoder().encode(record) {
                    cloud.set(data, forKey: Self.cloudPrefix + record.id.uuidString.lowercased())
                }
            }
            cloud.synchronize()
        }
    }
    @objc private func cloudChanged(_ notification: Notification) {
        if let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
           reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            storageError = "iCloud template storage is full. Your local templates are preserved."
            return
        }
        mergeCloud()
    }
    private func mergeCloud() {
        guard let cloud, !unreadable else { return }
        var merged = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(Self.cloudPrefix) {
            guard let data = value as? Data, let remote = try? JSONDecoder().decode(CustomSummaryTemplate.self, from: data),
                  key == Self.cloudPrefix + remote.id.uuidString.lowercased(), remote.name.count <= Self.nameLimit,
                  remote.instructions.utf8.count <= Self.instructionByteLimit else { continue }
            if let local = merged[remote.id], local.updatedAt > remote.updatedAt || (local.updatedAt == remote.updatedAt && local.revision >= remote.revision) { continue }
            merged[remote.id] = remote
        }
        records = Array(merged.values)
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.localKey) }
        refresh()
        for record in records {
            let key = Self.cloudPrefix + record.id.uuidString.lowercased()
            if let data = try? JSONEncoder().encode(record), cloud.data(forKey: key) != data { cloud.set(data, forKey: key) }
        }
    }
}
