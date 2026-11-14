import SwiftUI

struct JotleySupporterBadge: View {
    @ObservedObject private var supporter = JotleySupporterStore.shared
    var body: some View {
        if supporter.isSupporter {
            Label {
                Text("Jotley Supporter")
            } icon: {
                JotleySupporterEmblem(size: 30)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(Color.themePrimaryAccent.opacity(0.55)))
            .accessibilityIdentifier("jotleySupporterBadge")
        }
    }
}

struct JotleySupporterEmblem: View {
    var size: CGFloat = 120
    var animationID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image("SupporterBadge")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? nil : animationID) { badge, scale in
                badge.scaleEffect(scale)
            } keyframes: { _ in
                LinearKeyframe(0.92, duration: 0.12)
                SpringKeyframe(1.0, duration: 0.48, spring: .bouncy)
            }
            .accessibilityHidden(true)
    }
}

private struct SupporterCelebrationModifier: ViewModifier {
    let kind: JotleySupporterStore.Kind
    var previewEvent: JotleySupporterStore.Celebration?
    @ObservedObject private var supporter = JotleySupporterStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var event: JotleySupporterStore.Celebration? {
        previewEvent ?? supporter.celebration.flatMap { $0.kind == kind ? $0 : nil }
    }
    func body(content: Content) -> some View {
        content
            .overlay {
                if kind == .tip, let event, !reduceMotion {
                    SupporterConfetti(accent: Color.themePrimaryAccent, startedAt: event.startedAt)
                }
            }
            .task(id: event?.id) {
                guard let event else { return }
                let duration = kind == .tip ? SupporterConfetti.duration : 3
                let remaining = max(0, duration - Date().timeIntervalSince(event.startedAt))
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                supporter.endCelebration(event.id)
            }
            .onChange(of: event?.id) { _, id in
                if id != nil, kind == .support { JotleyEngagement.shared.recordClick(.support) }
            }
    }
}

/// Two celebratory fountain bursts, with tumbling confetti and brief glitter flares.
/// Decoration never intercepts Done or any purchase control.
private struct SupporterConfetti: View {
    let accent: Color
    let startedAt: Date
    static let duration = 4.6

    private func variation(_ index: Int, _ channel: Int) -> Double {
        let value = sin(Double(index * 73 + channel * 193) * 12.9898) * 43758.5453
        return value - floor(value)
    }

    private func sparklePath(radius: Double) -> Path {
        var path = Path()
        for point in 0..<8 {
            let angle = Double(point) * .pi / 4 - .pi / 2
            let distance = point.isMultiple(of: 2) ? radius : radius * 0.22
            let position = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
            if point == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        return path
    }

    private func drawConfetti(_ context: GraphicsContext, size: CGSize, elapsed: Double) {
        let colors: [Color] = [accent, .white, accent.opacity(0.65), Color(red: 1, green: 0.83, blue: 0.49)]
        for index in 0..<150 {
            let delay = variation(index, 1) * 0.32 + (index > 95 ? 0.3 : 0)
            let age = elapsed - delay
            let lifetime = 2.6 + variation(index, 2) * 1.4
            guard age >= 0, age < lifetime else { continue }
            let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
            let originX = direction > 0 ? size.width * 0.03 : size.width * 0.97
            let originY = size.height * (0.84 + variation(index, 3) * 0.12)
            let horizontalSpeed = size.width * (0.4 + variation(index, 4) * 0.65)
            let verticalSpeed = size.height * (0.68 + variation(index, 5) * 0.72)
            let gravity = size.height * (0.84 + variation(index, 6) * 0.2)
            let travel = (1 - exp(-0.38 * age)) / 0.38
            let flutter = sin(age * (5 + variation(index, 7) * 6) + Double(index)) * 15 * min(age, 1)
            let x = originX + direction * horizontalSpeed * travel + flutter
            let y = originY - verticalSpeed * age + 0.5 * gravity * age * age
            let fadeIn = min(1, age * 14)
            let fadeOut = min(1, (lifetime - age) * 2.6)
            let width = 4 + variation(index, 8) * 6
            let height = 7 + variation(index, 9) * 9
            var particle = context
            particle.opacity = fadeIn * fadeOut
            particle.translateBy(x: x, y: y)
            particle.rotate(by: .radians(Double(index) + direction * age * (3 + variation(index, 10) * 8)))
            // Changing face width gives each piece its own tumble in depth.
            particle.scaleBy(x: 0.18 + abs(cos(age * (5 + variation(index, 11) * 7) + Double(index))) * 0.82, y: 1)
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            let path = index.isMultiple(of: 7) ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
            particle.fill(path, with: .color(colors[index % colors.count]))
        }
    }

    private func drawGlitter(_ context: GraphicsContext, size: CGSize, elapsed: Double) {
        for index in 0..<38 {
            let delay = 0.25 + variation(index, 12) * 2.3
            let age = elapsed - delay
            let lifetime = 0.4 + variation(index, 13) * 0.6
            guard age >= 0, age < lifetime else { continue }
            let progress = age / lifetime
            let shimmer = sin(progress * .pi)
            let x = size.width * (0.06 + variation(index, 14) * 0.88)
            let y = size.height * (0.12 + variation(index, 15) * 0.76) - age * 15
            let radius = (5 + variation(index, 16) * 9) * shimmer
            var sparkle = context
            sparkle.translateBy(x: x, y: y)
            sparkle.rotate(by: .radians(progress * 0.45))
            var glow = sparkle
            glow.opacity = shimmer * 0.16
            glow.addFilter(.blur(radius: 3))
            glow.fill(sparklePath(radius: radius * 1.3), with: .color(.white))
            sparkle.opacity = shimmer * 0.9
            sparkle.fill(sparklePath(radius: radius), with: .color(index.isMultiple(of: 3) ? accent : .white))
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                guard elapsed >= 0, elapsed < Self.duration else { return }
                drawConfetti(context, size: size, elapsed: elapsed)
                drawGlitter(context, size: size, elapsed: elapsed)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func jotleySupporterCelebration(_ kind: JotleySupporterStore.Kind,
                                    previewEvent: JotleySupporterStore.Celebration? = nil) -> some View {
        modifier(SupporterCelebrationModifier(kind: kind, previewEvent: previewEvent))
    }
}
