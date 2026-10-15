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
        .frame(height: 120)
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
        HStack(spacing: 40) {
            // Left placeholder for symmetry (keeps the main control centered)
            Color.clear
                .frame(width: 50, height: 50)

            // Pause/Resume button
            Button(action: toggleTranscriptionPause) {
                ZStack {
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 80, height: 80)
                        .shadow(color: buttonColor.opacity(0.4), radius: 10, x: 0, y: 4)

                    buttonIcon
                }
            }
            // Only disable if permission was explicitly denied, not if undetermined
            .disabled(transcriptionManager.busy || isFinishing)
            .scaleEffect(transcriptionManager.transcriptionState == .listening ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: transcriptionManager.transcriptionState)
            .accessibilityIdentifier("transcriptionPauseButton")
            .accessibilityLabel(transcriptionManager.transcriptionState == .listening ? "Pause transcription" : transcriptionManager.transcriptionState == .paused ? "Resume transcription" : "Try transcription again")

            // End/Stop button (only show when listening or paused, otherwise placeholder)
            if transcriptionManager.transcriptionState != .idle {
                Button(action: {
                    finishAndClose()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)

                        Image(systemName: "stop.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
                .disabled(transcriptionManager.busy || isFinishing)
                .accessibilityIdentifier("transcriptionStopButton")
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear
                    .frame(width: 50, height: 50)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: transcriptionManager.transcriptionState)
    }

    var buttonColor: Color {
        switch transcriptionManager.transcriptionState {
        case .idle:
            return Color.themePrimaryAccent
        case .listening:
            return Color.themePrimaryAccent
        case .paused:
            return Color.themePrimaryAccent
        }
    }

    @ViewBuilder
    var buttonIcon: some View {
        switch transcriptionManager.transcriptionState {
        case .idle:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 28, weight: .semibold)).foregroundColor(.white)
        case .listening:
            // Pause icon
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 8, height: 28)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 8, height: 28)
            }
        case .paused:
            Image(systemName: "play.fill")
                .font(.system(size: 28, weight: .semibold)).foregroundColor(.white)
        }
    }
}
