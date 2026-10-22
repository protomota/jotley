import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {

    var jumpToRecordingTabButton: some View {
        Button {
            viewModel.jumpToActiveRecordingNote()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.themePrimaryAccent)
                Text("Transcribing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.themePrimaryAccent)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color.themePrimaryAccent.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(Color.themePrimaryAccent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .floatingTooltip("Jump to active transcription")
        .accessibilityIdentifier("noteDetailJumpToRecordingTab")
    }

}
