import CoreData
import Foundation

public extension Folder {
    /// Display name with a safe fallback.
    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled Folder" : trimmed
    }

    /// Canonical form used for case-insensitive dedup.
    static func canonical(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Number of notes currently in this folder.
    var noteCount: Int {
        (notes as? Set<Note>)?.count ?? 0
    }

    /// Find an existing folder by name (case-insensitive), or return nil.
    static func find(named name: String, in context: NSManagedObjectContext) -> Folder? {
        let canonical = Folder.canonical(name)
        guard !canonical.isEmpty else { return nil }
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.fetchLimit = 1
        // We store `name` as-given but match case-insensitively.
        request.predicate = NSPredicate(format: "name ==[c] %@", canonical)
        return (try? context.fetch(request))?.first
    }

    /// Find-or-create a folder with the given name. Returns the folder without saving.
    @discardableResult
    static func getOrCreate(named name: String, in context: NSManagedObjectContext) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = find(named: trimmed, in: context) {
            return existing
        }
        // Use this context's entity when several isolated stores/models exist.
        let folder = NSEntityDescription.insertNewObject(forEntityName: "Folder", into: context) as! Folder
        folder.id = UUID()
        folder.name = trimmed
        folder.createdAt = Date()
        folder.sortOrder = 0
        return folder
    }
}
