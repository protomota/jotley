import SwiftUI

struct iOSNotesListEmptyStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.themePrimaryAccent.opacity(0.14))
                    .frame(width: 84, height: 84)

                Circle()
                    .stroke(Color.themePrimaryAccent.opacity(0.35), lineWidth: 1)
                    .frame(width: 96, height: 96)

                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.themePrimaryAccent)
            }

            VStack(spacing: 6) {
                Text("No Notes Yet")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.themeTextPrimary)

                Text("Transcribe a thought or conversation to get started.")
                    .font(.subheadline)
                    .foregroundColor(.themeTextSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.themePrimaryAccent)

                Text("Tap the + button in the bottom-right to start live transcription.")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.themeTextPrimary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.themeBackground.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.themePrimaryAccent.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.themeContentBackground.opacity(0.95),
                    Color.themeBackground.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.themePrimaryAccent.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.themePrimaryAccent.opacity(0.12), radius: 8, x: 0, y: 4)
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
