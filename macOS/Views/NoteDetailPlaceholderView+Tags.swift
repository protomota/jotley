import SwiftUI

extension NoteDetailPlaceholderView {
    func removeTag(_ tagToRemove: String) {
        // Remove tag using the Tag entity system
        note.removeTagByName(tagToRemove)

        // Update currentTags binding to reflect the change
        currentTags = note.tagNames

        // Save the context
        saveContext()

    }
}
