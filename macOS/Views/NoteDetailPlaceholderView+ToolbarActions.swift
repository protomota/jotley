import SwiftUI

extension NoteDetailPlaceholderView {

    // More menu button
    var moreMenuButton: some View {
        Button {
            showActionsPopover = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(Color.themePrimaryAccent)
        }
        .buttonStyle(JotleyGlassButtonStyle(circular: true))
        .floatingTooltip("More Actions")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("More Actions")
        .accessibilityIdentifier("noteDetailMoreMenuButton")

    }



    func loadTemplates() {
        availableTemplates = LocalSummaryTemplate.allCases.map {
            Template(key: $0.key, title: $0.title, description: $0.prompt, category: $0.category)
        }
    }
}
