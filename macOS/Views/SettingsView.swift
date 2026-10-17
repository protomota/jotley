import SwiftUI
import AppKit
import FoundationModels

enum SettingsSection: String, CaseIterable {
    case general = "General", obsidian = "Obsidian"
    var icon: String { self == .general ? "gearshape" : "doc.text" }
}
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var persistenceController: SharedPersistenceController
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var updates = JotleyUpdates.shared
    @AppStorage(kJotleyObsidianSyncFolderBookmarkDefaultsKey) var obsidianSyncFolderBookmarkData: Data?
    @AppStorage("syncFolderAutoSyncEnabled") var syncFolderAutoSyncEnabled: Bool = true
    @AppStorage("syncFolderLastSyncTimestamp") var syncFolderLastSyncTimestamp: Double = 0
    @AppStorage("syncFolderLastSyncError") var syncFolderLastSyncError: String = ""
    @AppStorage("showTags") var showTags: Bool = false
    @AppStorage("showLiveCaptions") var showLiveCaptions: Bool = true
    @AppStorage(RecordingWidgetController.widgetEnabledDefaultsKey) var showRecordingWidget: Bool = true
    @AppStorage("transcriptionLanguage") var transcriptionLanguage: String = "en-US"
    @AppStorage("recordSystemAudio") var recordSystemAudio = true
    @State var selectedSection: SettingsSection = .general
    @State var showingThemeColorPicker = false
    @State var speechStatus = "Checking on-device models…"
    @State var speechNeedsSetup = false
    @State var speechLanguages: [LocalSpeech.Language] = []
    @State var isSettingUpSpeech = false
    @State var speechSetupProgress = 0.0
    @State var speechSetupError: String?
    @State var speechSetupTask: Task<Void, Never>?
    @AppStorage(NoteSyncMode.preferenceKey) var iCloudSyncEnabled = true
    var obsidianSyncFolderURL: URL? {
        guard let bookmarkData = obsidianSyncFolderBookmarkData else { return nil }
        var isStale: Bool = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale), !isStale else {
            return nil
        }
        return url
    }

    var obsidianSyncFolderPath: String {
        obsidianSyncFolderURL?.path ?? ""
    }


    func checkModels() async {
        let speech = await LocalSpeech.readiness(locale: Locale(identifier: transcriptionLanguage))
        let languages = await LocalSpeech.languages()
        guard !Task.isCancelled else { return }
        speechLanguages = languages
        if let matched = speech.configuration?.locale.identifier(.bcp47),
           matched != transcriptionLanguage,
           !languages.contains(where: { $0.id == transcriptionLanguage }),
           languages.contains(where: { $0.id == matched }) {
            transcriptionLanguage = matched
            return
        }
        speechNeedsSetup = speech.needsSetup || speechSetupError != nil
        let summary = LocalSummary.readiness(locale: Locale(identifier: transcriptionLanguage)) ?? "Built-in on-device summaries ready."
        let message = speech.status == .installed && speechSetupError != nil
            ? "Speech assets are installed, but transcription setup failed. Choose Set Up On-Device Speech to try again."
            : speech.message
        speechStatus = message + " " + summary
    }
    func setUpSpeech() {
        guard !isSettingUpSpeech else { return }
        let locale = Locale(identifier: transcriptionLanguage)
        isSettingUpSpeech = true; speechSetupProgress = 0; speechSetupError = nil
        speechSetupTask = Task { @MainActor in
            defer { isSettingUpSpeech = false; speechSetupTask = nil }
            do {
                try await LocalSpeech.setUp(locale: locale) { value in
                    await MainActor.run { speechSetupProgress = value }
                }
            } catch is CancellationError {
                speechSetupError = "Speech setup was canceled. Your notes and transcripts are unchanged."
            } catch {
                speechSetupError = Task.isCancelled ? "Speech setup was canceled." : "Speech setup failed: \(error.localizedDescription) Connect to the internet and try again."
            }
            await Task { @MainActor in await checkModels() }.value
        }
    }
    func selectObsidianSyncFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { obsidianSyncFolderBookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { speechStatus = error.localizedDescription }
    }
    func openObsidianSyncFolderInFinder() { if let url = obsidianSyncFolderURL { NSWorkspace.shared.open(url) } }
    var body: some View {
        HStack(spacing: 0) { sidebarView; Divider(); contentView.frame(maxWidth: .infinity, maxHeight: .infinity) }
            .frame(minWidth: 800, idealWidth: 900, maxWidth: 1200, minHeight: 560, idealHeight: 640, maxHeight: 820)
            .observeThemeChanges()
    }
}
