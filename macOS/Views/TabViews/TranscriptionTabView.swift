import SwiftUI
import CoreData

enum TabLoadingAnimation {
    static let spinnerRotationDuration: Double = 1.0
}

struct TranscriptBubbleView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let text: String
    let timestampLabel: String?
    let isInterim: Bool
    @Environment(\.themeRefresh) private var themeRefresh

    // Simple heuristic: if text is longer than ~80 characters, it's likely multi-line
    private var isLikelyMultiLine: Bool {
        text.count > 80
    }

    private var bubbleTextColor: Color {
        // Depend on themeRefresh so color resolves again when appearance changes.
        _ = themeRefresh
        return Color.themeTextPrimary
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let timestampLabel, !timestampLabel.isEmpty {
                    Text(timestampLabel)
                        .font(.caption2)
                        .foregroundColor(Color.themeTextSecondary.opacity(0.8))
                }

                Text(text)
                    .foregroundColor(bubbleTextColor)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: isLikelyMultiLine ? .infinity : nil, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isInterim ? Color.gray.opacity(0.2) : Color.themePrimaryAccent.opacity(0.1))
            )

            if !isLikelyMultiLine {
                Spacer(minLength: 0)
            }
        }
    }
}
// View for the Transcript tab content
public struct TranscriptTabView: View {
    @ObservedObject var note: Note
    @Binding var editableTranscript: String
    @FocusState.Binding var isTranscriptEditorFocused: Bool
    /// Loading state supplied by the note coordinator.
    var isLoading: Bool = false
    var viewModel: NotesListViewModel?
    @Environment(\.themeRefresh) private var themeRefresh

    private var isRecordingThisNote: Bool {
        guard let vm = viewModel else { return false }
        return vm.recorder.isRecording &&
               vm.recorder.isRecordingNewNote &&
               vm.newNoteBeingRecorded == note
    }

    // Check if transcript is in loading state. Backed by the view model's
    // per-note loading flag rather than a persisted placeholder string.
    private var isTranscriptLoading: Bool {
        isLoading
    }

    // Get loading message based on note type
    private var loadingMessage: String { "Recovering transcript…" }
    private var loadingDetailMessage: String? { "Processing audio stored on this Mac." }
    private func getEmptyStateMessage() -> String {
        "Your transcript appears here as you speak. Use + to start a new transcription."
    }

