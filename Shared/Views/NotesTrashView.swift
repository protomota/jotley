import CoreData
import SwiftUI

struct NotesTrashLink: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "trashedAt", ascending: false)],
        predicate: SharedPersistenceController.trashedNotesPredicate
    ) private var notes: FetchedResults<Note>
    @Binding var showingTrash: Bool

    var body: some View {
        Button {
            showingTrash = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .foregroundStyle(Color.themePrimaryAccent)
                Text("Trash")
                    .foregroundStyle(Color.themeTextPrimary)
                Spacer()
                if !notes.isEmpty {
                    Text(notes.count, format: .number)
                        .foregroundStyle(Color.themeTextSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.themeTextSecondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notesTrashLink")
    }
}

struct NotesTrashView: View {
    let store: SharedPersistenceController
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "trashedAt", ascending: false)],
        predicate: SharedPersistenceController.trashedNotesPredicate
    ) private var notes: FetchedResults<Note>

    private enum Deletion {
        case one(Note)
        case all([Note])
    }

    @State private var deletion: Deletion?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Trash")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .jotleyDismissButtonStyle()
                    .accessibilityIdentifier("notesTrashDone")
            }
            .padding(20)
            Divider()
            if notes.isEmpty {
                ContentUnavailableView("Trash Is Empty", systemImage: "trash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("Restore notes to put them back in your library.")
                            .font(.subheadline)
                            .foregroundStyle(Color.themeTextSecondary)
                            .padding(.bottom, 12)
                        ForEach(notes, id: \.objectID) { note in
                            trashRow(for: note)
                            Divider()
                        }
                    }
                    .padding(20)
                }
                Divider()
                Button(role: .destructive) {
                    deletion = .all(Array(notes))
                } label: {
                    Label("Empty Trash", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(JotleyGlassButtonStyle())
                .accessibilityIdentifier("notesEmptyTrash")
                .padding(16)
            }
        }
        .foregroundStyle(Color.themeTextPrimary)
        .background(Color.themeBackground)
        .presentationBackground(Color.themeBackground)
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #endif
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 320, idealHeight: 440)
        #endif
        .alert(
            isEmptyingTrash ? LocalizedStringKey("Empty Trash?") : LocalizedStringKey("Delete Note Permanently?"),
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            presenting: deletion
        ) { pending in
            Button("Cancel", role: .cancel) { deletion = nil }
            Button(role: .destructive) {
                switch pending {
                case .one(let note): perform { try store.permanentlyDeleteNotes([note]) }
                case .all(let notes): perform { try store.permanentlyDeleteNotes(notes) }
                }
                deletion = nil
            } label: {
                if case .all = pending { Text("Empty Trash") }
                else { Text("Delete Permanently") }
            }
        } message: { _ in
            Text("Permanently deleted notes can’t be restored.")
        }
        .alert("Jotley", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    private var isEmptyingTrash: Bool {
        if case .all = deletion { return true }
        return false
    }

    private func trashRow(for note: Note) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.titleOrUntitled)
                    .font(.headline)
                if let date = note.timestamp {
                    Text(date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button {
                    perform { try store.restoreNote(note) }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Button(role: .destructive) {
                    deletion = .one(note)
                } label: {
                    Label("Delete Permanently", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(JotleyGlassButtonStyle(circular: true, diameter: 36))
            .accessibilityLabel(note.titleOrUntitled)
            .accessibilityIdentifier("notesTrashActions")
        }
        .padding(.vertical, 10)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }
}
