import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var persistenceController: SharedPersistenceController
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @ObservedObject private var summaryNotifications = JotleySummaryNotifications.shared
    @State private var summaryNavigationID = UUID()
    @State private var navigationPath = NavigationPath()
    @State private var showingSettings = false
    @AppStorage(JotleyOnboarding.completedKey) private var onboardingCompleted = false
    @State private var selectedNoteId: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingTranscriptionModal = false
    @State private var newTranscriptionNote: Note?
    @State private var pendingWidgetAction: MobileTranscriptionAction?
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    notesList
                        .navigationSplitViewColumnWidth(min: 380, ideal: 420, max: 480)
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.2))
                                .frame(width: 1)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                } detail: {
                    NavigationStack {
                        if let selectedNoteId {
                            // Reset the fetch and tab/editor state when another note is selected.
                            NoteDetailByIdView(noteId: selectedNoteId).id(selectedNoteId).id(summaryNavigationID)
                        }
                        else { ContentUnavailableView("Select a Note", systemImage: "note.text", description: Text("Choose a note or tap + to transcribe live.")) }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $navigationPath) {
                    notesList
                        .navigationDestination(for: UUID.self) { id in
                            NoteDetailByIdView(noteId: id).id(summaryNavigationID)
                        }
                }
            }
        }
        .preferredColorScheme(themeManager.effectiveColorScheme)
        .observeThemeChanges()
        .modifier(JotleyOnboardingPresentation(onDismiss: {
            if let action = pendingWidgetAction { pendingWidgetAction = nil; handleWidgetAction(action) }
            openNotifiedSummary()
        }))
        .sheet(isPresented: $showingTranscriptionModal, onDismiss: {
            if let id = newTranscriptionNote?.id {
                openNote(id)
            }
            newTranscriptionNote = nil
            openNotifiedSummary()
        }) {
            LiveTranscriptionView(isPresented: $showingTranscriptionModal, existingNote: newTranscriptionNote, isNewTranscription: newTranscriptionNote != nil, transcriptionManager: transcriptionManager)
        }
        .onChange(of: summaryNotifications.noteToOpen, initial: true) { _, _ in openNotifiedSummary() }
        .onOpenURL { url in
            guard let action = MobileTranscriptionAction(url: url) else { return }
            if !onboardingCompleted && !JotleyOnboarding.bypassForFixture { pendingWidgetAction = action }
            else if showingSettings { pendingWidgetAction = action; showingSettings = false }
            else { handleWidgetAction(action) }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if let action = pendingWidgetAction { pendingWidgetAction = nil; handleWidgetAction(action) }
            openNotifiedSummary()
        }) {
            NavigationStack { SettingsView() }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .alert("Jotley", isPresented: Binding(get: { transcriptionManager.errorMessage != nil && !transcriptionManager.captureScreenVisible && newTranscriptionNote == nil && !showingTranscriptionModal && !transcriptionManager.isTranscribing && !transcriptionManager.busy }, set: { if !$0 { Task { @MainActor in transcriptionManager.errorMessage = nil } } })) {
            Button("OK", role: .cancel) { transcriptionManager.errorMessage = nil }
        } message: { Text(transcriptionManager.errorMessage ?? "") }
        .modifier(JotleyEngagementPrompts(isIdle: (onboardingCompleted || JotleyOnboarding.bypassForFixture) && !showingSettings && !showingTranscriptionModal && !transcriptionManager.isTranscribing && !transcriptionManager.busy && transcriptionManager.summaryNoteID == nil && transcriptionManager.errorMessage == nil))
    }
    private func handleWidgetAction(_ action: MobileTranscriptionAction) {
        switch action {
        case .start:
            if transcriptionManager.isTranscribing { showingTranscriptionModal = true; return }
            guard transcriptionManager.canStart, !showingTranscriptionModal else { return }
            do { newTranscriptionNote = try transcriptionManager.createNote(); showingTranscriptionModal = true }
            catch { transcriptionManager.errorMessage = error.localizedDescription }
        case .pause(let id):
            guard transcriptionManager.activeNoteID == id, !transcriptionManager.busy else { return }
            if transcriptionManager.transcriptionState == .listening { transcriptionManager.pauseTranscription() }
            else if transcriptionManager.transcriptionState == .paused { Task { await transcriptionManager.resumeTranscription() } }
        case .stop(let id):
            guard transcriptionManager.activeNoteID == id else { return }
            Task {
                await transcriptionManager.stopTranscription()
                newTranscriptionNote = nil
                showingTranscriptionModal = false
                openNote(id)
            }
        case .open(let id):
            if transcriptionManager.activeNoteID == id, transcriptionManager.isTranscribing { showingTranscriptionModal = true }
            else { openNote(id) }
        }
    }
    private func openNotifiedSummary() {
        guard onboardingCompleted || JotleyOnboarding.bypassForFixture,
              !showingSettings, !showingTranscriptionModal, let id = summaryNotifications.noteToOpen else { return }
        summaryNavigationID = UUID()
        openNote(id)
        summaryNotifications.noteToOpen = nil
    }
    private func openNote(_ id: UUID) {
        guard (try? persistenceController.notes().contains { $0.localNoteID == id }) == true else { return }
        if horizontalSizeClass == .regular { selectedNoteId = id }
        else { navigationPath = NavigationPath(); navigationPath.append(id) }
    }
    private var notesList: some View {
        NotesListView(navigationPath: $navigationPath, usesSplitView: horizontalSizeClass == .regular, showingSettings: $showingSettings,
            selectedNoteId: $selectedNoteId,
            showingTranscriptionModal: $showingTranscriptionModal, columnVisibility: $columnVisibility, newTranscriptionNote: $newTranscriptionNote)
    }
}

/// Reject malformed links and stale session IDs before starting transcription.
enum MobileTranscriptionAction: Equatable {
    case start, pause(UUID), stop(UUID), open(UUID)
    init?(url: URL) {
        guard url.scheme?.lowercased() == "jotley", url.path.isEmpty || url.path == "/",
              let host = url.host?.lowercased(), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if host == "starttranscription" || host == "startrecording" { self = .start; return }
        let ids = components.queryItems?.filter { $0.name == "id" } ?? []
        guard ids.count == 1, let value = ids.first?.value, let id = UUID(uuidString: value) else { return nil }
        switch host {
        case "pausetranscription", "pauserecording": self = .pause(id)
        case "stoptranscription", "stoprecording": self = .stop(id)
        case "transcription", "recording": self = .open(id)
        default: return nil
        }
    }
}
