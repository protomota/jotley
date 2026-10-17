import WidgetKit
import SwiftUI
import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var isRecording: Bool
        var lastUpdatedAt: Date?
        var formattedDuration: String { String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60) }
        var timerStartDate: Date { (lastUpdatedAt ?? Date()).addingTimeInterval(-Double(elapsedSeconds)) }
    }
    var recordingId: String
    var startTime: Date
}


private let recordingAccent = Color(red: 0.576, green: 0.2, blue: 0.918)

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "waveform").font(.title2).foregroundStyle(recordingAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.isRecording ? "Transcribing" : "Paused").font(.headline)
                    RecordingDuration(state: context.state).font(.subheadline.monospacedDigit())
                }
                Spacer()
                RecordingControls(context: context)
            }.padding(20).foregroundStyle(.white)
                .activityBackgroundTint(Color(red: 0.08, green: 0.08, blue: 0.1))
                .widgetURL(recordingURL("transcription", id: context.attributes.recordingId))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.isRecording ? "Transcribing" : "Paused", systemImage: "mic.fill")
                        .font(.caption).foregroundStyle(recordingAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingDuration(state: context.state).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RecordingControls(context: context).padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: "mic.fill").foregroundStyle(recordingAccent)
            } compactTrailing: {
                Text(context.state.isRecording ? "LIVE" : "Paused").font(.caption.bold()).foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.state.isRecording ? "mic.fill" : "pause.fill").foregroundStyle(recordingAccent)
            }
            .widgetURL(recordingURL("transcription", id: context.attributes.recordingId))
            .keylineTint(recordingAccent)
        }
    }
}

private struct RecordingDuration: View {
    let state: RecordingActivityAttributes.ContentState
    var body: some View {
        if state.isRecording { Text(state.timerStartDate, style: .timer) }
        else { Text(state.formattedDuration) }
    }
}

private struct RecordingControls: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    var body: some View {
        HStack(spacing: 12) {
            Link(destination: recordingURL("pausetranscription", id: context.attributes.recordingId)) {
                Image(systemName: context.state.isRecording ? "pause.fill" : "play.fill")
                    .frame(width: 44, height: 44).background(recordingAccent, in: Circle())
            }.accessibilityLabel(context.state.isRecording ? "Pause Transcription" : "Resume Transcription")
            Link(destination: recordingURL("stoptranscription", id: context.attributes.recordingId)) {
                Image(systemName: "stop.fill").frame(width: 44, height: 44).background(recordingAccent, in: Circle())
            }.accessibilityLabel("Stop Transcription")
        }.foregroundStyle(.white)
    }
}

private func recordingURL(_ action: String, id: String) -> URL {
    var components = URLComponents()
    components.scheme = "jotley"; components.host = action
    components.queryItems = [URLQueryItem(name: "id", value: id)]
    return components.url!
}

#Preview("Transcribing", as: .content, using: RecordingActivityAttributes(recordingId: UUID().uuidString, startTime: Date())) {
    RecordingLiveActivity()
} contentStates: {
    RecordingActivityAttributes.ContentState(elapsedSeconds: 125, isRecording: true, lastUpdatedAt: Date())
    RecordingActivityAttributes.ContentState(elapsedSeconds: 300, isRecording: false, lastUpdatedAt: Date())
}
