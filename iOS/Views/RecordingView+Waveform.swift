import SwiftUI
import UIKit
// MARK: - Live Transcription Waveform

/// A soft logarithmic response makes quiet input visible while reserving 8%
/// of the available height above full-scale PCM. This displays volume, not pitch.
enum LiveWaveformResponse {
    static func level(for peak: Float) -> Float {
        guard peak.isFinite else { return 0.04 }
        let input = max(0, min(1, peak))
        return 0.04 + 0.88 * log1p(24 * input) / log(25)
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
    private let bars = (0..<50).map { _ in CALayer() }
    private var levels = Array(repeating: Float(0.04), count: 50)
    private var smoothedLevel: Float = 0.04
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
            levels = Array(repeating: 0.04, count: bars.count); smoothedLevel = 0.04
            for bar in bars { bar.removeAllAnimations() }
            setNeedsLayout()
        }
        updateTimer()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); updateTimer() }
    private func updateTimer() {
        guard listening && window != nil else { stopTimer(); return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceWaveform() }
        }
        timer.tolerance = 0.01
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
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: max(6, CGFloat(levels[index]) * bounds.height))
            bar.position = CGPoint(x: left + CGFloat(index) * (width + spacing) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }
    func advanceWaveform() {
        guard listening else { return }
        let input = LiveWaveformResponse.level(for: levelProvider?() ?? 0)
        smoothedLevel += (input - smoothedLevel) * (input > smoothedLevel ? 0.7 : 0.2)
        levels.removeFirst(); levels.append(smoothedLevel)
        for (index, bar) in bars.enumerated() {
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            let target = max(6, CGFloat(levels[index]) * bounds.height)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bar.bounds.size.height = target
            CATransaction.commit()
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = current; animation.toValue = target
            animation.duration = 0.1
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            bar.add(animation, forKey: "liveLevel")
        }
    }
}
