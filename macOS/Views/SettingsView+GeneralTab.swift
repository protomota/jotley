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

                            SettingsDropdown(title: "Theme Color", selection: $themeManager.currentThemeColor,
                                             options: ThemeColor.allCases, optionTitle: { $0.displayName },
                                             swatch: { $0.color(in: themeManager.effectiveColorScheme ?? colorScheme) })
                                .accessibilityIdentifier("settingsThemePicker")
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summaries").font(.headline)
                        SettingsDropdown(title: "Summary Style", selection: $summaryDisplayStyle,
                                         options: SummaryDisplayStyle.allCases, optionTitle: { $0.title })
                            .accessibilityIdentifier("summaryDisplayStylePicker")
                        Text("Cards adds visual sections. Standard Text uses clean headings and bullets. Your choice applies to every note and can also be changed from a note’s More menu.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Note Organization").font(.headline)
                        JotleyNoteOrganizationSettings()
                        Text("Auto Tags adds five topics to recordings and summaries. Auto File Notes organizes completed recordings and unfiled summaries into a matching project or broad folder.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Notifications").font(.headline)
                        JotleySummaryNotificationSettings()
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Display Options")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Show Tags", isOn: $showTags)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Show Transcription Indicator When Jotley Is in Background", isOn: $showRecordingWidget)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Transcription")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {

                            SettingsDropdown(title: "Preferred Language", selection: $transcriptionLanguage,
                                             options: speechLanguages.map(\.id), placeholder: "Choose a supported language",
                                             optionTitle: { id in speechLanguages.first { $0.id == id }?.name ?? id })
                                .disabled(isSettingUpSpeech)
                                .accessibilityIdentifier("settingsLanguagePicker")

                            Text("Choose an Apple Intelligence language supported by this Mac for transcription, summaries and Ask AI. Apple speech may need a one-time setup; existing notes and the app’s interface language stay unchanged.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            CustomSpeechWordsButton().disabled(isSettingUpSpeech)
                            Toggle("Transcribe microphone and system audio", isOn: $recordSystemAudio)
                            Text(speechStatus).font(.caption).foregroundColor(.secondary)
                            if isSettingUpSpeech {
                                ProgressView("Setting up Apple speech…", value: speechSetupProgress).tint(.themePrimaryAccent)
                                Button("Cancel Setup") { speechSetupTask?.cancel() }
                                    .jotleyDismissButtonStyle()
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

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Backup & Restore").font(.headline)
                        LibraryBackupControls()
                    }

                    if updates.isEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Updates").font(.headline)
                            Toggle("Check for updates automatically", isOn: Binding(
                                get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }
                            ))
                            Button("Check for Updates…") { updates.check() }
                                .disabled(!updates.canCheck || !updates.isIdle)
                            Text("Sparkle checks jotley.ai for signed app updates. Updates require internet access; transcription and summaries continue to work offline. Your notes and audio are never included in update checks.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About")
                            .font(.headline)
                        JotleyAboutLogo()
                        JotleySupporterBadge()

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
                        Divider()
                        Button("Welcome to Jotley", systemImage: "sparkles") { onShowWelcome() }
                            .accessibilityIdentifier("settingsWelcomeJotley")
                        ProtomotaAppHelpLink()
                        JotleyTechnicalSupportButton()
                        JotleySupportLinks()
                    }

                }
            }
            .padding(32)
        }
        .task(id: [transcriptionLanguage, customWords]) { await checkModels() }
        .onDisappear { speechSetupTask?.cancel() }

    }
}
