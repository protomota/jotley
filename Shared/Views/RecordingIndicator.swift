// Includes material adapted from AudioCap by Guilherme Rambo (copyright 2024).
// Upstream material retains BSD-2-Clause; see docs/Rambo-BSD-2-Clause.txt.

import Combine
import SwiftUI

struct RecordingIndicator: View {
    #if os(macOS)
    let appIcon: NSImage?
    #else
    let appIcon: UIImage?
    #endif
    let isRecording: Bool
    let audioLevel: Float
    var size: CGFloat = 22
    var isPaused: Bool = false  // New parameter for paused state
    var alwaysShowBars: Bool = false  // New parameter to always show bars

    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var themeUpdateId = UUID()


    var body: some View {
        ZStack {
            // The recordingViewContent will now handle what to display based on isRecording and isPaused
            recordingViewContent
        }
        .id(themeUpdateId)
        // Animate the transition between ready (green), recording (red), and paused (gray) states
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPaused)
        .onChange(of: themeManager.currentThemeColor) { _, _ in
            // Force a redraw so indicator bars immediately adopt the new theme accent.
            themeUpdateId = UUID()
        }
    }

    @ViewBuilder
    private var recordingViewContent: some View {
        if isPaused && isRecording {
            // Paused state - grayed out
            pausedStateView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.5).combined(with: .opacity))
                )
        } else if isRecording {
            recordingStateView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.5).combined(with: .opacity))
                )
        } else {
            readyStateView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.5).combined(with: .opacity))
                )
        }
    }

    @ViewBuilder
    private var pausedStateView: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: size, height: size)

            Image(systemName: "pause.fill")
                .font(.system(size: self.size * 0.45))
                .foregroundColor(Color.gray)
        }
        .frame(width: size, height: size) // Ensure consistent frame
    }

    @ViewBuilder
    private var readyStateView: some View {
        if alwaysShowBars {
            // Always show bars for transcript button with random heights
            HStack(spacing: size * 0.1) {
                BarView(height: size, audioLevel: 0, delay: 0, alwaysShowBars: true)
                BarView(height: size, audioLevel: 0, delay: 0.1, alwaysShowBars: true)
                BarView(height: size, audioLevel: 0, delay: 0.2, alwaysShowBars: true)
            }
            .frame(width: size, height: size)
        } else {
            ZStack {
                Circle()
                    .fill(Color.themePrimaryAccent.opacity(0.85))
                    .frame(width: size, height: size)

                // Use the parameterized iconView for the app icon
                if appIcon != nil {
                    iconView(size: self.size * 0.55, fit: true)
                } else {
                    // Fallback icon when no app icon is provided
                    Image(systemName: "mic.fill")
                        .font(.system(size: self.size * 0.5))
                        .foregroundColor(Color.themeTextOnAccent)
                }
            }
            .frame(width: size, height: size) // Ensure consistent frame
        }
    }

    @ViewBuilder
    private var recordingStateView: some View {
        HStack(spacing: size * 0.1) {
            // Recording bars should track meter level directly (no synthetic phase/jitter animation).
            BarView(
                height: size,
                audioLevel: audioLevel,
                delay: 0,
                alwaysShowBars: true,
                forceMotionAtLowInput: true,
                baseHeightFactor: 0.10,
                maxHeightFactor: 0.84,
                growFromCenter: true
            )
            BarView(
                height: size,
                audioLevel: audioLevel,
                delay: 0,
                alwaysShowBars: true,
                forceMotionAtLowInput: true,
                baseHeightFactor: 0.10,
                maxHeightFactor: 1.0,
                recordingResponseBoost: 1.28,
                growFromCenter: true
            )
            BarView(
                height: size,
                audioLevel: audioLevel,
                delay: 0,
                alwaysShowBars: true,
                forceMotionAtLowInput: true,
                baseHeightFactor: 0.10,
                maxHeightFactor: 0.86,
                growFromCenter: true
            )
        }
        .frame(width: size, height: size)
    }

    // Bar component that animates based on audio level
    private struct BarView: View {
        let height: CGFloat
        let audioLevel: Float
        let delay: Double
        var alwaysShowBars: Bool = false
        var forceMotionAtLowInput: Bool = false
        var baseHeightFactor: CGFloat = 0.2
        var maxHeightFactor: CGFloat = 0.95
        var recordingResponseBoost: CGFloat = 1.0
        var growFromCenter: Bool = false

        // Each bar gets its own motion state so bars move independently but smoothly.
        @State private var randomFactor = Double.random(in: 0.75...1.1)
        @State private var motionPhase = Double.random(in: 0...(2 * .pi))
        @State private var motionVelocity = Double.random(in: 0.32...0.54)
        @State private var smoothedHeightFactor: CGFloat = 0.2
        // Keep timer identity stable across SwiftUI re-renders to avoid tick starvation.
        @State private var animationTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

        private static let activeThreshold: Float = 0.001
        private static let minimumAnimatedLevel: Float = 0.05
        private static let levelBoost: Float = 5.4
        private static let recordingLevelGain: CGFloat = 18.0
        private static let recordingLevelCurveExponent: CGFloat = 0.38

        // Constrain bar container size so unexpected parent layout never stretches bars vertically.
        private var constrainedHeight: CGFloat {
            min(max(height, 12), 28)
        }

        private var barWidth: CGFloat {
            constrainedHeight * 0.18
        }

        private var isActive: Bool {
            effectiveLevel > 0
        }

        private var normalizedAudioLevel: CGFloat {
            let clamped = min(max(CGFloat(audioLevel), 0), 1)
            let gained = min(1, clamped * Self.recordingLevelGain)
            // Strong low-end expansion so normal speech (not just loud peaks) visibly drives the bars.
            let curved = CGFloat(pow(Double(gained), Double(Self.recordingLevelCurveExponent)))
            return min(max(curved, 0), 1)
        }

        private var effectiveLevel: Float {
            if forceMotionAtLowInput {
                return Float(normalizedAudioLevel)
            }

            let boostedLevel = min(1.0, max(0, audioLevel) * Self.levelBoost)
            guard boostedLevel >= Self.activeThreshold else { return 0 }
            return max(boostedLevel, Self.minimumAnimatedLevel)
        }

        private var targetHeightFactor: CGFloat {
            if forceMotionAtLowInput {
                let clampedMin = min(max(baseHeightFactor, 0.08), 0.45)
                let clampedMax = min(max(maxHeightFactor, clampedMin + 0.2), 1.0)
                // Keep low-volume bars shorter while preserving headroom at high input.
                let shapedLevel = CGFloat(pow(Double(normalizedAudioLevel), 1.5))
                let boostedLevel = min(max(shapedLevel * recordingResponseBoost, 0), 1)
                return clampedMin + boostedLevel * (clampedMax - clampedMin)
            }

            // Expand quieter levels so activity remains visible with low amplitude inputs.
            let normalized = min(max(CGFloat(pow(Double(effectiveLevel), 0.62)), 0), 1)
            let floor = 0.26 + normalized * 0.2
            let ceil = 0.7 + normalized * 0.3
            let wave = CGFloat((sin(motionPhase + delay * 7.0) + 1.0) * 0.5)
            let shapedWave = pow(wave, 0.78)
            let pulse = min(max(shapedWave * CGFloat(randomFactor), 0), 1)
            return min(max(floor + (ceil - floor) * pulse, 0.24), 1.0)
        }

        private var activeBarHeight: CGFloat {
            let minimumFactor = forceMotionAtLowInput ? 0.08 : 0.24
            return constrainedHeight * min(max(smoothedHeightFactor, minimumFactor), 1.0)
        }

        private var snappedActiveBarHeight: CGFloat {
            // Snap tiny updates to half-points to prevent shimmer/flicker at low heights.
            max(1, (activeBarHeight * 2).rounded() / 2)
        }

        private var barAlignment: Alignment {
            growFromCenter ? .center : .bottom
        }

        private func updateSmoothedHeight(animated: Bool, refreshJitter: Bool = false) {
            let apply = {
                if forceMotionAtLowInput {
                    // Track live audio with fast attack/medium release; no synthetic jitter in recording mode.
                    let response: CGFloat = targetHeightFactor > smoothedHeightFactor ? 0.82 : 0.58
                    smoothedHeightFactor = smoothedHeightFactor * (1 - response) + targetHeightFactor * response
                    return
                }

                if refreshJitter {
                    // Advance phase each tick for smooth motion and retune pulse subtly.
                    motionPhase += motionVelocity
                    if motionPhase > 2 * .pi {
                        motionPhase -= 2 * .pi
                    }
                    randomFactor = randomFactor * 0.8 + Double.random(in: 0.82...1.16) * 0.2
                    motionVelocity = motionVelocity * 0.85 + Double.random(in: 0.3...0.58) * 0.15
                }

                if isActive || alwaysShowBars {
                    // Higher target weighting to follow live level changes more tightly.
                    smoothedHeightFactor = smoothedHeightFactor * 0.2 + targetHeightFactor * 0.8
                } else {
                    smoothedHeightFactor = 0.2
                }
            }

            if animated && !forceMotionAtLowInput {
                let animation: Animation = .linear(duration: 0.06).delay(delay * 0.08)
                withAnimation(animation) {
                    apply()
                }
            } else {
                apply()
            }
        }

        var body: some View {
            ZStack(alignment: barAlignment) {
                if isActive || forceMotionAtLowInput {
                    let accent = Color.themePrimaryAccent

                    RoundedRectangle(cornerRadius: constrainedHeight * 0.1)
                        .fill(accent)
                        .frame(width: barWidth, height: snappedActiveBarHeight)
                        .shadow(color: accent.opacity(0.55), radius: 3, x: 0, y: 0)
                } else if alwaysShowBars {
                    // When alwaysShowBars is true: keep bars animated at moderate height.
                    let staticHeight = constrainedHeight * min(max(smoothedHeightFactor * 0.72, 0.22), 0.72)
                    let accent = Color.themePrimaryAccent
                    RoundedRectangle(cornerRadius: constrainedHeight * 0.1)
                        .fill(accent.opacity(0.8))
                        .frame(width: barWidth, height: staticHeight)
                        .shadow(color: accent.opacity(0.3), radius: 1, x: 0, y: 0)
                } else {
                    // When inactive: Display a small dot
                    let accent = Color.themePrimaryAccent
                    Circle()
                        .fill(accent.opacity(0.85))
                        .frame(width: barWidth, height: barWidth)
                        .shadow(color: accent.opacity(0.25), radius: 1, x: 0, y: 0)
                }
            }
            .frame(height: constrainedHeight, alignment: growFromCenter ? .center : .bottom)
            .clipped()
            // Apply the animation
            .onChange(of: audioLevel) { oldValue, newValue in
                if forceMotionAtLowInput {
                    updateSmoothedHeight(animated: false)
                    return
                }
                guard abs(newValue - oldValue) > 0.0001 else { return }
                updateSmoothedHeight(animated: true)
            }
            .onReceive(animationTimer) { _ in
                if forceMotionAtLowInput {
                    updateSmoothedHeight(animated: false)
                    return
                }
                guard isActive || alwaysShowBars else { return }
                updateSmoothedHeight(animated: false, refreshJitter: true)
            }
            // Initialize state on appear
            .onAppear {
                // Initialize random factor for static bars
                if alwaysShowBars && !isActive && !forceMotionAtLowInput {
                    randomFactor = Double.random(in: 0.3...0.8) // Different range for static display
                }
                smoothedHeightFactor = forceMotionAtLowInput ? targetHeightFactor : (isActive ? targetHeightFactor : 0.2)
            }
        }
    }

    @ViewBuilder
    private func iconView(size: CGFloat, fit: Bool = false) -> some View {
        #if os(macOS)
        if let appIcon = appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: fit ? .fit : .fill) // Use parameter
                .frame(width: size, height: size)
        }
        #else
        if let appIcon = appIcon {
            Image(uiImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: fit ? .fit : .fill) // Use parameter
                .frame(width: size, height: size)
        }
        #endif
    }
}

#if DEBUG
struct RecordingIndicatorPreview: View {
    @State private var isRecording = false
    @State private var previewAudioLevel: Float = 0.0

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                RecordingIndicator(
                    appIcon: nil,
                    isRecording: isRecording,
                    audioLevel: previewAudioLevel
                )

                Text(isRecording ? "Transcribing (Level: \(String(format: "%.2f", previewAudioLevel)))" : "Ready to Transcribe")
                    .font(.headline)
                    .contentTransition(.identity)
            }
            .animation(.bouncy(extraBounce: 0.1), value: isRecording)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
            .contentShape(Rectangle())
            .onTapGesture {
                isRecording.toggle()
                if !isRecording {
                    previewAudioLevel = 0.0
                }
            }

            if isRecording {
                Slider(value: $previewAudioLevel, in: 0...1)
                    .padding()
            }
        }
    }
}
#Preview("Transcription Indicator") {
    RecordingIndicatorPreview()
}
#endif
