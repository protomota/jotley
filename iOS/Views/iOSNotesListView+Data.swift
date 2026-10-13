import SwiftUI
import CoreData

extension NotesListView {
    func noteMatchesSearch(_ note: Note) -> Bool {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty {
            return true
        }
        return (note.title?.localizedCaseInsensitiveContains(search) ?? false) ||
            (note.summary?.localizedCaseInsensitiveContains(search) ?? false) ||
            (note.tagsAsString?.localizedCaseInsensitiveContains(search) ?? false)
    }

    func noteMatchesFolder(_ note: Note) -> Bool {
        switch filterState.selectedFolder {
        case .all:
            return true
        case .unfiled:
            return note.folder == nil
        case .folder(let id):
            return note.folder?.id == id
        }
    }

    func noteMatchesTagFilter(_ note: Note) -> Bool {
        if filterState.selectedTags.isEmpty {
            return true
        }
        let noteTags = Set(note.tagNames)
        switch filterState.tagMatchMode {
        case .any:
            return !filterState.selectedTags.isDisjoint(with: noteTags)
        case .all:
            return filterState.selectedTags.isSubset(of: noteTags)
        }
    }

    var filteredNotes: [Note] {
        let base = notes.filter { note in
            noteMatchesSearch(note) && noteMatchesFolder(note) && noteMatchesTagFilter(note)
        }
        return sortNotes(base)
    }

    /// Notes that belong to the currently selected folder, ignoring tag filters and search.
    /// Used to distinguish "the folder is empty" from "filters hid everything in the folder".
    var notesInSelectedFolder: [Note] {
        notes.filter { noteMatchesFolder($0) }
    }

    /// Which empty-state message the notes list should render right now, or `.none`
    /// if the list has content to show. Mirrors the macOS filter-state resolver so
    /// both platforms share the "no notes in folder" vs. "filters hiding notes" logic.
    var currentEmptyState: NotesListEmptyState {
        let isSpecificFolder: Bool
        switch filterState.selectedFolder {
        case .all:
            isSpecificFolder = false
        case .unfiled, .folder:
            isSpecificFolder = true
        }
        return NotesListEmptyState.resolve(
            totalNoteCount: notes.count,
            notesInSelectedFolderCount: notesInSelectedFolder.count,
            filteredNoteCount: combinedListItems.count,
            searchText: searchText,
            isSpecificFolderSelected: isSpecificFolder,
            hasTagFilter: filterState.hasTagFilter
        )
    }

    func sortNotes(_ notes: [Note]) -> [Note] {
        switch filterState.sortOption {
        case .dateNewest:
            return notes.sorted { $0.timestampOrNow > $1.timestampOrNow }
        case .dateOldest:
            return notes.sorted { $0.timestampOrNow < $1.timestampOrNow }
        case .titleAZ:
            return notes.sorted { $0.titleOrUntitled.localizedCaseInsensitiveCompare($1.titleOrUntitled) == .orderedAscending }
        case .titleZA:
            return notes.sorted { $0.titleOrUntitled.localizedCaseInsensitiveCompare($1.titleOrUntitled) == .orderedDescending }
        case .mostTags:
            return notes.sorted {
                let lhs = $0.tagNames.count
                let rhs = $1.tagNames.count
                if lhs != rhs { return lhs > rhs }
                return $0.timestampOrNow > $1.timestampOrNow
            }
        }
    }

    func getAllUniqueTags() -> [String] {
        var allTags = Set<String>()
        for note in notes {
            allTags.formUnion(note.tagNames)
        }
        return Array(allTags).sorted()
    }

    /// Count tags within search-matched notes, independent of selected tag filters.
    func getTagCountsForVisibleResults() -> [String: Int] {
        var counts: [String: Int] = [:]
        for note in notes where noteMatchesSearch(note) {
            for tag in Set(note.tagNames) {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    var combinedListItems: [NotesListItem] { filteredNotes.map { .note($0) } }

    /// Group items by date for section headers
    var groupedItems: [(Date, [NotesListItem])] {
        // Non-date sort modes collapse into a single unlabeled group.
        if filterState.sortOption == .titleAZ
            || filterState.sortOption == .titleZA
            || filterState.sortOption == .mostTags {
            return combinedListItems.isEmpty ? [] : [(Date.distantFuture, combinedListItems)]
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: combinedListItems) { item in
            calendar.startOfDay(for: item.date)
        }
        let ascending = filterState.sortOption == .dateOldest
        return grouped.sorted { ascending ? $0.key < $1.key : $0.key > $1.key }
    }

    func formatDateSectionHeader(_ date: Date) -> String {
        // Sentinel used by non-date sort modes — render an empty header label.
        if date == .distantFuture { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "E, MMM d"
            return formatter.string(from: date)
        }
    }

    func deleteItemsInGroup(at offsets: IndexSet, from itemsInGroup: [NotesListItem]) {
        for index in offsets {
            if case .note(let note) = itemsInGroup[index] {
                do { try transcriptionManager.delete(note) } catch { transcriptionManager.errorMessage = error.localizedDescription }
            }
        }
    }
}
