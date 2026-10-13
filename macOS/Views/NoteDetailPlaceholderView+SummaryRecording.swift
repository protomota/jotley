import SwiftUI
extension NoteDetailPlaceholderView {
    func formatTimeInterval(_ interval: TimeInterval) -> String {
        let seconds = Int(interval); return "\(seconds / 60)m \(seconds % 60)s"
    }
    func handleSummarizeAction(templateKey: String) async {
        isSummaryEditorFocused = false
        showRawMarkdownSummary = false
        summaryInlineEditRequestCounter = 0
        selectedTab = DetailTab.summary.rawValue
        await viewModel.generateSummary(note: note, templateKey: templateKey)
        editableSummary = note.summary ?? ""
    }
    func stopRecordingAndShowTemplateSheet() async {
        await viewModel.stopRecording()
        editableTranscript = note.transcription ?? ""
        selectedTab = DetailTab.transcript.rawValue
    }
}
