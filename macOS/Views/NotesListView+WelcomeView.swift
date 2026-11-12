import SwiftUI

struct WelcomeView: View {
    let hasNotes: Bool
    let canCreateNewNote: Bool
    @ObservedObject var viewModel: NotesListViewModel

    var body: some View {
        JotleyLibraryWelcome(hasNotes: hasNotes, canStart: canCreateNewNote) {
            Task { await viewModel.startNewNote() }
        }
        .frame(maxHeight: .infinity)
    }
}
