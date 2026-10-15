import SwiftUI
import FoundationModels
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "en-US"
    @State private var modelStatus = "Checking installed Apple models…"
    @State private var speechNeedsSetup = false
    @State private var isSettingUpSpeech = false
    @State private var speechSetupProgress = 0.0
    @State private var speechSetupError: String?
    @State private var speechSetupTask: Task<Void, Never>?
    @State private var speechLanguages: [LocalSpeech.Language] = []
    @State private var speechDetails = ""
    @State private var speechIsReady = false
    @EnvironmentObject private var persistenceController: SharedPersistenceController
    @AppStorage(NoteSyncMode.preferenceKey) private var iCloudSyncEnabled = true
    private let macDownloadURL = URL(string: "https://jotley.ai/download")!
    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
    var body: some View {
        Form {
            Section {
                Menu {
                    Picker("Appearance Mode", selection: $themeManager.currentAppearanceMode) {
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                        Text("System").tag(AppearanceMode.system)
                    }
                } label: {
                    selectionLabel("Appearance Mode", value: themeManager.currentAppearanceMode.rawValue)
                }
                .accessibilityIdentifier("settingsAppearanceModePicker")
                .onChange(of: themeManager.currentAppearanceMode) { _, newValue in
                    themeManager.setAppearanceMode(newValue)
                }

                Menu {
                    Picker("Theme Color", selection: $themeManager.currentThemeColor) {
                        ForEach(ThemeColor.allCases, id: \.self) { color in
                            HStack {
                                Circle().fill(color.previewColor).frame(width: 20, height: 20)
                                Text(color.displayName)
                            }.tag(color)
                        }
                    }
                } label: {
                    selectionLabel("Theme Color", value: themeManager.currentThemeColor.displayName)
                }
                .accessibilityIdentifier("settingsThemeColorPicker")
                .onChange(of: themeManager.currentThemeColor) { _, newValue in
                    themeManager.setThemeColor(newValue)
                }

            } header: {
                Text("Appearance")
            }

            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.themePrimaryAccent)
                        .padding(12)
                        .background(Color.themePrimaryAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your voice notes. Now on Mac.").font(.headline)
                        Text("Jotley for Mac is completely free. Record your microphone and audio from meetings, apps and your browser, then transcribe and summarize on-device.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)

                Link(destination: macDownloadURL) {
                    MobileActionLabel("Mac Download & Installation Guide", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("settingsMacDownloadLink")
                ShareLink(item: macDownloadURL) {
                    MobileActionLabel("Send Download Link to Your Mac", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("settingsShareMacDownloadLink")
            } header: {
                Text("Jotley for Mac")
            } footer: {
                Text("On your Mac, visit jotley.ai/download and drag Jotley into Applications. Requires Apple silicon, macOS 27 or later and Apple Intelligence enabled. Notes sync through iCloud when enabled on both devices; audio captured on Mac stays on that Mac. New iPhone and iPad sessions save transcripts without audio files.")
            }

            // Transcription Settings
            Section("Transcription") {
                Menu {
                    Picker("Language", selection: Binding(
                        get: { speechLanguages.contains(where: { $0.id == transcriptionLanguage }) ? transcriptionLanguage : "" },
                        set: { transcriptionLanguage = $0 }
                    )) {
                        if !speechLanguages.contains(where: { $0.id == transcriptionLanguage }) {
                            Text("Choose a supported language").tag("").disabled(true)
                        }
                        ForEach(speechLanguages) { language in Text(language.name).tag(language.id) }
                    }
                } label: {
                    selectionLabel("Language", value: speechLanguages.first(where: { $0.id == transcriptionLanguage })?.name ?? "Choose a supported language")
                }
                .accessibilityIdentifier("settingsLanguagePicker")
                .disabled(isSettingUpSpeech)
            }

            Section("Built-in Models") {
                Text(modelStatus).font(.footnote).accessibilityIdentifier("settingsModelStatus")
                if isSettingUpSpeech {
                    ProgressView("Setting up Apple speech…", value: speechSetupProgress)
                        .accessibilityIdentifier("settingsSpeechSetupProgress")
                    Button("Cancel Setup") { speechSetupTask?.cancel() }
                } else if speechNeedsSetup {
                    Button("Set Up On-Device Speech") { setUpSpeech() }
                        .accessibilityIdentifier("settingsSpeechSetupButton")
                }
                if let speechSetupError { Text(speechSetupError).font(.footnote).accessibilityIdentifier("settingsSpeechSetupError") }
                if !speechIsReady && !isSettingUpSpeech {
                    Button("Refresh Speech Availability") { Task { await checkModels() } }
                        .accessibilityIdentifier("settingsSpeechRefreshButton")
                }
                DisclosureGroup("Speech Details") {
                    Text(speechDetails).font(.caption).textSelection(.enabled)
                    ShareLink(item: speechDetails) { Label("Share Speech Details", systemImage: "square.and.arrow.up") }
                }
                Text("Speech setup installs the selected language's model from Apple once and requires internet access. After setup, live transcription and summaries run on-device and work offline. New iPhone and iPad sessions do not save audio files. Audio and notes are never sent to an AI service.").font(.caption).foregroundColor(.secondary)
            }
            Section("iCloud Sync") {
                if NoteSyncMode.configuredIdentifier(in: Bundle.main.infoDictionary ?? [:]) != nil {
                    Toggle("Sync notes with iCloud after restarting Jotley", isOn: $iCloudSyncEnabled)
                        .tint(Color.themePrimaryAccent)
                        .accessibilityIdentifier("settingsICloudSyncToggle")
                }
                Text("Sync is on by default in iCloud-enabled builds. You can turn it off here. It sends notes, transcripts, summaries, folders and tags to your private iCloud database. Audio and AI processing stay on this device. Changes take effect after closing and reopening Jotley; disabling does not delete data already in iCloud.")
                    .font(.caption).foregroundColor(.secondary)
                Text(NoteSyncMode.configuredIdentifier(in: Bundle.main.infoDictionary ?? [:]) == nil
                     ? "iCloud sync requires a signed build configured with an iCloud container. This build saves notes only on this iPhone."
                     : (persistenceController.syncMode.isEnabled ? "iCloud sync is enabled for this session. Apple schedules synchronization when available." : "iCloud sync is off for this session."))
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Support Jotley") { JotleySupportLinks() }
            Section("About") {
                Text("Jotley · Free · Offline")
                Text(versionLine).lineLimit(1).accessibilityIdentifier("settingsAppVersion")
                Text("Requires iOS or iPadOS 27 and Apple Intelligence-capable hardware: iPhone 15 Pro/Pro Max, iPhone 16 or newer, iPhone Air, iPad with M1 or later, or iPad mini with A17 Pro.").font(.caption)
            }
        }
        .scrollContentBackground(.hidden).background(Color.themeBackground)
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .tint(Color.themeActionText)
        .toolbar { ToolbarItem(placement: .confirmationAction) { MobileDoneButton(inToolbar: true) { dismiss() }.accessibilityIdentifier("settingsDoneButton") } }
        .task(id: transcriptionLanguage) { await checkModels() }
        .onDisappear { speechSetupTask?.cancel() }
        .preferredColorScheme(themeManager.effectiveColorScheme).observeThemeChanges()
    }
    /// Native menu selection stays intact; explicit label colors avoid a stale
    /// selected-value tint when a presented Form changes appearance.
    private func selectionLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.themeTextPrimary)
            Spacer()
            Text(value).foregroundStyle(Color.themeTextSecondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold)).foregroundStyle(Color.themeTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func checkModels() async {
        let locale = Locale(identifier: transcriptionLanguage)
        let speech = await LocalSpeech.readiness(locale: locale)
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
        speechIsReady = speech.status == .installed && speechSetupError == nil
        speechDetails = "\(versionLine)\nDevice: \(MobileDeviceEligibility.identifier)\niOS/iPadOS: \(UIDevice.current.systemVersion)\n\(speech.details)"
        if let speechSetupError { speechDetails += "\nLast setup error: \(speechSetupError)" }
        if let lastFailure = UserDefaults.standard.string(forKey: LocalSpeech.lastFailureDefaultsKey) {
            speechDetails += "\nLast speech failure: \(lastFailure)"
        }
        speechNeedsSetup = speech.needsSetup || speechSetupError != nil
        var statuses = [speech.status == .installed && speechSetupError != nil
            ? "Speech assets are installed, but transcription setup failed. Choose Set Up On-Device Speech to try again."
            : speech.message]
        // Model variant metadata is absent from some iOS 27 framework builds.
        // Readiness uses the stable availability API without requiring that symbol.
        statuses.append(LocalSummary.readiness(locale: locale) ?? "On-device summaries ready.")
        modelStatus = statuses.joined(separator: " ")
    }
    private func setUpSpeech() {
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
                speechSetupError = "Speech setup was canceled. Your notes are unchanged."
            } catch {
                let underlying = error as NSError
                speechSetupError = Task.isCancelled ? "Speech setup was canceled." : "Speech setup failed: \(underlying.localizedDescription) (\(underlying.domain), \(underlying.code)). Connect to the internet and try again."
            }
            // Recheck in a fresh task even after cancellation so the retry stays available.
            await Task { @MainActor in await checkModels() }.value
        }
    }
}
