import SwiftUI
import Combine
import Foundation
import AppKit

struct NotesListView: View {
    @ObservedObject var summaryNotifications = JotleySummaryNotifications.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.timestamp, ascending: false)],
        predicate: SharedPersistenceController.activeNotesPredicate,
        animation: .default)
    var notes: FetchedResults<Note>

    @Binding var searchText: String
    @Binding var showingSettingsSheet: Bool

    @StateObject var viewModel: NotesListViewModel
    let persistenceController: SharedPersistenceController
    @State var showingFolderManagement = false
    @State var showingTrash = false
    @State var showingTagFilter = false
    @State var sidebarVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.jotleyOnboardingActive) var onboardingActive
    @StateObject var filterState = FilterAndSortState()
    @AppStorage("foldersExpanded") var foldersExpanded: Bool = false
    @AppStorage(RecordingWidgetController.widgetEnabledDefaultsKey) var showRecordingWidget: Bool = true
    @State var recordingWidgetController = RecordingWidgetController()

    init(recorder: ProcessTapRecorder, searchText: Binding<String>, showingSettingsSheet: Binding<Bool>, persistenceController: SharedPersistenceController) {
        self.persistenceController = persistenceController
        _viewModel = StateObject(wrappedValue: NotesListViewModel(viewContext: persistenceController.container.viewContext, recorder: recorder, persistenceController: persistenceController))
        _searchText = searchText
        _showingSettingsSheet = showingSettingsSheet
    }

}
