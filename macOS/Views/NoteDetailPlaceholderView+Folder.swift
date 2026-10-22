import SwiftUI
import CoreData

extension NoteDetailPlaceholderView {
    /// Compact folder chip shown in the note detail metadata row.
    /// Tapping opens a menu to assign, change, or clear the folder, or create a new one.
    var folderChip: some View {
        FolderChipView(note: note, onChange: { saveContext() })
    }
}

/// Isolated chip view so it can fetch folders via @FetchRequest without
/// bloating NoteDetailPlaceholderView's state.
struct FolderChipView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject var note: Note
    let onChange: () -> Void

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>

    @State private var showingCreate = false
    @State private var newFolderName = ""

    var body: some View {
        Menu {
            if let current = note.folder {
                Button("Remove from “\(current.displayName)”") {
                    note.clearFolder()
                    onChange()
                }
                Divider()
            }

            if folders.isEmpty {
                Text("No folders yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(folders) { folder in
                    Button {
                        note.assignFolder(folder)
                        onChange()
                    } label: {
                        if note.folder?.objectID == folder.objectID {
                            Label(folder.displayName, systemImage: "checkmark")
                        } else {
                            Text(folder.displayName)
                        }
                    }
                }
                Divider()
            }

            Button("New Folder…") {
                newFolderName = ""
                showingCreate = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: note.folder == nil ? "folder" : "folder.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.currentThemeColor.color)
                Text(note.folder?.displayName ?? "No Folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.currentThemeColor.color)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.currentThemeColor.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.themeAccent.opacity(0.35))
            )
        }
        .menuStyle(.button).buttonStyle(.plain)
        .tint(theme.currentThemeColor.color)
        .fixedSize()
        .accessibilityIdentifier("noteDetailFolderChip")
        .sheet(isPresented: $showingCreate) {
            NewFolderInlineSheet(
                name: $newFolderName,
                onCreate: { name in
                    let folder = Folder.getOrCreate(named: name, in: viewContext)
                    note.assignFolder(folder)
                    onChange()
                    showingCreate = false
                },
                onCancel: { showingCreate = false }
            )
        }
    }
}

/// Small sheet for creating a new folder inline from the detail chip.
private struct NewFolderInlineSheet: View {
    @Binding var name: String
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Folder")
                .font(.headline)
            TextField("Folder name", text: $name)
                .tint(Color.themePrimaryAccent)
                .accentColor(Color.themePrimaryAccent)
                .modifier(JotleyFormInputStyle())
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .buttonStyle(JotleyGlassButtonStyle())
        .padding(20)
        .frame(minWidth: 320)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
    }
}
