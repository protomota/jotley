import SwiftUI

extension SettingsView {
    var obsidianView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Obsidian Sync")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack {
                    Image("obsidian-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .padding(.trailing, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        if !obsidianSyncFolderPath.isEmpty {
                            Text("Current Sync Folder:")
                                .font(.caption)
                                .foregroundColor(Color.themeTextSecondary)
                            Button(action: openObsidianSyncFolderInFinder) {
                                Text(obsidianSyncFolderPath)
                                    .font(.callout)
                                    .underline()
                                    .foregroundColor(Color.themePrimaryAccent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .buttonStyle(.plain)
                            .help("Open sync folder in Finder")
                            .padding(.bottom, 4)
                        } else {
                            Text("No Obsidian sync folder selected.")
                                .font(.callout)
                                .foregroundColor(Color.themeTextSecondary)
                                .padding(.bottom, 4)
                        }

                        HStack(spacing: 12) {
                            Button(obsidianSyncFolderPath.isEmpty ? "Select Obsidian Sync Folder" : "Change Sync Folder") {
                                selectObsidianSyncFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.themePrimaryAccent)

                            Button("Export Selected Note…") {
                                LocalAppModel.shared.exportObsidian()
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.themePrimaryAccent)
                            .disabled(obsidianSyncFolderPath.isEmpty)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Setup")
                        .font(.headline)

                    Text("1. Create a folder anywhere inside your Obsidian vault.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("2. In Jotley, select that folder as your Obsidian sync folder.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("3. Jotley creates `YYYY-MM-DD` subfolders inside that sync folder and writes notes into the matching date folder.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }

            }
            .padding(32)
        }
    }
}
