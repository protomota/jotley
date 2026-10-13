import Combine
import Foundation
import SwiftUI

/// How multiple selected tags combine when filtering notes.
enum TagMatchMode: String, CaseIterable, Identifiable {
    case any
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any"
        case .all: return "All"
        }
    }

    var helpText: String {
        switch self {
        case .any: return "Match notes that have at least one selected tag"
        case .all: return "Match notes that have every selected tag"
        }
    }
}

/// How the notes list is sorted once filtering is applied.
enum NotesSortOption: String, CaseIterable, Identifiable {
    case dateNewest
    case dateOldest
    case titleAZ
    case titleZA
    case mostTags

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateNewest: return "Date (newest)"
        case .dateOldest: return "Date (oldest)"
        case .titleAZ:    return "Title A→Z"
        case .titleZA:    return "Title Z→A"
        case .mostTags:   return "Most tags"
        }
    }
}

/// Which folder (or pseudo-folder) the notes list is scoped to.
enum FolderSelection: Equatable {
    case all
    case unfiled
    case folder(UUID)
}

/// Shared observable filter + sort state driven by both platforms.
/// Persists non-folder preferences via AppStorage-backed raw values where practical;
/// folder scope is intentionally transient so it doesn't stick across launches.
final class FilterAndSortState: ObservableObject {
    @Published var selectedTags: Set<String> = []
    @Published var tagMatchMode: TagMatchMode = .any
    @Published var sortOption: NotesSortOption = .dateNewest
    @Published var selectedFolder: FolderSelection = .all

    /// True when any filter OR non-default sort is active — used to highlight the toolbar button.
    /// Folder selection is treated as navigation, not filtering, so it does not count here.
    var isActive: Bool {
        !selectedTags.isEmpty
            || sortOption != .dateNewest
            || tagMatchMode != .any
    }

    /// True when tag filter specifically is active (used to toggle the tag icon fill).
    var hasTagFilter: Bool {
        !selectedTags.isEmpty
    }

    func clearAll() {
        selectedTags.removeAll()
        tagMatchMode = .any
        sortOption = .dateNewest
        // Folder intentionally preserved — clearing tag filters should not navigate away from the selected folder.
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

/// Which empty-state message (if any) the notes list should render.
///
/// Extracted into a pure function so the decision can be unit-tested without
/// having to stand up a Core Data stack or SwiftUI environment.
enum NotesListEmptyState: Equatable {
    /// Render the notes list normally.
    case none
    /// The entire Core Data store has no notes.
    case noNotesYet
    /// An active search returned zero matches, but notes exist elsewhere.
    case noSearchResults
    /// A specific folder is selected and that folder itself contains zero notes.
    /// Clearing tag filters will not help — the folder is genuinely empty.
    case noNotesInFolder
    /// A tag filter (or non-All folder + tag combo) hides notes that do exist in the current scope.
    /// Clearing filters would reveal notes.
    case filtersHidingNotes

    /// Decide which empty state to show given the full filter pipeline state.
    ///
    /// Precedence, top to bottom:
    ///   1. Active search with zero matches — "No Results for ...".
    ///   3. Entire store empty and sync is done (or not applicable) — "No Notes Yet".
    ///   4. A specific folder is selected and has zero notes of its own — "No notes in folder".
    ///      (Clearing tag filters won't reveal anything, so this wins over `filtersHidingNotes`.)
    ///   5. Filters (tag filter, or a specific folder with notes that are all filtered out) hide
    ///      the remaining notes — "Filters are hiding notes".
    ///   6. Otherwise — `.none`, render the list.
    static func resolve(
        totalNoteCount: Int,
        notesInSelectedFolderCount: Int,
        filteredNoteCount: Int,
        searchText: String,
        isSpecificFolderSelected: Bool,
        hasTagFilter: Bool
    ) -> NotesListEmptyState {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if filteredNoteCount == 0 && !trimmedSearch.isEmpty && totalNoteCount > 0 {
            return .noSearchResults
        }

        if totalNoteCount == 0 {
            return .noNotesYet
        }

        if filteredNoteCount == 0 && isSpecificFolderSelected && notesInSelectedFolderCount == 0 {
            return .noNotesInFolder
        }

        if filteredNoteCount == 0 && (hasTagFilter || isSpecificFolderSelected) {
            return .filtersHidingNotes
        }

        return .none
    }
}
