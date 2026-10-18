import SwiftUI
import AppKit
import Combine

struct MacLiveTranscriptionSheet: View {
    @ObservedObject var viewModel: NotesListViewModel
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Live Transcription").font(.system(size: 22, weight: .bold))
                Spacer()
                Button { finish() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 32, height: 32)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .foregroundStyle(Color.themeTextPrimary)
                .disabled(viewModel.operationInProgress)
                .accessibilityLabel("Stop and Close Transcription")
                .accessibilityIdentifier("macLiveTranscriptionCloseButton")
            }.padding(24)
            Divider()
            MacLiveTranscriptPane(recorder: viewModel.recorder).equatable()
                .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            VStack(spacing: 14) {
                MacLiveWaveform(recorder: viewModel.recorder,
                    listening: viewModel.recorder.isRecording && !viewModel.isTranscriptionPaused)
                    .frame(height: 64).accessibilityLabel("Live audio waveform")
                MacTranscriptionControls(timerText: timerText, isPaused: viewModel.isTranscriptionPaused,
                    isBusy: viewModel.operationInProgress,
                    onPause: { Task { await viewModel.resumeTranscription() } }, onStop: finish)
            }.padding(24)
        }
        .foregroundStyle(Color.themeTextPrimary)
        .background(Color.themeBackground)
        .frame(width: 600, height: 660)
        .accessibilityIdentifier("macLiveTranscriptionSheet")
        .onExitCommand { if !viewModel.operationInProgress { finish() } }
        .preferredColorScheme(themeManager.effectiveColorScheme).observeThemeChanges()
    }
    private var timerText: String {
        let seconds = Int(viewModel.recorder.elapsedTime)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private func finish() { Task { await viewModel.stopRecording() } }
}

struct MacTranscriptionControls: View {
    let timerText: String
    let isPaused: Bool
    var isBusy = false
    let onPause: () -> Void
    let onStop: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isPaused ? "Paused" : "Transcribing").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.themeTextSecondary)
                Text(timerText).font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.themeTextPrimary).fixedSize()
            }
            Spacer(minLength: 20)
            Button(action: onPause) {
                Label(isPaused ? "Continue" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .semibold)).frame(minHeight: 32)
            }.buttonStyle(.glass).foregroundStyle(Color.themeTextPrimary)
                .accessibilityIdentifier("macLiveTranscriptionPauseButton")
            Button(action: onStop) {
                Label("Stop Transcription", systemImage: "stop.fill")
                    .font(.system(size: 16, weight: .semibold)).frame(minHeight: 32)
            }.buttonStyle(.glassProminent).tint(Color.themePrimaryAccent)
                .accessibilityIdentifier("macLiveTranscriptionStopButton")
        }.disabled(isBusy).frame(minWidth: 460, minHeight: 52)
    }
}

/// Text subscribes only to speech revisions. Meter/timer updates don't rebuild
/// the transcript's timestamped bubbles or drive its scroll position.
@MainActor private final class MacLiveTranscriptState: ObservableObject {
    @Published var text = ""
    @Published var interim = ""
    @Published var utterances: [TranscriptUtterance] = []
    @Published var revision = 0
    private var subscription: AnyCancellable?
    init(recorder: ProcessTapRecorder) {
        refresh(recorder)
        subscription = recorder.$transcription.removeDuplicates().sink { [weak self, weak recorder] _ in
            Task { @MainActor in
                guard let self, let recorder else { return }
                self.refresh(recorder)
            }
        }
    }
    private func refresh(_ recorder: ProcessTapRecorder) {
        text = recorder.accumulatedTranscript
        interim = recorder.latestTranscriptDelta
        utterances = recorder.transcriptUtterances
        revision += 1
    }
}

private struct MacLiveTranscriptPane: View, Equatable {
    let recorder: ProcessTapRecorder
    @StateObject private var state: MacLiveTranscriptState
    init(recorder: ProcessTapRecorder) {
        self.recorder = recorder
        _state = StateObject(wrappedValue: MacLiveTranscriptState(recorder: recorder))
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.recorder === rhs.recorder }
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TranscriptParagraphsView(transcript: state.text, utterances: state.utterances,
                            interimText: state.interim, isRecordingActive: true, showEllipsis: false)
                            .font(.system(size: 16)).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Color.clear.frame(height: 1).id("liveTranscriptBottom")
                    }.frame(minHeight: geometry.size.height, alignment: .top)
                }
                .task(id: state.revision) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo("liveTranscriptBottom", anchor: .bottom)
                }
            }
        }.accessibilityIdentifier("macLiveTranscriptionText")
    }
}

/// Core Animation interpolates the meter independently of SwiftUI text updates.
private struct MacLiveWaveform: NSViewRepresentable {
    let recorder: ProcessTapRecorder
    let listening: Bool
    func makeNSView(context: Context) -> MacWaveformLayerView { MacWaveformLayerView() }
    func updateNSView(_ view: MacWaveformLayerView, context: Context) {
        view.update(levelProvider: { recorder.currentAudioLevel }, listening: listening,
                    color: NSColor(listening ? Color.themePrimaryAccent : Color.themeTextSecondary))
    }
    static func dismantleNSView(_ view: MacWaveformLayerView, coordinator: ()) { view.stopTimer() }
}

private final class MacWaveformLayerView: NSView {
    private let bars = (0..<50).map { _ in CALayer() }
    private var levels = Array(repeating: Float(0.04), count: 50)
    private var smoothed: Float = 0.04
    private var levelProvider: (() -> Float)?
    private var listening = false
    private var timer: Timer?
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        for bar in bars { layer?.addSublayer(bar) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    func update(levelProvider: @escaping () -> Float, listening: Bool, color: NSColor) {
        self.levelProvider = levelProvider; self.listening = listening
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for bar in bars { bar.backgroundColor = color.cgColor }
        CATransaction.commit(); updateTimer()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateTimer() }
    private func updateTimer() {
        guard listening, window != nil else { stopTimer(); return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer.tolerance = 0.01; RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func stopTimer() { timer?.invalidate(); timer = nil }
    override func layout() {
        super.layout()
        let spacing: CGFloat = 3
        let width = max(1, (bounds.width - CGFloat(bars.count - 1) * spacing) / CGFloat(bars.count))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: max(4, CGFloat(levels[index]) * bounds.height))
            bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }
    private func advance() {
        let raw = levelProvider?() ?? 0
        let peak = raw.isFinite ? max(0, min(1, raw)) : 0
        let target = 0.04 + 0.88 * log1p(24 * peak) / log(25)
        smoothed += (target - smoothed) * (target > smoothed ? 0.7 : 0.2)
        levels.removeFirst(); levels.append(smoothed)
        for (index, bar) in bars.enumerated() {
            let before = bar.presentation()?.bounds.height ?? bar.bounds.height
            let after = max(4, CGFloat(levels[index]) * bounds.height)
            CATransaction.begin(); CATransaction.setDisableActions(true); bar.bounds.size.height = after; CATransaction.commit()
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = before; animation.toValue = after; animation.duration = 0.1
            animation.timingFunction = CAMediaTimingFunction(name: .linear); bar.add(animation, forKey: "liveLevel")
        }
    }
}
