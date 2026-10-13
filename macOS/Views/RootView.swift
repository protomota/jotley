import SwiftUI
struct RootView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var recorder: ProcessTapRecorder
    @EnvironmentObject var persistenceController: SharedPersistenceController
    @ObservedObject private var local = LocalAppModel.shared
    @State private var searchText = ""
    @State private var showingSettingsSheet = false
    var body: some View {
        NotesListView(recorder: recorder, searchText: $searchText, showingSettingsSheet: $showingSettingsSheet, persistenceController: persistenceController)
            .background(Color.themeContentBackground.ignoresSafeArea())
            .sheet(isPresented: $showingSettingsSheet) { SettingsView() }
            .observeThemeChanges()
            .modifier(JotleyEngagementPrompts(isIdle: !showingSettingsSheet && !local.busy && !recorder.isRecording && !recorder.isBusy))
            .safeAreaInset(edge: .bottom) {
                if !local.message.isEmpty {
                    HStack {
                        Text(local.message).font(.caption).foregroundColor(Color.themeTextSecondary)
                        if local.busy { ProgressView().controlSize(.small); Button("Cancel") { local.cancel() } }
                    }.padding(6)
                }
            }
    }
}
