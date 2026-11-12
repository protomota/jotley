import SwiftUI
import AppKit
import FoundationModels

enum SettingsSection: String, CaseIterable {
    case general = "General", templates = "Templates", obsidian = "Obsidian", mcp = "MCP"
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .templates: return "doc.text"
        case .obsidian: return "doc.text"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        }
    }
}
struct SettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var persistenceController: SharedPersistenceController
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var updates = JotleyUpdates.shared
    @ObservedObject var mcp = LocalAppModel.shared.mcp
    @AppStorage(kJotleyObsidianSyncFolderBookmarkDefaultsKey) var obsidianSyncFolderBookmarkData: Data?
    @AppStorage("syncFolderAutoSyncEnabled") var syncFolderAutoSyncEnabled: Bool = true
    @AppStorage("syncFolderLastSyncTimestamp") var syncFolderLastSyncTimestamp: Double = 0
    @AppStorage("syncFolderLastSyncError") var syncFolderLastSyncError: String = ""
    @AppStorage("showTags") var showTags: Bool = false
    @AppStorage(RecordingWidgetController.widgetEnabledDefaultsKey) var showRecordingWidget: Bool = true
    @AppStorage("transcriptionLanguage") var transcriptionLanguage: String = "en-US"
    @AppStorage(CustomSpeechWords.defaultsKey) var customWords = ""
    @AppStorage("recordSystemAudio") var recordSystemAudio = true
    @AppStorage(SummaryDisplayStyle.preferenceKey) var summaryDisplayStyle: SummaryDisplayStyle = .cards
    @State var selectedSection: SettingsSection = .general
    @State var mcpClient = "Claude Code app"
    @State var mcpShowingDetails = false
    @State var mcpCopiedItem: String?
    @State var mcpSetupMessage: String?
    var onShowWelcome: () -> Void = {}
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
        let speech = await LocalSpeech.readiness(locale: Locale(identifier: transcriptionLanguage), checkingCustomWordsSetup: true)
        let languages = await LocalSpeech.languages()
        guard !Task.isCancelled else { return }
        speechLanguages = languages
        if let matched = LocalSpeech.selectedLanguage(locale: Locale(identifier: transcriptionLanguage), in: languages)?.id,
           matched != transcriptionLanguage {
            transcriptionLanguage = matched
            return
        }
        speechNeedsSetup = speech.needsSetup || speechSetupError != nil
        let summary = LocalSummary.readiness(locale: Locale(identifier: transcriptionLanguage)) ?? "Built-in on-device summaries ready."
        let message = speech.status == .installed && speechSetupError != nil
            ? "Speech assets are installed, but transcription setup failed. Choose Set Up On-Device Speech to try again."
            : speech.customWordsStatus ?? speech.message
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
            .frame(width: min(1160, max(600, (NSScreen.main?.visibleFrame.width ?? 1240) - 80)),
                   height: min(780, max(480, (NSScreen.main?.visibleFrame.height ?? 880) - 100)))
            .presentationSizing(.fitted)
            .buttonStyle(JotleyGlassButtonStyle())
            .toggleStyle(MacSettingsSwitchStyle())
            .observeThemeChanges()
    }
}

private struct MacSettingsSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? Color.themePrimaryAccent : Color.secondary.opacity(0.28))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                            .frame(width: 18, height: 18)
                            .padding(2)
                    }
                    .frame(width: 40, height: 22)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isOn)
            }
            .foregroundStyle(isEnabled ? Color.primary : .secondary)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}
