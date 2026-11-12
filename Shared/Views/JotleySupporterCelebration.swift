import SwiftUI

struct JotleySupporterBadge: View {
    @ObservedObject private var supporter = JotleySupporterStore.shared
    var body: some View {
        if supporter.isSupporter {
            Label("Jotley Supporter", systemImage: "heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.themePrimaryAccent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.themePrimaryAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("jotleySupporterBadge")
        }
    }
}

private struct SupporterCelebrationModifier: ViewModifier {
    let kind: JotleySupporterStore.Kind
    @ObservedObject private var supporter = JotleySupporterStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var event: JotleySupporterStore.Celebration? {
        supporter.celebration.flatMap { $0.kind == kind ? $0 : nil }
    }
    func body(content: Content) -> some View {
        content
            .overlay {
                if let event, !reduceMotion {
                    SupporterConfetti(startedAt: event.startedAt)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if event != nil {
                    HStack(spacing: 10) {
                        Image(systemName: "heart.fill").foregroundStyle(Color.themePrimaryAccent)
                        Text("Thank you for supporting Jotley!").font(.callout.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(14).background(.regularMaterial)
                    .accessibilityIdentifier("jotleySupporterThankYou")
                }
            }
            .task(id: event?.id) {
                guard let event else { return }
                let remaining = max(0, 3 - Date().timeIntervalSince(event.startedAt))
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                supporter.endCelebration(event.id)
            }
            .onChange(of: event?.id) { _, id in
                if id != nil, kind == .support { JotleyEngagement.shared.recordClick(.support) }
            }
    }
}

/// Deterministic purple/lavender paper pieces. Reduce Motion keeps the static
/// thank-you and badge, with no falling particles or sound.
private struct SupporterConfetti: View {
    let startedAt: Date
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                let progress = min(1, max(0, elapsed / 3))
                guard progress < 1 else { return }
                let colors: [Color] = [.themePrimaryAccent, Color(red: 0.75, green: 0.52, blue: 0.99), Color(red: 0.88, green: 0.77, blue: 1)]
                for index in 0..<55 {
                    let seed = Double(index)
                    let x = size.width * CGFloat((seed * 0.61803398875).truncatingRemainder(dividingBy: 1))
                        + CGFloat(sin(elapsed * 3 + seed) * 32)
                    let y = CGFloat(progress) * (size.height + 150) - CGFloat((index % 9) * 14)
                    var piece = context
                    piece.opacity = min(1, max(0, (1 - progress) * 4))
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(seed * 23 + elapsed * (index.isMultiple(of: 2) ? 150 : -120)))
                    let rect = CGRect(x: -3, y: -6, width: index.isMultiple(of: 3) ? 5 : 7, height: 12)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[index % colors.count]))
                }
            }
        }
    }
}

extension View {
    func jotleySupporterCelebration(_ kind: JotleySupporterStore.Kind) -> some View {
        modifier(SupporterCelebrationModifier(kind: kind))
    }
}
