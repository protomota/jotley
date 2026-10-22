import SwiftUI

extension LiveTranscriptionView {
    // MARK: - Header

    var header: some View {
        HStack {
            Text(isResuming ? "Continue Transcription" : "Live Transcription")
                .font(.headline)
                .foregroundColor(.themeTextPrimary)
            Spacer()
            MobileDoneButton { finishAndClose() }
                .disabled(isFinishing)
                .accessibilityIdentifier("transcriptionCloseButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Waveform Section

    var waveformSection: some View {
        // The closure hands the manager to the waveform's own timer, which
        // pulls the level so this view doesn't re-render on every meter tick.
        LiveTranscriptionWaveformView(
            levelProvider: { [weak transcriptionManager] in transcriptionManager?.audioLevel ?? 0 },
            isTranscribing: transcriptionManager.transcriptionState == .listening,
            isPaused: transcriptionManager.transcriptionState == .paused
        )
    }

    // MARK: - Time Display

    var timeDisplay: some View {
        let seconds = max(0, Int(transcriptionManager.transcriptionDuration))
        return Text("\(seconds / 60)m \(seconds % 60)s")
            .font(.system(size: 56, weight: .light).monospacedDigit())
            .foregroundColor(.themeTextPrimary)
            .accessibilityIdentifier("transcriptionDurationText")
    }

    // MARK: - Transcription Controls

    var transcriptionControls: some View {
        HStack(spacing: 24) {
            Color.clear.frame(width: 44, height: 44)
            Button(action: toggleTranscriptionPause) {
                Image(systemName: transcriptionManager.transcriptionState == .listening ? "pause.fill" : transcriptionManager.transcriptionState == .paused ? "play.fill" : "arrow.clockwise")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.themePrimaryAccent)
            }
            .buttonStyle(JotleyGlassButtonStyle(circular: true))
            .disabled(transcriptionManager.busy || isFinishing)
            .accessibilityIdentifier("transcriptionPauseButton")
            .accessibilityLabel(transcriptionManager.transcriptionState == .listening ? "Pause transcription" : transcriptionManager.transcriptionState == .paused ? "Resume transcription" : "Try transcription again")

            if transcriptionManager.transcriptionState != .idle {
                Button(action: finishAndClose) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18)).foregroundStyle(Color.themePrimaryAccent)
                }
                .buttonStyle(JotleyGlassButtonStyle(circular: true))
                .disabled(transcriptionManager.busy || isFinishing)
                .accessibilityLabel("Stop transcription")
                .accessibilityIdentifier("transcriptionStopButton")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }
}
