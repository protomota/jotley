import SwiftUI
import CoreData

/// Create / rename / delete folders. Shared across macOS and iOS.
/// Folder deletion unfiles associated notes (they are not deleted)
/// thanks to the Nullify deletion rule on the Folder.notes relationship.
struct FolderManagementSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ],
        animation: .default
    )
    private var folders: FetchedResults<Folder>

    @State private var newFolderName: String = ""
    @State private var renamingFolder: Folder?
    @State private var renameText: String = ""
    @State private var pendingDelete: Folder?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Folders")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.themeTextPrimary)
                Spacer()
                #if os(iOS)
                MobileDoneButton { dismiss() }
                    .accessibilityIdentifier("folderManagementDoneButton")
                #else
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("folderManagementDoneButton")
                #endif
            }

            createRow

            Text("Name your folder, then choose Create Folder. Find it in the Folders menu to organize your notes.")
                .font(.caption)
                .foregroundColor(Color.themeTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if folders.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 32))
                        .foregroundColor(Color.themeTextSecondary)
                    Text("No folders yet")
                        .font(.subheadline)
                        .foregroundColor(Color.themeTextSecondary)
                    Text("Create a folder above to start organizing notes.")
                        .font(.caption)
                        .foregroundColor(Color.themeTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(folders) { folder in
                            folderRow(folder)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 360)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 420, minHeight: 360)
        #else
        .frame(maxWidth: .infinity, minHeight: 360)
        #endif
        .background(Color.themeContentBackground)
        #if os(iOS)
        .tint(Color.themeActionText)
        #endif
        .observeThemeChanges()
        .alert(
            "Delete Folder?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { folder in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                deleteFolder(folder)
                pendingDelete = nil
            }
        } message: { folder in
            Text("“\(folder.displayName)” will be removed. \(folder.noteCount) note\(folder.noteCount == 1 ? "" : "s") in this folder will become Unfiled.")
        }
    }

    // MARK: - Subviews

    private var createRow: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 12) {
            TextField("New folder name", text: $newFolderName)
                .font(.body).foregroundStyle(Color.themeTextPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16).frame(minHeight: 56)
                .background(Color.themeBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeTextSecondary.opacity(0.25)))
                .submitLabel(.done).onSubmit(createFolder)
                .accessibilityIdentifier("newFolderNameField")
            Button(action: createFolder) {
                Label("Create Folder", systemImage: "folder.badge.plus")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(.themePrimaryAccent)
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("createFolderButton")
        }
        #else
        HStack(spacing: 8) {
            TextField("New folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createFolder)
            Button("Create Folder") { createFolder() }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        #endif
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundColor(Color.themePrimaryAccent)
            if renamingFolder?.objectID == folder.objectID {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(folder) }
                Button("Save") { commitRename(folder) }
                    .buttonStyle(.borderless)
                Button("Cancel") {
                    renamingFolder = nil
                    renameText = ""
                }
                .buttonStyle(.borderless)
            } else {
                Text(folder.displayName)
                    .foregroundColor(Color.themeTextPrimary)
                Spacer()
                Text("\(folder.noteCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color.themeTextSecondary)
                Button {
                    renamingFolder = folder
                    renameText = folder.displayName
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Rename folder")

                Button {
                    pendingDelete = folder
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete folder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.themeAccent.opacity(0.25))
        )
    }

    // MARK: - Actions

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = Folder.getOrCreate(named: trimmed, in: viewContext)
        save()
        newFolderName = ""
    }

    private func commitRename(_ folder: Folder) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            folder.name = trimmed
            save()
        }
        renamingFolder = nil
        renameText = ""
    }

    private func deleteFolder(_ folder: Folder) {
        viewContext.delete(folder)
        save()
    }

    private func save() {
        do {
            try viewContext.save()
        } catch {
            print("FolderManagementSheet save failed: \(error)")
        }
    }
}
