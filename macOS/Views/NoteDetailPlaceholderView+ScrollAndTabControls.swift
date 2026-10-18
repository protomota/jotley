import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {

    // Simple transcript tab button (for when not recording)
    var transcriptTabButton: some View {
        let isViewingTranscript = selectedTab == DetailTab.transcript.rawValue
        let isLoadingTranscript = viewModel.isTranscriptLoading(for: note)
        let iconColor = isViewingTranscript ? Color.white : Color.themePrimaryAccent
        let trackColor = isViewingTranscript ? Color.white.opacity(0.3) : Color.themePrimaryAccent.opacity(0.3)

        return Button {
            selectedTab = DetailTab.transcript.rawValue
        } label: {
            HStack(spacing: 8) {
                if isLoadingTranscript {
                    ZStack {
                        Circle()
                            .stroke(trackColor, lineWidth: 2)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0, to: 0.2)
                            .stroke(iconColor, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .rotationEffect(Angle(degrees: animatingTranscriptRotation))
                            .onAppear {
                                animatingTranscriptRotation = 0
                                withAnimation(Animation.linear(duration: TabLoadingAnimation.spinnerRotationDuration).repeatForever(autoreverses: false)) {
                                    animatingTranscriptRotation = 360
                                }
                            }
                            .onDisappear {
                                animatingTranscriptRotation = 0
                            }
                    }
                } else {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(iconColor)
                }
                Text("Transcript")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isViewingTranscript ? Color.themePrimaryAccent : Color.themePrimaryAccent.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .floatingTooltip("View Transcript")
        .accessibilityIdentifier("noteDetailTranscriptTab")
    }

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
