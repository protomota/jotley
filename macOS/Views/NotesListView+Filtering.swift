import SwiftUI

extension NotesListView {
    func noteMatchesSearch(_ note: Note) -> Bool {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty {
            return true
        }

        let transcriptionMatch = note.transcription?.localizedCaseInsensitiveContains(search) ?? false
        let titleMatch = note.title?.localizedCaseInsensitiveContains(search) ?? false
        let tagsMatch = note.tagsAsString?.localizedCaseInsensitiveContains(search) ?? false
        return transcriptionMatch || titleMatch || tagsMatch
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
    /// if the list has content to show.
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
            filteredNoteCount: filteredNotes.count,
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

    var groupedNotes: [(Date, [Note])] {
        // When sorting by title or tag count, date grouping would fight the sort.
        // In those modes, collapse everything into a single unlabeled group so the list renders flat.
        if filterState.sortOption == .titleAZ
            || filterState.sortOption == .titleZA
            || filterState.sortOption == .mostTags {
            return filteredNotes.isEmpty ? [] : [(Date.distantFuture, filteredNotes)]
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredNotes) { note -> Date in
            calendar.startOfDay(for: note.timestampOrNow)
        }
        let ascending = filterState.sortOption == .dateOldest
        return grouped.sorted(by: { ascending ? $0.key < $1.key : $0.key > $1.key })
    }
}
