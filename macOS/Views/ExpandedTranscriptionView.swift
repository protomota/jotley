import SwiftUI
import AppKit
import Combine

/// Window-local controls stay available while the user browses any note.
struct MacCompactTranscriptionBar: View {
    @ObservedObject var viewModel: NotesListViewModel
    var body: some View {
        MacTranscriptionControls(timerText: timerText, isPaused: viewModel.isTranscriptionPaused,
            isBusy: viewModel.operationInProgress, recorder: viewModel.recorder,
            onPause: { Task { await viewModel.resumeTranscription() } },
            onStop: { Task { await viewModel.stopRecording() } })
            .accessibilityIdentifier("macCompactTranscriptionBar")
    }
    private var timerText: String {
        let seconds = Int(viewModel.recorder.elapsedTime)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct MacTranscriptionControls: View {
    let timerText: String
    let isPaused: Bool
    var isBusy = false
    var recorder: ProcessTapRecorder? = nil
    let onPause: () -> Void
    let onStop: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            if let recorder {
                MacCompactTranscriptionIndicator(recorder: recorder, isPaused: isPaused)
                    .frame(width: 22, height: 24).accessibilityLabel("Live audio waveform")
            } else {
                RecordingIndicator(appIcon: nil, isRecording: true, audioLevel: 0.1, size: 22, isPaused: isPaused)
                    .frame(width: 22, height: 24)
            }
            Rectangle().fill(Color.themeAccent.opacity(0.35)).frame(width: 1, height: 18)
            Text(timerText).font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.themeTextPrimary).fixedSize()
            Button(action: onPause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .foregroundStyle(Color.themePrimaryAccent)
            }.buttonStyle(JotleyGlassButtonStyle(circular: true)).accessibilityLabel(isPaused ? "Continue Transcription" : "Pause Transcription")
                .accessibilityIdentifier("macLiveTranscriptionPauseButton")
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.themePrimaryAccent)
            }.buttonStyle(JotleyGlassButtonStyle()).accessibilityLabel("Stop Transcription")
                .accessibilityIdentifier("macLiveTranscriptionStopButton")
        }.disabled(isBusy).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.themeContentBackground.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(Color.themeAccent.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}

/// A user scroll suspends following until they return to the transcript's end.
struct MacTranscriptFollowState {
    private(set) var isFollowing = true
    private(set) var isUserScrolling = false
    private(set) var isAtBottom = true
    var shouldFollow: Bool { isFollowing && !isUserScrolling }
    mutating func scrollPhaseChanged(isUserScrolling: Bool) {
        if isUserScrolling {
            self.isUserScrolling = true
            isFollowing = false
        } else if self.isUserScrolling {
            self.isUserScrolling = false
            isFollowing = isAtBottom
        }
    }
    mutating func bottomChanged(_ atBottom: Bool) {
        isAtBottom = atBottom
        if !isUserScrolling && atBottom { isFollowing = true }
    }
}

// Reuse the original three-bar indicator. Meter ticks stay local to this small
// view, rather than invalidating the note list and transcript on every sample.
private struct MacCompactTranscriptionIndicator: View {
    let recorder: ProcessTapRecorder
    let isPaused: Bool
    @State private var level: Float = 0
    @State private var meter = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    var body: some View {
        RecordingIndicator(appIcon: recorder.icon, isRecording: true,
                           audioLevel: isPaused ? 0 : level, size: 22, isPaused: isPaused)
            .onReceive(meter) { _ in level = recorder.currentAudioLevel }
    }
}
