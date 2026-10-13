import SwiftUI
import AppKit

extension SettingsView {
    var visibleSections: [SettingsSection] { SettingsSection.allCases }
    @ViewBuilder func sectionHeader(for section: SettingsSection) -> some View {
        if section == .obsidian { Text("Integrations").font(.caption).foregroundColor(.secondary).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8) }
    }

    func sectionButton(for section: SettingsSection) -> some View {
        let isSelected = selectedSection == section

        return Button(action: {
            selectedSection = section
        }) {
            HStack(spacing: 12) {
                if section == .obsidian {
                    Image("obsidian-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .opacity(isSelected ? 1.0 : 0.9)
                } else {
                    Image(systemName: section.icon)
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? .themePrimaryAccent : .themeTextSecondary)
                        .frame(width: 16)
                }

                Text(section.rawValue)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .themePrimaryAccent : .themeTextSecondary)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                isSelected ?
                Color.themePrimaryAccent.opacity(0.14) : Color.clear
            )
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityIdentifier("settings\(section.rawValue.replacingOccurrences(of: " ", with: ""))Section")
    }

    var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .accessibilityIdentifier("settingsCloseButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleSections, id: \.self) { section in
                        sectionHeader(for: section)
                        sectionButton(for: section)
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity)


        }
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
