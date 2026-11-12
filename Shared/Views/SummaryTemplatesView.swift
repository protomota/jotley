import SwiftUI
import CoreData

enum SummaryTemplatePresentation: String, Identifiable {
    case create, manage
    var id: String { rawValue }
}

struct SummaryTemplatesView: View {
    @ObservedObject private var catalog = SummaryTemplateStore.shared
    @State private var selectedKey: String?
    @State private var draft: TemplateDraft?
    var onUse: ((SummaryTemplateDefinition) -> Void)?

    var body: some View {
        #if os(macOS)
        ViewThatFits(in: .horizontal) {
            HSplitView {
                library.frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
                selectedEditor.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }.frame(minWidth: 700)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("Template", selection: $selectedKey) {
                        Text("Choose a template").tag(String?.none)
                        ForEach(catalog.definitions) { definition in
                            Text(definition.title).tag(Optional(definition.key))
                        }
                    }.frame(maxWidth: .infinity)
                    Button { draft = TemplateDraft() } label: { Label("New Template", systemImage: "plus") }
                        .accessibilityIdentifier("templatesNewButton")
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                Divider()
                selectedEditor
            }
        }
        .sheet(item: $draft) { value in draftEditor(value) }
        .onAppear {
            if selectedKey == nil { selectedKey = catalog.templates.first?.key ?? LocalSummaryTemplate.auto.key }
        }
        #else
        library
            .navigationTitle("Summary Templates")
            .sheet(item: $draft) { value in NavigationStack { draftEditor(value) } }
        #endif
    }
    @ViewBuilder private var selectedEditor: some View {
        if let selectedKey, let definition = try? catalog.resolve(selectedKey) {
            editor(definition).id(selectedKey)
        } else {
            ContentUnavailableView("Summary Templates", systemImage: "doc.text",
                description: Text("Create a template or duplicate a built-in template to make it your own."))
        }
    }
    private var library: some View {
        List {
            Section {
                Button { draft = TemplateDraft() } label: { Label("New Template", systemImage: "plus") }
                    .accessibilityIdentifier("templatesNewButton")
            }
            if let error = catalog.storageError { Section { Text(error).foregroundStyle(.secondary) } }
            Section("My Templates") {
                if catalog.templates.isEmpty { Text("No custom templates yet").foregroundStyle(.secondary) }
                ForEach(catalog.templates) { template in row(template.definition) }
            }
            Section("Built-in Templates") {
                ForEach(LocalSummaryTemplate.allCases) { row(.init($0)) }
            }
            Section {
                Text(catalog.syncEnabled ? "Custom templates sync with your iCloud account. Existing summaries change only when you regenerate them." : "Custom templates are saved on this device. Existing summaries change only when you regenerate them.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .tint(Color.themePrimaryAccent)
        .accessibilityIdentifier("summaryTemplatesLibrary")
    }
    @ViewBuilder private func row(_ definition: SummaryTemplateDefinition) -> some View {
        #if os(macOS)
        Button { selectedKey = definition.key } label: {
            HStack { Text(definition.title); Spacer(); if selectedKey == definition.key { Image(systemName: "checkmark").foregroundStyle(Color.themePrimaryAccent) } }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.vertical, 4).accessibilityIdentifier("templateRow-\(definition.key)")
        #else
        NavigationLink { editor(definition) } label: { Text(definition.title) }
            .accessibilityIdentifier("templateRow-\(definition.key)")
        #endif
    }
    private func editor(_ definition: SummaryTemplateDefinition) -> some View {
        SummaryTemplateEditor(draft: TemplateDraft(definition: definition, catalog: catalog), onSaved: { selectedKey = $0.key },
            onDuplicate: { draft = TemplateDraft(name: definition.title + " copy", instructions: definition.prompt) },
            onDeleted: { selectedKey = nil }, onUse: onUse)
    }
    private func draftEditor(_ value: TemplateDraft) -> some View {
        SummaryTemplateEditor(draft: value, onSaved: { record in selectedKey = record.key; draft = nil },
            onDuplicate: {}, onDeleted: {}, onUse: onUse, onCancel: { draft = nil })
            #if os(macOS)
            .frame(width: 580, height: 690)
            #endif
    }
}

/// Present creation directly from a note. A second sheet during the first
/// sheet's presentation can be dropped by SwiftUI on iPhone/iPad.
struct NewSummaryTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void = {}
    var onUse: ((SummaryTemplateDefinition) -> Void)?
    var body: some View {
        SummaryTemplateEditor(draft: TemplateDraft(), onSaved: { _ in onSaved(); dismiss() },
            onDuplicate: {}, onDeleted: {}, onUse: onUse, onCancel: { dismiss() })
    }
}

private struct TemplateDraft: Identifiable {
    let id = UUID()
    var recordID: UUID?
    var revision: String?
    var name = ""
    var instructions = ""
    var builtIn = false
    var key = "custom/preview"
    init(name: String = "", instructions: String = "") { self.name = name; self.instructions = instructions }
    @MainActor init(definition: SummaryTemplateDefinition, catalog: SummaryTemplateStore) {
        name = definition.title; instructions = definition.prompt; builtIn = !definition.isCustom
        key = definition.key
        if let record = catalog.templates.first(where: { $0.key == definition.key }) { recordID = record.id; revision = record.revision }
    }
}

private struct SummaryTemplateEditor: View {
    @ObservedObject private var catalog = SummaryTemplateStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("transcriptionLanguage") private var language = "en-US"
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]) private var notes: FetchedResults<Note>
    let draft: TemplateDraft
    let onSaved: (CustomSummaryTemplate) -> Void
    let onDuplicate: () -> Void
    let onDeleted: () -> Void
    var onUse: ((SummaryTemplateDefinition) -> Void)?
    var onCancel: (() -> Void)?
    @State private var name: String
    @State private var instructions: String
    @State private var revision: String?
    @State private var recordID: UUID?
    @State private var error: String?
    @State private var savedMessage: String?
    @State private var showDelete = false
    @State private var previewNote: UUID?
    @State private var preview = ""
    @State private var isPreviewing = false
    @State private var previewTask: Task<Void, Never>?
    @State private var previewID: UUID?

    init(draft: TemplateDraft, onSaved: @escaping (CustomSummaryTemplate) -> Void,
         onDuplicate: @escaping () -> Void, onDeleted: @escaping () -> Void,
         onUse: ((SummaryTemplateDefinition) -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.draft = draft; self.onSaved = onSaved; self.onDuplicate = onDuplicate; self.onDeleted = onDeleted
        self.onUse = onUse; self.onCancel = onCancel
        _name = State(initialValue: draft.name); _instructions = State(initialValue: draft.instructions)
        _revision = State(initialValue: draft.revision); _recordID = State(initialValue: draft.recordID)
    }
    private var eligibleNotes: [Note] { Array(notes.filter { !($0.transcription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(30)) }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= SummaryTemplateStore.nameLimit && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && instructions.utf8.count <= SummaryTemplateStore.instructionByteLimit }
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name).disabled(draft.builtIn).accessibilityIdentifier("templateNameField")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions").font(.headline)
                    TextEditor(text: $instructions).frame(minHeight: 150).disabled(draft.builtIn)
                        .accessibilityLabel("Template instructions").accessibilityIdentifier("templateInstructionsField")
                    Text("\(instructions.utf8.count) / \(SummaryTemplateStore.instructionByteLimit) bytes").font(.caption).foregroundStyle(.secondary)
                    Text("Describe the sections, focus, length and tone you want. Jotley uses only facts in the note and runs the summary on-device.").font(.footnote).foregroundStyle(.secondary)
                }
                if draft.builtIn {
                    Button("Duplicate Template", action: onDuplicate).accessibilityIdentifier("templateDuplicateButton")
                } else {
                    HStack {
                        Button("Save Template") { save(use: false) }.disabled(!valid || isPreviewing).accessibilityIdentifier("templateSaveButton")
                        if onUse != nil { Button("Save & Use") { save(use: true) }.disabled(!valid || isPreviewing) }
                    }.buttonStyle(.borderless)
                    if recordID != nil {
                        HStack {
                            Button("Duplicate") { onDuplicate() }.disabled(onCancel != nil)
                            Button("Delete Template", role: .destructive) { showDelete = true }.accessibilityIdentifier("templateDeleteButton")
                        }.buttonStyle(.borderless)
                    }
                }
                if let savedMessage { Text(savedMessage).foregroundStyle(.secondary).accessibilityIdentifier("templateSavedStatus") }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("templateError") }
            }
            Section("Try on a Note") {
                if eligibleNotes.isEmpty {
                    Text("Add a transcript to a note to preview this template.").foregroundStyle(.secondary)
                } else {
                    Picker("Note", selection: $previewNote) {
                        Text("Choose a note").tag(UUID?.none)
                        ForEach(eligibleNotes) { note in Text(note.title ?? "Untitled").tag(note.id) }
                    }.disabled(isPreviewing).accessibilityIdentifier("templatePreviewNotePicker")
                    if isPreviewing {
                        ProgressView("Generating preview…")
                        Button("Cancel Preview") { cancelPreview() }
                            .jotleyDismissButtonStyle()
                    } else {
                        Button("Preview Summary") { generatePreview() }.disabled(!valid || previewNote == nil).accessibilityIdentifier("templatePreviewButton")
                    }
                    Text("Previewing does not change the note’s saved summary.").font(.footnote).foregroundStyle(.secondary)
                    if !preview.isEmpty { StructuredSummaryView(content: preview).accessibilityIdentifier("templatePreviewResult") }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft.builtIn ? name : (recordID == nil ? "New Template" : "Edit Template"))
        .tint(Color.themePrimaryAccent)
        .toolbar {
            if let onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel).jotleyDismissButtonStyle(inToolbar: true)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .alert("Delete this template?", isPresented: $showDelete) {
            Button("Delete Template", role: .destructive) {
                guard let recordID, let revision else { return }
                do {
                    try catalog.delete(id: recordID, expectedRevision: revision); onDeleted()
                    #if os(iOS)
                    dismiss()
                    #endif
                }
                catch { self.error = error.localizedDescription }
            }.accessibilityIdentifier("templateConfirmDeleteButton")
            Button("Cancel", role: .cancel) {}
        } message: { Text("Saved notes and summaries will be kept. Choose another template to regenerate notes that used this one.") }
        .onAppear { previewNote = eligibleNotes.first?.id }
        .onChange(of: name) { _, _ in savedMessage = nil; cancelPreview() }
        .onChange(of: instructions) { _, _ in savedMessage = nil; cancelPreview() }
        .onChange(of: previewNote) { _, _ in cancelPreview() }
        .onDisappear { cancelPreview() }
    }
    private func save(use: Bool) {
        do {
            let record = try catalog.save(id: recordID, name: name, instructions: instructions, expectedRevision: revision)
            recordID = record.id; revision = record.revision; savedMessage = "Template saved. Existing summaries are unchanged."; error = nil
            onSaved(record)
            if use { onUse?(record.definition) }
        } catch { self.error = error.localizedDescription }
    }
    private func cancelPreview() { previewID = nil; previewTask?.cancel(); previewTask = nil; isPreviewing = false; preview = "" }
    private func generatePreview() {
        guard let note = eligibleNotes.first(where: { $0.id == previewNote }) else { return }
        let source = note.transcription ?? ""
        let definition = SummaryTemplateDefinition(key: draft.builtIn ? draft.key : "custom/preview", title: name, prompt: instructions)
        let locale = Locale(identifier: language)
        let identifier = UUID(); previewID = identifier
        isPreviewing = true; preview = ""; error = nil
        previewTask = Task {
            defer { if !Task.isCancelled { isPreviewing = false; previewTask = nil } }
            do {
                let result = try await LocalSummary.generate(source, template: definition, locale: locale) { value in
                    guard !Task.isCancelled else { return }
                    await MainActor.run { if previewID == identifier { preview = value } }
                }
                try Task.checkCancellation(); preview = result
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
