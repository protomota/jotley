import SwiftUI

@MainActor
final class RecordingWidgetViewModel: ObservableObject {
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var appIcon: NSImage?

    private weak var recorder: ProcessTapRecorder?
    private var timer: Timer?

    init(recorder: ProcessTapRecorder) {
        self.recorder = recorder
    }

    func start() {
        stop()
        syncFromRecorder()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.syncFromRecorder()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func stopRecording() {
        guard let recorder else { return }
        Task { @MainActor in
            if let vm = (JotleyAppDelegate.shared?.recordingNotesViewModel ?? JotleyAppDelegate.shared?.activeNotesViewModel) { await vm.stopRecording() }
            else { _ = await recorder.stop() }
        }
    }

    private func syncFromRecorder() {
        guard let recorder else { return }
        elapsedTime = recorder.elapsedTime
        audioLevel = recorder.currentAudioLevel
        isRecording = recorder.isRecording
        appIcon = recorder.icon
    }
}

struct RecordingWidgetView: View {
    @ObservedObject var viewModel: RecordingWidgetViewModel
    var onWidgetTapped: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            RecordingIndicator(
                appIcon: viewModel.appIcon,
                isRecording: viewModel.isRecording,
                audioLevel: viewModel.audioLevel,
                size: 22
            )
            .frame(width: 22, height: 22)

            Rectangle()
                .fill(Color.themeAccent.opacity(0.35))
                .frame(width: 1, height: 18)

            Text(formatTimeInterval(viewModel.elapsedTime))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(Color.themeTextPrimary)
                .lineLimit(1)
                .frame(width: 50, alignment: .leading)

            Spacer(minLength: 0)

            Button(action: viewModel.stopRecording) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .medium))

                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.themePrimaryAccent)
                )
                .shadow(color: Color.themePrimaryAccent.opacity(0.45), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 220, height: 48)
        .background(
            Capsule(style: .continuous)
                .fill(Color.themeContentBackground.opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.themeAccent.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            onWidgetTapped?()
        }
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
}

struct RecordingWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        let tap = ProcessTap(muteWhenRunning: true)
        let recorder = ProcessTapRecorder()
        let viewModel = RecordingWidgetViewModel(recorder: recorder)
        return RecordingWidgetView(viewModel: viewModel)
            .padding()
            .background(Color.gray.opacity(0.2))
    }
}
