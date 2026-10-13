import SwiftUI
import AppKit
struct AlertModifier: ViewModifier {
    @ObservedObject var viewModel: NotesListViewModel
    func body(content: Content) -> some View {
        content.alert("Jotley", isPresented: $viewModel.showSyncError) {
            Button("OK", role: .cancel) {}
        } message: { Text(viewModel.syncErrorMessage) }
    }
}
