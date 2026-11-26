import SwiftUI
import UIKit
// MARK: - Live Transcription Waveform

enum LiveWaveformResponse {
    static let restingLevel: Float = 0.04

    static func level(for peak: Float) -> Float {
        guard peak.isFinite else { return restingLevel }
        let noiseFloor: Float = 0.002
        let input = max(0, min(1, peak) - noiseFloor)
        // Lift quiet speech while leaving room for louder syllables.
        return restingLevel + 0.88 * log1p(170 * input) / log1p(170 * (1 - noiseFloor))
    }
}

/// Core Animation interpolates bars on the render server. Transcript updates
/// do not publish waveform state or require SwiftUI to render every frame.
struct LiveTranscriptionWaveformView: View {
    let levelProvider: () -> Float
    let isTranscribing: Bool
    var isPaused = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        LiveWaveformSurface(levelProvider: levelProvider,
            listening: isTranscribing && scenePhase == .active, paused: isPaused,
            color: isTranscribing ? UIColor(Color.themePrimaryAccent) : UIColor.gray.withAlphaComponent(isPaused ? 0.5 : 0.4))
            .accessibilityLabel(isTranscribing ? "Live microphone waveform" : "Paused waveform")
    }
}

private struct LiveWaveformSurface: UIViewRepresentable {
    let levelProvider: () -> Float
    let listening: Bool
    let paused: Bool
    let color: UIColor
    func makeUIView(context: Context) -> LiveWaveformLayerView { LiveWaveformLayerView() }
    func updateUIView(_ view: LiveWaveformLayerView, context: Context) {
        view.update(levelProvider: levelProvider, listening: listening, paused: paused, color: color)
    }
    static func dismantleUIView(_ view: LiveWaveformLayerView, coordinator: ()) { view.stopTimer() }
}

final class LiveWaveformLayerView: UIView {
    private static let updateInterval = 1 / LiveTranscriptionManager.waveformSamplesPerSecond
    private static let minimumBarHeight: CGFloat = 3
    private let bars = (0..<50).map { _ in CALayer() }
    private var levels = Array(repeating: LiveWaveformResponse.restingLevel, count: 50)
    private var smoothedLevel = LiveWaveformResponse.restingLevel
    private var levelProvider: (() -> Float)?
    private var listening = false
    private var timer: Timer?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for bar in bars { layer.addSublayer(bar) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    func update(levelProvider: @escaping () -> Float, listening: Bool, paused: Bool, color: UIColor) {
        self.levelProvider = levelProvider; self.listening = listening
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for bar in bars { bar.backgroundColor = color.cgColor }
        CATransaction.commit()
        if !listening && !paused {
            levels = Array(repeating: LiveWaveformResponse.restingLevel, count: bars.count)
            smoothedLevel = LiveWaveformResponse.restingLevel
            for bar in bars { bar.removeAllAnimations() }
            setNeedsLayout()
        }
        updateTimer()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); updateTimer() }
    private func updateTimer() {
        guard listening && window != nil else { stopTimer(); return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceWaveform() }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stopTimer() { timer?.invalidate(); timer = nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        let spacing: CGFloat = 2
        let width = max(1, floor((bounds.width - CGFloat(bars.count - 1) * spacing) / CGFloat(bars.count)))
        let left = floor((bounds.width - CGFloat(bars.count) * width - CGFloat(bars.count - 1) * spacing) / 2)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: barHeight(at: index))
            bar.position = CGPoint(x: left + CGFloat(index) * (width + spacing) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }
    func advanceWaveform() {
        guard listening else { return }
        let input = LiveWaveformResponse.level(for: levelProvider?() ?? 0)
        smoothedLevel += (input - smoothedLevel) * (input > smoothedLevel ? 0.9 : 0.65)
        levels.removeFirst(); levels.append(smoothedLevel)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            let target = barHeight(at: index)
            bar.bounds.size.height = target
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = current; animation.toValue = target
            animation.duration = Self.updateInterval
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            bar.add(animation, forKey: "liveLevel")
        }
        CATransaction.commit()
    }

    private func barHeight(at index: Int) -> CGFloat {
        max(Self.minimumBarHeight, CGFloat(levels[index]) * bounds.height)
    }
}
