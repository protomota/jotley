import SwiftUI

extension LiveTranscriptionView {
    // MARK: - Header

    var header: some View {
        HStack {
            Text(isResuming ? "Continue Transcription" : "Live Transcription")
                .font(.headline)
                .foregroundColor(.themeTextPrimary)
            Spacer()
            Button("Done") { finishAndClose() }
                .jotleyDismissButtonStyle()
                .disabled(isFinishing)
                .accessibilityIdentifier("transcriptionCloseButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Waveform Section

    var waveformSection: some View {
        // The closure hands the manager to the waveform's own timer, which
        // pulls the level so this view doesn't re-render on every meter tick.
        LiveTranscriptionWaveformView(
            levelProvider: { [weak transcriptionManager] in transcriptionManager?.nextWaveformPeak() ?? 0 },
            isTranscribing: transcriptionManager.transcriptionState == .listening,
            isPaused: transcriptionManager.transcriptionState == .paused
        )
    }

    // MARK: - Time Display

    var recordingReadout: some View {
        let seconds = max(0, Int(transcriptionManager.transcriptionDuration))
        let state = transcriptionManager.transcriptionState
        let showsStatus = state != .idle || hasStartedTranscription
        return HStack(spacing: 12) {
            Text(state == .listening ? "Transcribing" : state == .paused ? "Paused" : "Ready")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.themeTextSecondary)
                .opacity(showsStatus ? 1 : 0)
                .accessibilityHidden(!showsStatus)
                .accessibilityIdentifier("transcriptionStatusText")
            Text("\(seconds / 60)m \(seconds % 60)s")
                .font(.system(size: 34, weight: .light).monospacedDigit())
                .foregroundStyle(Color.themeTextPrimary)
                .accessibilityIdentifier("transcriptionDurationText")
        }
    }

    // MARK: - Transcription Controls

    var transcriptionControls: some View {
        HStack(spacing: 24) {
            Color.clear.frame(width: 60, height: 60)
            Button(action: toggleTranscriptionPause) {
                Image(systemName: transcriptionManager.transcriptionState == .listening ? "pause.fill" : transcriptionManager.transcriptionState == .paused ? "play.fill" : "arrow.clockwise")
                    .font(.system(size: 30, weight: .semibold))
            }
            .buttonStyle(JotleyGlassButtonStyle(circular: true, diameter: 84))
            .disabled(transcriptionManager.busy || isFinishing)
            .accessibilityIdentifier("transcriptionPauseButton")
            .accessibilityLabel(transcriptionManager.transcriptionState == .listening ? "Pause transcription" : transcriptionManager.transcriptionState == .paused ? "Resume transcription" : "Try transcription again")

            if transcriptionManager.transcriptionState != .idle {
                Button(action: finishAndClose) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 22))
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(JotleyGlassButtonStyle(circular: true, diameter: 60))
                .disabled(transcriptionManager.busy || isFinishing)
                .accessibilityLabel("Stop transcription")
                .accessibilityIdentifier("transcriptionStopButton")
            } else {
                Color.clear.frame(width: 60, height: 60)
            }
        }
    }
}
