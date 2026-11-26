import SwiftUI
extension NoteDetailPlaceholderView {
    func handleSummarizeAction(templateKey: String) async {
        isSummaryEditorFocused = false
        showRawMarkdownSummary = false
        summaryInlineEditRequestCounter = 0
        selectedTab = DetailTab.summary.rawValue
        await viewModel.generateSummary(note: note, templateKey: templateKey)
        editableSummary = note.summary ?? ""
    }
}
