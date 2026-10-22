import SwiftUI
import CoreData

/// Vertical folder drawer presented as a sheet. Replaces the horizontal
/// chip row. Tapping a row scopes the notes list to that folder and
/// dismisses the drawer.
struct iOSFolderDrawer: View {
    @ObservedObject var filterState: FilterAndSortState
    @Binding var showingFolderManagement: Bool
    var onDone: () -> Void

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 2) {
                    row(
                        title: "All Notes",
                        systemImage: "tray.full",
                        count: nil,
                        isSelected: filterState.selectedFolder == .all
                    ) {
                        select(.all)
                    }

                    row(
                        title: "Unfiled",
                        systemImage: "tray",
                        count: nil,
                        isSelected: filterState.selectedFolder == .unfiled
                    ) {
                        select(.unfiled)
                    }

                    if !folders.isEmpty {
                        Divider()
                            .overlay(Color.themeTextSecondary.opacity(0.2))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)

                        ForEach(folders) { folder in
                            folderRow(folder)
                        }
                    } else {
                        folderEmptyState
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()
                .overlay(Color.themeTextSecondary.opacity(0.2))

            Button {
                showingFolderManagement = true
                onDone()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 16))
                    Text("Manage Folders")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.themeTextSecondary)
                }
                .foregroundColor(Color.themeTextPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("folderDrawerManageButton")
        }
        .background(Color.themeBackground)
    }

    private var header: some View {
        HStack {
            Text("Folders")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.themeTextPrimary)
            Spacer()
            MobileDoneButton(action: onDone)
            .accessibilityIdentifier("folderDrawerDoneButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var folderEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30))
                .foregroundColor(Color.themeTextSecondary)
            Text("No folders yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.themeTextPrimary)
            Text("Tap “Manage Folders” below to create your first folder, then file notes into it from any note.")
                .font(.system(size: 13))
                .foregroundColor(Color.themeTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func row(title: String, systemImage: String, count: Int?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundColor(isSelected ? Color.themePrimaryAccent : Color.themeTextSecondary)
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(Color.themeTextPrimary)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 14, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Color.themeTextSecondary)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.themePrimaryAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color.themePrimaryAccent.opacity(0.12) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func folderRow(_ folder: Folder) -> some View {
        let isSelected: Bool = {
            if case .folder(let id) = filterState.selectedFolder {
                return id == folder.id
            }
            return false
        }()

        return Button {
            if let id = folder.id {
                select(.folder(id))
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundColor(isSelected ? Color.themePrimaryAccent : Color.themeTextSecondary)
                Text(folder.displayName)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(Color.themeTextPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(folder.noteCount)")
                    .font(.system(size: 14, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color.themeTextSecondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.themePrimaryAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color.themePrimaryAccent.opacity(0.12) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("folderDrawerRow-\(folder.displayName)")
    }

    private func select(_ selection: FolderSelection) {
        filterState.selectedFolder = selection
        onDone()
    }
}

/// Single horizontally-scrollable row of pills shown in the notes list header
/// when a folder scope and/or tag filters are active. Folder pill (if any) is
/// rendered first, followed by a pill for each selected tag. Tapping a pill
/// opens the relevant sheet; tapping its X clears just that item.
struct iOSCurrentScopeIndicator: View {
    @ObservedObject var filterState: FilterAndSortState
    var onFolderTap: () -> Void
    var onTagTap: () -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Folder.name, ascending: true)]
    )
    private var folders: FetchedResults<Folder>

    private var folderLabel: (name: String, systemImage: String)? {
        switch filterState.selectedFolder {
        case .all:
            return nil
        case .unfiled:
            return ("Unfiled", "tray")
        case .folder(let id):
            guard let folder = folders.first(where: { $0.id == id }) else {
                return nil
            }
            return (folder.displayName, "folder.fill")
        }
    }

    var body: some View {
        if folderLabel != nil || !filterState.selectedTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let folderLabel {
                        scopePill(
                            systemImage: folderLabel.systemImage,
                            text: folderLabel.name,
                            onTap: onFolderTap,
                            onClear: { filterState.selectedFolder = .all },
                            clearIdentifier: "currentFolderClearButton"
                        )
                        .accessibilityIdentifier("currentFolderIndicator")
                    }

                    ForEach(filterState.selectedTags.sorted(), id: \.self) { tag in
                        scopePill(
                            systemImage: "tag.fill",
                            text: tag,
                            onTap: onTagTap,
                            onClear: { filterState.selectedTags.remove(tag) },
                            clearIdentifier: "currentTagClearButton-\(tag)"
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .accessibilityIdentifier("currentScopeIndicator")
        }
    }

    @ViewBuilder
    private func scopePill(
        systemImage: String,
        text: String,
        onTap: @escaping () -> Void,
        onClear: @escaping () -> Void,
        clearIdentifier: String
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                    Text(text)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(Color.themeTextOnAccent)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.themeTextOnAccent.opacity(0.9))
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(clearIdentifier)
        }
        .background(
            Capsule()
                .fill(Color.themePrimaryAccent)
        )
    }
}
