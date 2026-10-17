import SwiftUI
import AppKit

extension SettingsView {
    var generalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("General")
                        .font(.title2)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Appearance")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Appearance Mode")
                                    .frame(width: 120, alignment: .leading)

                                Picker("", selection: $themeManager.currentAppearanceMode) {
                                    Text("Light").tag(AppearanceMode.light)
                                    Text("Dark").tag(AppearanceMode.dark)
                                    Text("System").tag(AppearanceMode.system)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                                .tint(.themePrimaryAccent)
                            }

                            HStack {
                                Text("Theme Color")
                                    .frame(width: 120, alignment: .leading)

                                ThemeColorDropdown(
                                    selection: $themeManager.currentThemeColor,
                                    isShowing: $showingThemeColorPicker
                                )
                                .frame(width: 150)
                            }


                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Display Options")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Show Tags", isOn: $showTags)
                                .toggleStyle(.switch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Show Live Captions", isOn: $showLiveCaptions)
                                .toggleStyle(.switch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Show Floating Transcription Indicator", isOn: $showRecordingWidget)
                                .toggleStyle(.switch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(.themePrimaryAccent)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Transcription")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {

                            HStack {
                                Text("Language")
                                    .frame(width: 120, alignment: .leading)

                                Picker("", selection: Binding(
                                    get: { speechLanguages.contains(where: { $0.id == transcriptionLanguage }) ? transcriptionLanguage : "" },
                                    set: { transcriptionLanguage = $0 }
                                )) {
                                    if !speechLanguages.contains(where: { $0.id == transcriptionLanguage }) {
                                        Text("Choose a supported language").tag("").disabled(true)
                                    }
                                    ForEach(speechLanguages) { language in Text(language.name).tag(language.id) }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 220)
                                .disabled(isSettingUpSpeech)
                            }

                            Text("Select the language for audio transcription. Availability depends on installed Apple speech assets.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Toggle("Transcribe microphone and system audio", isOn: $recordSystemAudio)
                                .toggleStyle(.switch)
                            Text(speechStatus).font(.caption).foregroundColor(.secondary)
                            if isSettingUpSpeech {
                                ProgressView("Setting up Apple speech…", value: speechSetupProgress)
                                Button("Cancel Setup") { speechSetupTask?.cancel() }
                            } else if speechNeedsSetup {
                                Button("Set Up On-Device Speech") { setUpSpeech() }
                                    .accessibilityIdentifier("settingsSpeechSetupButton")
                            }
                            if let speechSetupError { Text(speechSetupError).font(.caption) }
                            Text("Speech setup installs the selected language's model from Apple once and requires internet access. After setup, transcription and summaries run on-device and work offline. Audio and notes are never sent to an AI service.")
                                .font(.caption).foregroundColor(.secondary)

                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("iCloud Sync").font(.headline)
                        if NoteSyncMode.configuredIdentifier(in: Bundle.main.infoDictionary ?? [:]) != nil {
                            Toggle("Sync notes with iCloud after restarting Jotley", isOn: $iCloudSyncEnabled)
                                .accessibilityIdentifier("settingsICloudSyncToggle")
                        }
                        Text("Sync is on by default in iCloud-enabled builds. You can turn it off here. It sends notes, transcripts, summaries, folders and tags to your private iCloud database. Audio and AI processing stay on this Mac. Changes take effect after quitting and reopening Jotley; disabling does not delete data already in iCloud.")
                            .font(.caption).foregroundColor(.secondary)
                        Text(NoteSyncMode.configuredIdentifier(in: Bundle.main.infoDictionary ?? [:]) == nil
                             ? "iCloud sync requires a signed build configured with an iCloud container. This build saves notes only on this Mac."
                             : (persistenceController.syncMode.isEnabled ? "iCloud sync is enabled for this session. Apple schedules synchronization when available." : "iCloud sync is off for this session."))
                            .font(.caption).foregroundColor(.secondary)
                    }

                    if updates.isEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Updates").font(.headline)
                            Toggle("Check for updates automatically", isOn: Binding(
                                get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }
                            )).toggleStyle(.switch)
                            Button("Check for Updates…") { updates.check() }
                                .disabled(!updates.canCheck || !updates.isIdle)
                            Text("Sparkle checks jotley.ai for signed app updates. Updates require internet access; transcription and summaries continue to work offline. Your notes and audio are never included in update checks.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Support Jotley").font(.headline)
                        JotleySupportLinks()
                        Divider()
                        Text("About")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Version")
                                    .frame(width: 120, alignment: .leading)
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")
                                    .foregroundColor(.secondary)
                                    .font(.callout)
                            }
                            HStack {
                                Text("Build")
                                    .frame(width: 120, alignment: .leading)
                                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                                    .foregroundColor(.secondary)
                                    .font(.callout)
                            }
                        }
                    }

                }
            }
            .padding(32)
        }
        .task(id: transcriptionLanguage) { await checkModels() }
        .onDisappear { speechSetupTask?.cancel() }

    }
}
