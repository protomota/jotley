import SwiftUI

extension NotesListView {
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
            // Avoid double counting if a note somehow stores duplicate tag values.
            for tag in Set(note.tagNames) {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    // Helper struct to simplify type-checking by breaking up complex expressions
    struct NoteRowView: View {
        let note: Note
        let isSelected: Bool
        let toggleSelection: (Note, Bool) -> Void
        let prepareDelete: (Note) -> Void
        let topPadding: CGFloat
        let rowIndex: Int
        let isRecordingNote: Bool
        @Environment(\.colorScheme) private var colorScheme

        private var recordingBadgeIconColor: Color {
            Color.themePrimaryAccent
        }

        private var recordingBadgeBackgroundColor: Color {
            Color.white.opacity(colorScheme == .dark ? 0.95 : 1.0)
        }

        var body: some View {
            Button(action: {
                // This captures the current key modifiers from the global NSEvent
                let modifiers = NSEvent.modifierFlags
                let isCommandPressed = modifiers.contains(.command)
                toggleSelection(note, isCommandPressed)
            }) {
                NoteListRowView(
                    note: note,
                    isSelected: isSelected,
                    onDelete: { prepareDelete(note) }
                )
                .padding(.top, topPadding)
                .background(Color.themeContentBackground.clipShape(Rectangle()))
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .tint(Color.themePrimaryAccent)
            .accessibilityIdentifier("notesListNoteRow-\(rowIndex)")
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.themeTextSecondary.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.leading, 20)
                    .padding(.trailing, 14)
            }
            .overlay(alignment: .topTrailing) {
                if isRecordingNote {
                    ZStack {
                        Circle()
                            .fill(recordingBadgeBackgroundColor)
                            .frame(width: 15, height: 15)

                        Image(systemName: "mic.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(recordingBadgeIconColor)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.themePrimaryAccent.opacity(0.7), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.18), radius: 2, x: 0, y: 1)
                    .padding(.top, 5)
                    .padding(.trailing, 16)
                    .offset(x: 4, y: 4)
                    .zIndex(10)
                        .help("Active recording")
                        .accessibilityIdentifier("activeRecordingRowIcon")
                }
            }
        }
    }

}
