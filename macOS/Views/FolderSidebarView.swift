import SwiftUI
import CoreData

/// Collapsible folder list that lives at the top of the notes sidebar.
/// Selecting a folder scopes the notes list via `FilterAndSortState`.
struct FolderSidebarView: View {
    @ObservedObject var filterState: FilterAndSortState
    @Binding var isExpanded: Bool
    @Binding var showingFolderManagement: Bool

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    row(
                        title: "All Notes",
                        systemImage: "tray.full",
                        isSelected: filterState.selectedFolder == .all,
                        action: { filterState.selectedFolder = .all }
                    )
                    row(
                        title: "Unfiled",
                        systemImage: "tray",
                        isSelected: filterState.selectedFolder == .unfiled,
                        action: { filterState.selectedFolder = .unfiled }
                    )

                    if !folders.isEmpty {
                        Divider().padding(.vertical, 2)
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(folders) { folder in
                                    folderRow(folder)
                                }
                            }
                        }
                        .frame(maxHeight: foldersMaxHeight)
                    }

                    Button {
                        showingFolderManagement = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11))
                            Text("Manage Folders…")
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .foregroundColor(Color.themeTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("Create, rename, or delete folders")
                    .accessibilityIdentifier("notesListManageFoldersButton")
                }
                .padding(.leading, 4)
            }
        }
    }

    private var foldersMaxHeight: CGFloat {
        let rowHeight: CGFloat = 24
        let visibleRowCap = 6
        return CGFloat(min(folders.count, visibleRowCap)) * rowHeight
    }

    // MARK: - Rows

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.themeTextSecondary)
                Text("FOLDERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.themeTextSecondary)
                    .kerning(0.6)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Color.themePrimaryAccent : Color.themeTextSecondary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color.themeTextPrimary : Color.themeTextPrimary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.themePrimaryAccent.opacity(0.18) : Color.clear)
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
                filterState.selectedFolder = .folder(id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundColor(Color.themePrimaryAccent)
                    .frame(width: 14)
                Text(folder.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(Color.themeTextPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(folder.noteCount)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color.themeTextSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.themePrimaryAccent.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("folderSidebarRow-\(folder.displayName)")
    }
}
