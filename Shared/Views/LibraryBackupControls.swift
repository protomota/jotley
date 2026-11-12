import SwiftUI
import UniformTypeIdentifiers

private struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Shared controls keep the platform's existing Settings layout and native
/// save/open sheets. No account or internet connection is needed.
struct LibraryBackupControls: View {
    @EnvironmentObject private var store: SharedPersistenceController
    @State private var document: LibraryBackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingBackup: LibraryBackup?
    @State private var message: String?

    var body: some View {
        Button("Export Backup…", systemImage: "square.and.arrow.up") { exportBackup() }
            .accessibilityIdentifier("settingsExportBackup")
        Button("Import / Restore…", systemImage: "square.and.arrow.down") { showingImporter = true }
            .accessibilityIdentifier("settingsImportBackup")
        Text("Save all notes, transcripts, summaries, folders, tags, note chats, markers and custom templates in one JSON file. Restore adds missing items and keeps existing versions. No account or internet connection is needed.")
            .font(.caption).foregroundStyle(.secondary)
        Text("Backups contain your note text. Save them somewhere private. Support conversations and sign-in credentials are not included.")
            .font(.caption).foregroundStyle(.secondary)
        if let message { Text(message).font(.callout).textSelection(.enabled).accessibilityIdentifier("settingsBackupResult") }
        Color.clear.frame(height: 0)
            .fileExporter(isPresented: $showingExporter, document: document, contentType: .json,
                defaultFilename: "Jotley Backup \(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result {
                case .success: message = "Backup saved. You can restore this file in Jotley on Mac, iPhone or iPad."
                case .failure(let error): message = "The backup was not saved: \(error.localizedDescription)"
                }
                document = nil
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= LibraryBackupService.byteLimit else { throw LocalError.message("Choose a Jotley backup smaller than 256 MB.") }
                    pendingBackup = try LibraryBackupService.decode(Data(contentsOf: url, options: .mappedIfSafe))
                } catch { message = error.localizedDescription }
            }
            .sheet(isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })) {
                if let backup = pendingBackup { restorePreview(backup) }
            }
    }

    private func exportBackup() {
        do {
            let backup = try LibraryBackupService.export(from: store, templates: .shared)
            document = LibraryBackupDocument(data: try LibraryBackupService.encode(backup))
            showingExporter = true
        } catch { message = error.localizedDescription }
    }

    private func restorePreview(_ backup: LibraryBackup) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Restore your library").font(.title2.bold())
                    Text("Backup created \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)).")
                        .foregroundStyle(.secondary)
                    Text("\(backup.noteCount) notes · \(backup.items.filter { $0.entity == "Folder" }.count) folders · \(backup.items.filter { $0.entity == "Tag" }.count) tags · \(backup.templates.count) custom templates")
                    Text("Saved note chats and markers are included. Existing notes and templates keep their current version. Folders and tags with matching names are reused. Missing items are added, and nothing is deleted. Restoring the same backup again does not duplicate its notes.")
                    Text("Restored notes will sync to your other devices if iCloud sync is enabled.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("Restore Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingBackup = nil }.jotleyDismissButtonStyle(inToolbar: true)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") {
                        do {
                            let result = try LibraryBackupService.restore(backup, to: store, templates: .shared)
                            #if os(macOS)
                            try? LocalAppModel.shared.reload()
                            #endif
                            message = "Restored \(result.notesAdded) notes and \(result.templatesAdded) templates. Kept \(result.recordsKept) existing items."
                            pendingBackup = nil
                        } catch { message = error.localizedDescription; pendingBackup = nil }
                    }.accessibilityIdentifier("confirmLibraryRestore")
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 360)
        #endif
    }
}
