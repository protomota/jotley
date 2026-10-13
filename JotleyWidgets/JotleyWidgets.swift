import WidgetKit
import SwiftUI

// MARK: - Brand Colors
private extension Color {
    static let jotleyPurple = Color(red: 0.576, green: 0.2, blue: 0.918) // #9333EA
    static let jotleyDark = Color(red: 0.08, green: 0.08, blue: 0.1)
    static let jotleyCardBg = Color(red: 0.12, green: 0.12, blue: 0.14)
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

// MARK: - Small Widget View
struct QuickRecordSmallView: View {
    var body: some View {
        ZStack {
            // Dark background
            Color.jotleyDark

            VStack(spacing: 12) {
                // Record button with glow
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(Color.jotleyPurple.opacity(0.3))
                        .frame(width: 72, height: 72)
                        .blur(radius: 8)

                    // Main button
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.jotleyPurple, Color.jotleyPurple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.jotleyPurple.opacity(0.5), radius: 8, y: 4)

                    // Mic icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Label
                Text("Transcribe")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .widgetURL(URL(string: "jotley://starttranscription"))
    }
}

// MARK: - Medium Widget View
struct QuickRecordMediumView: View {
    var body: some View {
        ZStack {
            Color.jotleyDark

            HStack(spacing: 16) {
                // Left - Record button
                VStack(spacing: 10) {
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(Color.jotleyPurple.opacity(0.3))
                            .frame(width: 64, height: 64)
                            .blur(radius: 8)

                        // Main button
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.jotleyPurple, Color.jotleyPurple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)
                            .shadow(color: Color.jotleyPurple.opacity(0.5), radius: 8, y: 4)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("Transcribe live")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 100)

                // Right - Info
                VStack(alignment: .leading, spacing: 8) {
                    // Logo/title
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.jotleyPurple)

                        Text("Jotley")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Text("Show up. Leave the notes to us.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)

                    Spacer()

                    // Waveform decoration
                    HStack(spacing: 3) {
                        ForEach(0..<12, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.jotleyPurple.opacity(0.4 + Double(i % 3) * 0.2))
                                .frame(width: 3, height: CGFloat([8, 14, 10, 18, 12, 16, 8, 14, 20, 10, 14, 8][i]))
                        }
                    }
                }
                .padding(.vertical, 14)

                Spacer()
            }
            .padding(.leading, 16)
        }
        .widgetURL(URL(string: "jotley://starttranscription"))
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

    var body: some View {
        switch family {
        case .systemSmall:
            QuickRecordSmallView()
        case .systemMedium:
            QuickRecordMediumView()
        default:
            QuickRecordSmallView()
        }
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
