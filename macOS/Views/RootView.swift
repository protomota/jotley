import SwiftUI
struct RootView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var recorder: ProcessTapRecorder
    @EnvironmentObject var persistenceController: SharedPersistenceController
    @ObservedObject private var local = LocalAppModel.shared
    @State private var searchText = ""
    @State private var showingSettingsSheet = false
    @State private var showingWelcome = false
    @State private var replayAfterSettings = false
    @State private var returnToSettingsAfterWelcome = false
    private var onboardingInProgress: Bool {
        showingWelcome || replayAfterSettings || (!onboardingCompleted && !JotleyOnboarding.bypassForFixture)
    }
    @AppStorage(JotleyOnboarding.completedKey) private var onboardingCompleted = false
    var body: some View {
        NotesListView(recorder: recorder, searchText: $searchText, showingSettingsSheet: $showingSettingsSheet, persistenceController: persistenceController)
            .background(Color.themeContentBackground.ignoresSafeArea())
            .sheet(isPresented: $showingSettingsSheet, onDismiss: {
                if replayAfterSettings { replayAfterSettings = false; showingWelcome = true }
            }) {
                SettingsView(onShowWelcome: {
                    returnToSettingsAfterWelcome = true
                    replayAfterSettings = true
                    showingSettingsSheet = false
                }).buttonStyle(JotleyGlassButtonStyle())
            }
            .buttonStyle(JotleyGlassButtonStyle())
            .observeThemeChanges()
            .modifier(JotleyOnboardingPresentation(replay: $showingWelcome, onDismiss: {
                if returnToSettingsAfterWelcome {
                    returnToSettingsAfterWelcome = false
                    showingSettingsSheet = true
                }
            }))
            .modifier(JotleyEngagementPrompts(isIdle: !onboardingInProgress && !showingSettingsSheet && !local.busy && !recorder.isRecording && !recorder.isBusy))
            .preferredColorScheme(onboardingInProgress ? .light : themeManager.effectiveColorScheme)
            .safeAreaInset(edge: .bottom) {
                if !onboardingInProgress && !local.message.isEmpty {
                    HStack {
                        Text(local.message).font(.caption).foregroundColor(Color.themeTextSecondary)
                        if local.busy { ProgressView().progressViewStyle(MacThemedCircularProgressStyle()).controlSize(.small); Button("Cancel") { local.cancel() } }
                    }.padding(6)
                }
            }
    }
}
