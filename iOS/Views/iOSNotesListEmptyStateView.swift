import SwiftUI

struct iOSNotesListEmptyStateView: View {
    var body: some View {
        ContentUnavailableView("No notes yet", systemImage: "note.text",
            description: Text("New transcripts and summaries will appear here."))
            .foregroundStyle(Color.themeTextPrimary)
            .padding(.vertical, 26)
            .accessibilityIdentifier("notesListEmptyState")
    }
}

struct iOSNoNotesInFolderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundColor(.themePrimaryAccent)
            Text("No notes in this folder")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.themeTextPrimary)
            Text("Create a note here, or pick another folder from the drawer.")
                .font(.subheadline)
                .foregroundColor(.themeTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("notesListNoNotesInFolder")
    }
}

/// Shown when filters hide every note in the current scope (tag filter active,
/// or folder + tag combo with no matches). Mirrors the macOS `filtersHidingNotes`
/// state: message plus a "Clear Filters" button that wipes tags/sort while
/// preserving the folder selection.
struct iOSFiltersHidingNotesView: View {
    @ObservedObject var filterState: FilterAndSortState

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundColor(.themePrimaryAccent)
            Text("Filters are hiding notes")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.themeTextPrimary)
            Text("Your current filters match no notes in this view.")
                .font(.subheadline)
                .foregroundColor(.themeTextSecondary)
                .multilineTextAlignment(.center)
            Button {
                filterState.clearAll()
            } label: {
                Text("Clear Filters").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(JotleyGlassButtonStyle())
            .accessibilityIdentifier("notesListClearFiltersButton")
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("notesListFiltersHidingNotes")
    }
}

// MARK: - Active Transcription

struct ActiveTranscriptionJumpRowView: View {
    @ObservedObject var recorder: LiveTranscriptionManager
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").foregroundColor(.themePrimaryAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(recorder.transcriptionState == .paused ? "Transcription Paused" : "Transcribing Live").font(.subheadline.weight(.semibold))
                Text("Tap to return to transcription").font(.caption).foregroundColor(.themeTextSecondary)
            }
            Spacer()
            Text("\(Int(recorder.transcriptionDuration) / 60)m \(Int(recorder.transcriptionDuration) % 60)s").font(.caption.monospacedDigit())
            Image(systemName: "chevron.right").font(.caption)
        }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.themeContentBackground))
    }
}
