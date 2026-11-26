import SwiftUI

private enum SummaryLoadingTimerFormatting {
    static func string(from interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SummaryLoadingTimerView: View {
    let startedAt: Date
    var timeoutInterval: TimeInterval?

    private func progress(for elapsed: TimeInterval) -> Double? {
        guard let timeoutInterval, timeoutInterval > 0 else { return nil }
        return min(max(elapsed / timeoutInterval, 0), 1)
    }

    private func progressColor(for progress: Double?) -> Color {
        guard let progress else { return Color.themePrimaryAccent }
        return progress >= 0.85 ? .orange : Color.themePrimaryAccent
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(context.date.timeIntervalSince(startedAt), 0)
            let timeoutProgress = progress(for: elapsed)

            VStack(spacing: 8) {
                Label("\(SummaryLoadingTimerFormatting.string(from: elapsed)) elapsed", systemImage: "timer")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(Color.themeTextSecondary)

                if timeoutInterval ?? 0 > 0, let timeoutProgress {
                    ProgressView(value: timeoutProgress)
                        .tint(progressColor(for: timeoutProgress))
                        .frame(maxWidth: 220)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
