import SwiftUI
import CoreData

/// Folder pill shown next to the tag count in the iOS note detail view.
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
                Image(systemName: note.folder == nil ? "folder" : "folder.fill")
                    .foregroundStyle(Color.themePrimaryAccent)
                Text(note.folder?.displayName ?? String(localized: "No Folder"))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .noteMetadataPill(font: .footnote.weight(.medium), minHeight: 27)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("noteDetailFolderPicker")
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
                    .tint(Color.themePrimaryAccent)
                    .submitLabel(.done)
                    .onSubmit { commit() }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .jotleyDismissButtonStyle(inToolbar: true)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { commit() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(Color.themeActionText)
        .presentationDetents([.medium])
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
    }
}
