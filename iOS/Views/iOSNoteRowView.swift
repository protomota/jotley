import SwiftUI
import UIKit

struct NoteRowView: View {
    @ObservedObject var note: Note
    var isSelected: Bool = false
    @ObservedObject private var themeManager = ThemeManager.shared
    @EnvironmentObject private var transcriptionManager: LiveTranscriptionManager
    @Environment(\.colorScheme) var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var phoneTitleSize = 17
    @ScaledMetric(relativeTo: .footnote) private var phonePreviewSize = 15

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private var hasRenderedSummary: Bool {
        guard let summary = note.summary?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !summary.isEmpty &&
            summary != "Generating summary..." &&
            summary != "Transcription in progress..."
    }

    private var hasUsableTranscription: Bool {
        let transcription = note.transcription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !transcription.isEmpty else { return false }

        return transcription != "Transcribing audio..." &&
            transcription != "Loading transcript..." &&
            transcription != "Loading content..." &&
            transcription != "Transcription in progress..." &&
            !transcription.hasPrefix("Transcription failed:")
    }

    private var shouldShowGeneratingIcon: Bool { transcriptionManager.summaryNoteID == note.id }

    @ViewBuilder
    private var statusIconView: some View {
        if shouldShowGeneratingIcon {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.themePrimaryAccent)
                .accessibilityIdentifier("noteRowGeneratingIcon")
        }
    }

    /// Get a preview snippet from summary or transcription.
    private var previewText: String {
        if hasRenderedSummary, let summary = note.summary {
            return summary.previewSnippet()
        } else if hasUsableTranscription, let transcription = note.transcription {
            return transcription.previewSnippet()
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isPhone ? 4 : 2) {
            // Title - bold like Apple Notes
            Text(note.title ?? "Untitled")
                .font(isPhone ? .system(size: phoneTitleSize, weight: .semibold) : .subheadline.weight(.semibold))
                .foregroundColor(Color.themeTextPrimary)
                .lineLimit(1)
                .accessibilityIdentifier("noteRowTitle")

            // Date and preview on same line, like Apple Notes
            HStack(spacing: 6) {
                Text(note.timestamp ?? Date(), style: hasRenderedSummary ? .time : .date)
                    .font(isPhone ? .system(size: phonePreviewSize) : .footnote)
                    .foregroundColor(Color.themeTextSecondary)
                    .accessibilityIdentifier("noteRowTimestamp")

                statusIconView

                if !previewText.isEmpty {
                    Text(previewText)
                        .font(isPhone ? .system(size: phonePreviewSize) : .footnote)
                        .foregroundColor(Color.themeTextSecondary.opacity(0.8))
                        .lineLimit(1)

                }
            }
        }
        .accessibilityIdentifier("noteRow")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, isPhone ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.themePrimaryAccent.opacity(0.3) : Color.themeContentBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.themePrimaryAccent : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
