import SwiftUI
import CoreData
import UIKit

/// Represents an item in the unified Notes list - a saved transcript note
enum NotesListItem: Identifiable, Hashable {
    case note(Note)

    var id: String {
        switch self {
        case .note(let note):
            let fallbackID = note.objectID.uriRepresentation().absoluteString
            return "note-\(note.id?.uuidString ?? fallbackID)"
        }
    }

    var date: Date {
        switch self {
        case .note(let note):
            return note.timestamp ?? Date()
        }
    }

    static func == (lhs: NotesListItem, rhs: NotesListItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
