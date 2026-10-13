import SwiftUI
import CoreData

/// Compact folder row shown in the iOS note detail view above the tags section.
/// Displays the current folder (or "No folder") and opens a picker menu on tap.
struct iOSNoteFolderRow: View {
    @Environment(\.managedObjectContext) private var viewContext
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
        HStack(spacing: 6) {
            Image(systemName: note.folder == nil ? "folder" : "folder.fill")
                .foregroundColor(note.folder == nil ? .themeTextSecondary : .themePrimaryAccent)
            Menu {
                if note.folder != nil {
                    Button("Remove from folder", role: .destructive) {
                        note.clearFolder()
                        onChange()
                    }
                    Divider()
                }
                if folders.isEmpty {
                    Text("No folders yet")
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
                    Text(note.folder?.displayName ?? "No folder")
                        .foregroundColor(.themeTextSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.themeTextSecondary)
                }
            }
        }
        .font(.footnote)
        .sheet(isPresented: $showingCreate) {
            NewFolderInlineSheetiOS(
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

private struct NewFolderInlineSheetiOS: View {
    @Binding var name: String
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name)
                    .submitLabel(.done)
                    .onSubmit { commit() }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { commit() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
    }
}
