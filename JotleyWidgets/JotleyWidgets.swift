import WidgetKit
import SwiftUI

// MARK: - Brand Colors
private extension Color {
    static let jotleyWidgetAccent = ThemeColor.purple.color(in: .dark)
    static let jotleyDark = Color(white: 0.08)
}

// MARK: - Widget Timeline Provider
struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry {
        QuickRecordEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        completion(QuickRecordEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        let entry = QuickRecordEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Widget Entry
struct QuickRecordEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget Views
private struct QuickRecordGlyph: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let diameter: CGFloat
    let fontSize: CGFloat

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(renderingMode == .fullColor ? Color.black : Color.primary)
            .frame(width: diameter, height: diameter)
            .background {
                if renderingMode == .fullColor {
                    Circle()
                        .fill(Color.jotleyWidgetAccent)
                        .overlay(Circle().strokeBorder(.white.opacity(0.18)))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                } else {
                    Circle().fill(.primary.opacity(0.15))
                }
            }
    }
}

struct QuickRecordSmallView: View {
    var body: some View {
        VStack(spacing: 12) {
            QuickRecordGlyph(diameter: 56, fontSize: 24)
                .frame(width: 72, height: 72)
            Text("Transcribe")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuickRecordMediumView: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 10) {
                QuickRecordGlyph(diameter: 52, fontSize: 22)
                    .frame(width: 64, height: 64)
                Text("Transcribe live")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.jotleyWidgetAccent)
                        .widgetAccentable()
                    Text("Jotley")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }

                Text("Show up. Leave the notes to us.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.jotleyWidgetAccent)
                            .frame(width: 3, height: CGFloat([8, 14, 10, 18, 12, 16, 8, 14, 20, 10, 14, 8][i]))
                    }
                }
                .widgetAccentable()
            }
            .padding(.vertical, 14)

            Spacer()
        }
        .padding(.leading, 16)
    }
}

// MARK: - Widget Configuration
struct QuickRecordWidget: Widget {
    let kind: String = "QuickRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { entry in
            QuickRecordWidgetEntryView(entry: entry)
                .containerBackground(Color.jotleyDark, for: .widget)
        }
        .configurationDisplayName("Live Transcription")
        .description("Start on-device live transcription with one tap")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Entry View
struct QuickRecordWidgetEntryView: View {
    var entry: QuickRecordProvider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            case .systemMedium: QuickRecordMediumView()
            default: QuickRecordSmallView()
            }
        }
        .foregroundStyle(renderingMode == .fullColor ? Color.white : Color.primary)
        .widgetURL(URL(string: "jotley://starttranscription"))
    }
}

// MARK: - Previews
#Preview("Small", as: .systemSmall) {
    QuickRecordWidget()
} timeline: {
    QuickRecordEntry(date: Date())
}

#Preview("Medium", as: .systemMedium) {
    QuickRecordWidget()
} timeline: {
    QuickRecordEntry(date: Date())
}