    // Check if transcript has actual content (not just whitespace)
    private var hasActualContent: Bool {
        !editableTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        let _ = themeRefresh

        VStack(alignment: .leading, spacing: 0) {
            if isTranscriptLoading {
                // Loading state with animated spinner
                TranscriptLoadingView(
                    message: loadingMessage,
                    detailMessage: loadingDetailMessage
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isRecordingThisNote {
                let liveTranscript = (viewModel?.recorder.accumulatedTranscript ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let transcriptToDisplay = liveTranscript.isEmpty ? editableTranscript : (viewModel?.recorder.accumulatedTranscript ?? "")

                // Live transcription while recording.
                let liveUtterances = viewModel?.recorder.transcriptUtterances ?? []
                let utterancesForDisplay = liveUtterances.isEmpty ? note.transcriptUtterances : liveUtterances
                TranscriptParagraphsView(
                    transcript: transcriptToDisplay,
                    utterances: utterancesForDisplay,
                    interimText: viewModel?.recorder.latestTranscriptDelta ?? "",
                    isRecordingActive: true,
                    showEllipsis: true
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if hasActualContent {
                // Static transcript view - only show if there's actual content
                TranscriptParagraphsView(
                    transcript: editableTranscript,
                    utterances: note.transcriptUtterances,
                    interimText: "",
                    isRecordingActive: false,
                    showEllipsis: false
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Empty state - provide more context
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "mic.slash")
                        .font(.system(size: 48))
                        .foregroundColor(Color.themeTextSecondary.opacity(0.3))

                    Text("No transcript available")
                        .font(.headline)
                        .foregroundColor(Color.themeTextSecondary.opacity(0.7))

                    Text(getEmptyStateMessage())
                        .font(.body)
                        .foregroundColor(Color.themeTextSecondary.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
    }
}

struct TranscriptParagraphsView: View {
    let transcript: String
    let utterances: [TranscriptUtterance]
    let interimText: String
    let isRecordingActive: Bool
    let showEllipsis: Bool
    private let liveRecordingTimestampInterval: TimeInterval = 10.0
    private let minimumDisplayTimestampStart: TimeInterval = 1.0

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            let sourceUtterances = utterances.isEmpty
                ? TranscriptUtterance.fallbackUtterances(from: transcript)
                : TranscriptUtterance.deduplicated(utterances)
            let utteranceList = isRecordingActive
                ? TranscriptUtterance.coalescedForDisplay(sourceUtterances)
                : sourceUtterances
            let utterancesForDisplay = visibleTimestampedUtterances(from: utteranceList)

            ForEach(Array(utterancesForDisplay.enumerated()), id: \.offset) { index, item in
                TranscriptBubbleView(
                    text: item.utterance.text,
                    timestampLabel: item.timestampLabel,
                    isInterim: false
                )
                .id(index)
            }

            // Show interim transcript
            if !interimText.isEmpty {
                TranscriptBubbleView(
                    text: interimText,
                    timestampLabel: nil,
                    isInterim: true
                )
                .id("interim")
            }

            // Show ellipsis when recording
            if showEllipsis {
                AnimatedEllipsis()
                    .padding(.leading, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .id("ellipsis")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func visibleTimestampedUtterances(from utterances: [TranscriptUtterance]) -> [(utterance: TranscriptUtterance, timestampLabel: String?)] {
        guard !utterances.isEmpty else { return [] }

        if !isRecordingActive {
            return utterances.map { utterance in
                (utterance: utterance, timestampLabel: timestampLabel(for: utterance))
            }
        }

        var result: [(utterance: TranscriptUtterance, timestampLabel: String?)] = []
        var lastDisplayedTimestamp: Double? = nil

        for utterance in utterances {
            guard let start = utterance.start else {
                result.append((utterance: utterance, timestampLabel: nil))
                continue
            }

            let shouldShowTimestamp: Bool
            if start < minimumDisplayTimestampStart {
                shouldShowTimestamp = false
            } else if let lastTimestamp = lastDisplayedTimestamp {
                shouldShowTimestamp = (start - lastTimestamp) >= liveRecordingTimestampInterval
            } else {
                shouldShowTimestamp = true
            }

            let label = shouldShowTimestamp ? timestampLabel(for: utterance) : nil
            if shouldShowTimestamp {
                lastDisplayedTimestamp = start
            }

            result.append((utterance: utterance, timestampLabel: label))
        }

        return result
    }

    private func timestampLabel(for utterance: TranscriptUtterance) -> String? {
        guard let start = utterance.start else { return nil }
        return formatRelativeTime(start)
    }

    private func formatRelativeTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// Animated ellipsis component that shows recording activity
struct AnimatedEllipsis: View {
    @State private var opacity1: Double = 0.3
    @State private var opacity2: Double = 0.3
    @State private var opacity3: Double = 0.3

    private let dotSize: CGFloat = 6

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.themePrimaryAccent)
                .frame(width: dotSize, height: dotSize)
                .fixedSize()
                .opacity(opacity1)

            Circle()
                .fill(Color.themePrimaryAccent)
                .frame(width: dotSize, height: dotSize)
                .fixedSize()
                .opacity(opacity2)

            Circle()
                .fill(Color.themePrimaryAccent)
                .frame(width: dotSize, height: dotSize)
                .fixedSize()
                .opacity(opacity3)
        }
        .fixedSize()
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                opacity1 = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity2 = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity3 = 1.0
                }
            }
        }
    }
}

// Loading view with animated spinner for transcript imports
struct TranscriptLoadingView: View {
    let message: String
    var detailMessage: String? = nil
    var startedAt: Date? = nil
    var timeoutInterval: TimeInterval? = nil

    @State private var spinnerRotation: Double = 0

    var body: some View {
        // Use GeometryReader with explicit frame to enable Spacer centering inside ScrollView
        GeometryReader { geometry in
            VStack {
                Spacer()
                VStack(spacing: 20) {
                    // Animated spinner using @State rotation for smooth animation
                    // (avoids TimelineView(.animation) which re-evaluates body every frame)
                    ZStack {
                        Circle()
                            .stroke(Color.themeTextSecondary.opacity(0.2), lineWidth: 4)
                            .frame(width: 50, height: 50)

                        Circle()
                            .trim(from: 0, to: 0.2)
                            .stroke(Color.themePrimaryAccent, lineWidth: 4)
                            .frame(width: 50, height: 50)
                            .rotationEffect(Angle(degrees: spinnerRotation))
                    }
                    .onAppear {
                        withAnimation(Animation.linear(duration: TabLoadingAnimation.spinnerRotationDuration).repeatForever(autoreverses: false)) {
                            spinnerRotation = 360
                        }
                    }

                    VStack(spacing: 8) {
                        Text(message)
                            .font(.headline)
                            .foregroundColor(Color.themeTextSecondary)

                        if let detailMessage, !detailMessage.isEmpty {
                            Text(detailMessage)
                                .font(.subheadline)
                                .foregroundColor(Color.themeTextSecondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }

                        if let startedAt {
                            SummaryLoadingTimerView(
                                startedAt: startedAt,
                                timeoutInterval: timeoutInterval
                            )
                            .frame(maxWidth: 260)
                        }
                    }
                }
                Spacer()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minHeight: 300)
    }
}
