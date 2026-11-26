import SwiftUI

extension NoteDetailPlaceholderView {

    // More menu button
    var moreMenuButton: some View {
        Button {
            showActionsPopover.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .medium))
        }
        .buttonStyle(JotleyGlassButtonStyle(circular: true, floatsOverContent: true))
        .floatingTooltip("More Actions")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("More Actions")
        .accessibilityIdentifier("noteDetailMoreMenuButton")

    }



    func loadTemplates() {
        // The observed catalog supplies built-in and user-created templates.
    }
}
