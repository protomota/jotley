import SwiftUI
import UIKit

struct MainTabView: View {
    private let minimumSidebarWidth: CGFloat = 280
    @EnvironmentObject var persistenceController: SharedPersistenceController
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @ObservedObject private var summaryNotifications = JotleySummaryNotifications.shared
    @State private var summaryNavigationID = UUID()
    @State private var duoFooterHeight: CGFloat = 92
    @State private var windowBounds: CGRect = .zero
    @State private var windowContentBounds: CGRect = .zero
    @State private var detailBounds: CGRect = .zero
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var showingSettings = false
    @State private var showingWelcome = false
    @State private var replayAfterSettings = false
    @State private var returnToSettingsAfterWelcome = false
    private var onboardingInProgress: Bool {
        showingWelcome || replayAfterSettings || (!onboardingCompleted && !JotleyOnboarding.bypassForFixture)
    }
    @AppStorage(JotleyOnboarding.completedKey) private var onboardingCompleted = false
    @State private var selectedNoteId: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingTranscriptionModal = false
    @State private var newTranscriptionNote: Note?
    @State private var pendingWidgetAction: MobileTranscriptionAction?
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesExpandedPhoneLayout: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .phone
    }

    private var usesCornerCaptureButton: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var usesSideBySideFooter: Bool {
        usesExpandedPhoneLayout && detailBounds.minX >= windowBounds.minX + minimumSidebarWidth
    }

    private var usesWindowFooter: Bool {
        // Keep the native overlay-drawer route on Duo. A landscape phone's
        // leading safe area also needs the window host, without being a sidebar.
        usesCornerCaptureButton && (!usesExpandedPhoneLayout || detailBounds.minX > windowBounds.minX + 1)
    }

    private var footerBounds: CGRect {
        // A persistent sidebar owns its own space. Only single-column screens
        // and overlay drawers use controls centered on the whole window.
        guard usesSideBySideFooter else { return windowBounds }
        // The detail's trailing safe area reserves the system toolbar above.
        // Bottom actions can extend below that rail to the actual window edge.
        return CGRect(x: detailBounds.minX, y: windowBounds.minY,
                      width: windowBounds.maxX - detailBounds.minX, height: windowBounds.height)
    }

    var body: some View {
        // One navigation container survives folds, rotations and window resizing.
        // Replacing a split view with a separate stack loses the current detail's
        // tab, editor and sheet state when iPhone Duo changes displays.
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            notesList
                .navigationSplitViewColumnWidth(min: minimumSidebarWidth, ideal: 320, max: 420)
                .overlay(alignment: .trailing) {
                    if !usesExpandedPhoneLayout {
                        Rectangle()
                            .fill(Color.primary.opacity(0.2))
                            .frame(width: 1)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } detail: {
            Group {
                if let selectedNoteId {
                    NoteDetailByIdView(noteId: selectedNoteId, newTranscriptionAction: usesCornerCaptureButton ? { handleWidgetAction(.start) } : nil).id(selectedNoteId).id(summaryNavigationID)
                } else {
                    ContentUnavailableView("Select a Note", systemImage: "note.text", description: Text("Choose a note or tap + to transcribe live."))
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { detailBounds = $0 }
            // Keep the footer inside the native detail presentation. The Notes
            // drawer and its dimming layer must cover all detail controls.
            .overlayPreferenceValue(NoteFooterContentKey.self, alignment: .bottomTrailing) { footers in
                if usesCornerCaptureButton && !usesWindowFooter {
                    Group {
                        if let selectedNoteId, let footer = footers[selectedNoteId] { footer }
                        else { cornerCaptureFooter }
                    }
                    .frame(width: windowBounds.isEmpty ? nil : windowBounds.width)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { duoFooterHeight = $0 }
                    // The overlay aligns the footer's trailing edge with the
                    // detail. Translate that edge to the current window edge,
                    // retaining natural height as the device folds or rotates.
                    .offset(x: windowBounds.isEmpty || detailBounds.isEmpty ? 0 : windowBounds.maxX - detailBounds.maxX)
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .ignoresSafeArea(.container, edges: usesCornerCaptureButton ? .bottom : [])
        }
        .navigationSplitViewStyle(.balanced)
        .overlayPreferenceValue(NoteFooterContentKey.self, alignment: .bottom) { footers in
            if usesWindowFooter {
                Group {
                    if let selectedNoteId,
                       usesExpandedPhoneLayout || preferredCompactColumn == .detail,
                       let footer = footers[selectedNoteId] { footer }
                    else { cornerCaptureFooter }
                }
                .frame(width: footerBounds.isEmpty ? nil : footerBounds.width)
                .offset(x: footerBounds.isEmpty ? 0 : footerBounds.midX - windowContentBounds.midX)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { duoFooterHeight = $0 }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .ignoresSafeArea(.container, edges: usesWindowFooter ? .bottom : [])
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { windowContentBounds = $0 }
        .onGeometryChange(for: CGRect.self) { geometry in
            let frame = geometry.frame(in: .global)
            let insets = geometry.safeAreaInsets
            return CGRect(x: frame.minX - insets.leading, y: frame.minY - insets.top,
                          width: frame.width + insets.leading + insets.trailing,
                          height: frame.height + insets.top + insets.bottom)
        } action: { bounds in
            let becameWide = !windowBounds.isEmpty && windowBounds.width <= windowBounds.height && bounds.width > bounds.height
            windowBounds = bounds
            if usesExpandedPhoneLayout && becameWide { columnVisibility = .automatic }
        }
        .preferredColorScheme(themeManager.effectiveColorScheme)
        .observeThemeChanges()
        .modifier(JotleyOnboardingPresentation(replay: $showingWelcome, onDismiss: {
            if returnToSettingsAfterWelcome {
                returnToSettingsAfterWelcome = false
                if pendingWidgetAction == nil && summaryNotifications.noteToOpen == nil { showingSettings = true }
            }
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
            if onboardingInProgress { pendingWidgetAction = action }
            else if showingSettings { pendingWidgetAction = action; showingSettings = false }
            else { handleWidgetAction(action) }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if replayAfterSettings { replayAfterSettings = false; showingWelcome = true; return }
            if let action = pendingWidgetAction { pendingWidgetAction = nil; handleWidgetAction(action) }
            openNotifiedSummary()
        }) {
            NavigationStack {
                SettingsView(onShowWelcome: {
                    returnToSettingsAfterWelcome = true
                    replayAfterSettings = true
                    showingSettings = false
                })
            }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .alert("Jotley", isPresented: Binding(get: { transcriptionManager.errorMessage != nil && !transcriptionManager.captureScreenVisible && newTranscriptionNote == nil && !showingTranscriptionModal && !transcriptionManager.isTranscribing && !transcriptionManager.busy }, set: { if !$0 { Task { @MainActor in transcriptionManager.errorMessage = nil } } })) {
            Button("OK", role: .cancel) { transcriptionManager.errorMessage = nil }
        } message: { Text(transcriptionManager.errorMessage ?? "") }
        .modifier(JotleyEngagementPrompts(isIdle: !onboardingInProgress && !showingSettings && !showingTranscriptionModal && !transcriptionManager.isTranscribing && !transcriptionManager.busy && transcriptionManager.summaryNoteID == nil && transcriptionManager.errorMessage == nil))
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
        guard !onboardingInProgress,
              !showingSettings, !showingTranscriptionModal, let id = summaryNotifications.noteToOpen else { return }
        summaryNavigationID = UUID()
        openNote(id)
        summaryNotifications.noteToOpen = nil
    }
    private func openNote(_ id: UUID) {
        guard (try? persistenceController.notes().contains { $0.localNoteID == id }) == true else { return }
        selectedNoteId = id
        preferredCompactColumn = .detail
        if usesExpandedPhoneLayout && !usesSideBySideFooter {
            withAnimation { columnVisibility = .detailOnly }
        }
    }
    private var cornerCaptureFooter: some View {
        HStack {
            Spacer()
            NotesNewTranscriptionButton { handleWidgetAction(.start) }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
    }

    private var notesList: some View {
        NotesListView(onSelectNote: openNote, showsNewTranscriptionButton: !usesCornerCaptureButton, usesSplitView: horizontalSizeClass == .regular, bottomContentInset: usesWindowFooter ? duoFooterHeight : 0, showingSettings: $showingSettings,
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
