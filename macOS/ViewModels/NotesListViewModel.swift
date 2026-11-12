import SwiftUI
import CoreData
import Combine
import AppKit

// Retains the existing view-facing model while all capture and inference run locally.
@MainActor final class NotesListViewModel: ObservableObject {
    let viewContext: NSManagedObjectContext
    let recorder: ProcessTapRecorder
    let summaryNotifications: JotleySummaryNotifications
    let persistenceController: SharedPersistenceController
    @Published var newNoteBeingRecorded: Note?
    @Published var isTranscriptionPaused = false
    @Published var accumulatedTranscription = ""
    @Published var selectedNoteIDs: Set<NSManagedObjectID> = []
    @Published var selectedDetailTab = DetailTab.transcript.rawValue
    @Published var showSyncError = false
    @Published var syncErrorMessage = ""
    @Published var isGeneratingSummary = false
    @Published var generatingSummaryNoteID: NSManagedObjectID?
    @Published var generatingSummaryStartedAt: Date?
    @Published var operationInProgress = false
    var pendingFolderSelection: FolderSelection = .all
    var activeRecordingNote: Note? { recorder.isRecording ? newNoteBeingRecorded : nil }
    let streamingSummaryViewModel = StreamingSummaryViewModel()
    var summaryProgress: LocalSummaryProgress { streamingSummaryViewModel.progress }
    private var subscriptions: Set<AnyCancellable> = []
    private var inference: Task<Void, Never>?
    #if DEBUG
    var simulatedSummaryGeneration: (@MainActor (@escaping @Sendable (String) async -> Void) async throws -> String)?
    var simulatedOrganization: (@MainActor (String, [LocalTagCandidate]) async throws -> LocalNoteOrganization)?
    #endif
    private var recordingLease: UUID?
    private var summaryLease: UUID?
    private var stopTask: Task<Void, Never>?
    private var isConfirmingCapture = false
    private var baseText = ""
    private var baseUtterances: [TranscriptUtterance] = []
    init(viewContext: NSManagedObjectContext, recorder: ProcessTapRecorder, persistenceController: SharedPersistenceController, summaryNotifications: JotleySummaryNotifications? = nil) {
        self.summaryNotifications = summaryNotifications ?? .shared
        self.viewContext = viewContext; self.recorder = recorder; self.persistenceController = persistenceController
        streamingSummaryViewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        // The waveform polls its meter directly. Audio-level changes must not
        // invalidate the entire sidebar, note detail and transcript bubble tree.
        let captureChanges: [AnyPublisher<Void, Never>] = [
            recorder.$recording.map { _ in () }.eraseToAnyPublisher(),
            recorder.$paused.map { _ in () }.eraseToAnyPublisher(),
            recorder.$starting.map { _ in () }.eraseToAnyPublisher(),
            recorder.$finishing.map { _ in () }.eraseToAnyPublisher(),
            recorder.$elapsed.map { _ in () }.eraseToAnyPublisher(),
            recorder.$transcription.map { _ in () }.eraseToAnyPublisher(),
            recorder.$errorMessage.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(captureChanges).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    func saveContext() {
        do { try persistenceController.save() } catch { report(error) }
    }
    func report(_ error: Error) { syncErrorMessage = error.localizedDescription; showSyncError = true }
    @discardableResult
    func createBlankNote(text: String = "", title: String = "Untitled Note") -> Note? {
        guard !recorder.isRecording, !recorder.isBusy, !operationInProgress, !LocalAppModel.shared.busy else { return nil }
        do {
            guard let note = try persistenceController.create(title: title, text: text) as? Note else {
                throw LocalError.message("Unable to create a local note.")
            }
            if case .folder(let id) = pendingFolderSelection {
                let request = Folder.fetchRequest(); request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                note.folder = try viewContext.fetch(request).first
            }
            try persistenceController.save(); LocalAppModel.shared.selected = note.id; try LocalAppModel.shared.reload(); selectedNoteIDs = [note.objectID]; selectedDetailTab = DetailTab.transcript.rawValue
            return note
        } catch { report(error); return nil }
    }
    func startNewNote() async {
        guard canStartCapture, let systemAudio = await confirmCapture(), canStartCapture else { return }
        guard let note = createBlankNote() else { return }
        await startCapture(on: note, systemAudio: systemAudio)
    }
    func resumeTranscriptionOnNote(note: Note) async {
        guard canStartCapture, let systemAudio = await confirmCapture(), canStartCapture else { return }
        await startCapture(on: note, systemAudio: systemAudio)
    }

    private var canStartCapture: Bool {
        !recorder.isRecording && !recorder.isBusy && !operationInProgress && !LocalAppModel.shared.busy && !isConfirmingCapture
    }

    private func confirmCapture() async -> Bool? {
        guard UserDefaults.standard.object(forKey: "recordSystemAudio") as? Bool ?? true else { return false }
        #if DEBUG
        if recorder.simulatedStart != nil { return true }
        #endif
        isConfirmingCapture = true
        defer { isConfirmingCapture = false }
        let alert = NSAlert()
        alert.messageText = "Before you transcribe a call"
        alert.informativeText = "Jotley doesn’t join the call or notify anyone. Tell the other participants and get their permission before transcribing. Microphone-only mode can still pick up people you hear through speakers."
        alert.addButton(withTitle: "Start with System Audio")
        alert.addButton(withTitle: "Use Microphone Only")
        let cancel = alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = ""
        cancel.keyEquivalent = "\u{1b}"
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible, window.attachedSheet == nil {
            response = await alert.beginSheetModal(for: window)
        } else {
            NSApp.activate()
            response = alert.runModal()
        }
        switch response {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    private func startCapture(on note: Note, systemAudio: Bool) async {
        operationInProgress = true; defer { operationInProgress = false }
        do {
            guard note.managedObjectContext === viewContext, !note.isDeleted else {
                throw LocalError.message("This note is unavailable.")
            }
            recordingLease = try persistenceController.beginRecording(note)
            let id = note.id ?? UUID(); note.id = id
            note.noteType = "transcription"
            try persistenceController.save()
            baseText = note.transcription ?? ""; baseUtterances = note.transcriptUtterances
            recorder.onTranscript = { [weak self] value in self?.persistLiveTranscript(value) }
            recorder.existingTranscript = baseText
            recorder.existingUtterances = baseUtterances
            JotleyAppDelegate.shared?.recordingNotesViewModel = self
            LocalAppModel.shared.selected = note.id
            newNoteBeingRecorded = note; selectedNoteIDs = [note.objectID]; selectedDetailTab = DetailTab.transcript.rawValue
            recorder.speechLocale = Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US")
            try await recorder.start(root: persistenceController.root, noteID: id, systemAudio: systemAudio)
            LocalAppModel.shared.message = ""
            isTranscriptionPaused = false
            if let message = recorder.errorMessage { syncErrorMessage = message; showSyncError = true }
        } catch {
            newNoteBeingRecorded = nil
            if let recordingLease { persistenceController.endRecording(lease: recordingLease); self.recordingLease = nil }
            if JotleyAppDelegate.shared?.recordingNotesViewModel === self { JotleyAppDelegate.shared?.recordingNotesViewModel = nil }
            report(error)
        }
    }
    private func persistLiveTranscript(_ value: LocalTranscript) {
        guard let note = newNoteBeingRecorded,
              note.managedObjectContext === viewContext, !note.isDeleted else { return }
        // Save only finalized words; tentative snapshots remain transient in the UI.
        let text = [baseText, value.text].filter { !$0.isEmpty }.joined(separator: " ")
        accumulatedTranscription = [baseText, value.displayText].filter { !$0.isEmpty }.joined(separator: " ")
        if !value.text.isEmpty {
            note.transcription = text
            let offset = recorder.transcriptTimeOffset
            note.setTranscriptUtterances(baseUtterances + value.utterances.map {
                TranscriptUtterance(text: $0.text, start: offset + $0.start, end: offset + $0.end)
            })
            saveContext()
        }
    }
    func updateNewNoteTranscription() { objectWillChange.send() }
    func resumeTranscription() async {
        guard recorder.isRecording else { return }
        defer { isTranscriptionPaused = recorder.paused }
        do { try recorder.togglePause() } catch { report(error) }
    }
    func stopRecording() async {
        if let stopTask { await stopTask.value; return }
        if let owner = JotleyAppDelegate.shared?.recordingNotesViewModel, owner !== self {
            await owner.stopRecording(); return
        }
        guard recorder.isRecording || newNoteBeingRecorded != nil else { return }
        let task = Task { @MainActor in
            operationInProgress = true
            defer {
                if let recordingLease { persistenceController.endRecording(lease: recordingLease); self.recordingLease = nil }
                if let note = newNoteBeingRecorded, selectedNoteIDs.contains(note.objectID) {
                    selectedDetailTab = DetailTab.transcript.rawValue
                }
                newNoteBeingRecorded = nil; isTranscriptionPaused = false; operationInProgress = false; stopTask = nil
                if JotleyAppDelegate.shared?.recordingNotesViewModel === self { JotleyAppDelegate.shared?.recordingNotesViewModel = nil }
            }
            _ = await recorder.stop()
            do {
                try persistenceController.save()
            } catch { report(error) }
            if let error = recorder.errorMessage { syncErrorMessage = error; showSyncError = true }
        }
        stopTask = task; await task.value
    }
    func isTranscriptLoading(for _: Note) -> Bool { false }
    func summaryLoadingStartedAt(for noteID: NSManagedObjectID) -> Date? { generatingSummaryNoteID == noteID ? generatingSummaryStartedAt : nil }
    func beginSummaryGeneration(for id: NSManagedObjectID) {
        if let summaryLease { persistenceController.endNoteOperation(lease: summaryLease) }
        summaryLease = persistenceController.beginNoteOperation(for: id)
        isGeneratingSummary = true; generatingSummaryNoteID = id; generatingSummaryStartedAt = Date()
    }
    func endSummaryGeneration(for id: NSManagedObjectID) {
        guard generatingSummaryNoteID == id else { return }
        if let summaryLease { persistenceController.endNoteOperation(lease: summaryLease); self.summaryLease = nil }
        isGeneratingSummary = false; generatingSummaryNoteID = nil; generatingSummaryStartedAt = nil
    }

    func toggleSelection(for note: Note, isCommandKeyPressed: Bool = false) {
        LocalAppModel.shared.selected = note.id
        try? LocalAppModel.shared.reload()
        NotificationCenter.default.post(name: Notification.Name("JotVibeSaveCurrentNote"), object: nil)
        if isCommandKeyPressed {
            if selectedNoteIDs.contains(note.objectID) {
                if selectedNoteIDs.count > 1 { selectedNoteIDs.remove(note.objectID) }
            }
            else { selectedNoteIDs.insert(note.objectID) }
        } else { selectedNoteIDs = [note.objectID] }
        selectedDetailTab = note.hasMeaningfulSummaryText ? DetailTab.summary.rawValue : DetailTab.transcript.rawValue
    }
    func ensureSelection(in notes: [Note]) {
        let available = notes.filter { !$0.isDeleted }
        let retained = selectedNoteIDs.intersection(Set(available.map(\.objectID)))
        if !retained.isEmpty {
            if retained != selectedNoteIDs { selectedNoteIDs = retained }
        } else if let first = available.first {
            toggleSelection(for: first)
        } else if !selectedNoteIDs.isEmpty { selectedNoteIDs = [] }
    }
    func jumpToActiveRecordingNote() { if let note = activeRecordingNote { selectedNoteIDs = [note.objectID]; selectedDetailTab = DetailTab.transcript.rawValue } }
    func performContextualDelete(for note: Note) { Task { await delete(note) } }
    private func delete(_ note: Note) async {
        guard !LocalAppModel.shared.busy, !recorder.isBusy else {
            report(LocalError.message("Cancel or finish the current operation before deleting notes.")); return
        }
        if let owner = JotleyAppDelegate.shared?.recordingNotesViewModel, owner.newNoteBeingRecorded?.objectID == note.objectID {
            await owner.stopRecording()
        } else if note == newNoteBeingRecorded { await stopRecording() }
        if generatingSummaryNoteID == note.objectID { inference?.cancel() }
        let objectID = note.objectID
        do {
            try persistenceController.deleteNote(note)
            selectedNoteIDs.remove(objectID)
            try LocalAppModel.shared.reload()
        } catch { report(error) }
    }
    func deleteSelectedNotes(fetchedNotes: FetchedResults<Note>) async {
        for note in fetchedNotes.filter({ selectedNoteIDs.contains($0.objectID) }) { await delete(note) }
    }
    func deleteNotes(inGroup group: [Note], atOffsets offsets: IndexSet) async {
        for i in offsets { await delete(group[i]) }
    }
    func generateSummary(note: Note, templateKey: String) async {
        guard !operationInProgress, !isGeneratingSummary, !recorder.isRecording, !recorder.isBusy, !LocalAppModel.shared.busy else { return }
        do { try persistenceController.requireExternalWriteAccess(to: note) }
        catch { report(error); return }
        let template: SummaryTemplateDefinition
        do { template = try SummaryTemplateStore.shared.resolve(templateKey) }
        catch { report(error); return }
        summaryNotifications.prepareForSummary()
        beginSummaryGeneration(for: note.objectID)
        streamingSummaryViewModel.summary = ""; streamingSummaryViewModel.progress = .preparing
        let source = note.transcription ?? ""
        let canFileNote = note.folder == nil
        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US")
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Finish on-device note summary")
        let task = Task { @MainActor in
            JotleyEngagement.shared.beginProcessing()
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                JotleyEngagement.shared.endProcessing()
            }
            defer { endSummaryGeneration(for: note.objectID); streamingSummaryViewModel.summary = ""; streamingSummaryViewModel.progress = .preparing }
            do {
                let update: @Sendable (String) async -> Void = { [weak self] text in
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.streamingSummaryViewModel.summary = text; if !text.isEmpty { self?.streamingSummaryViewModel.progress = .writing } }
                }
                let progress: @Sendable (LocalSummaryProgress) async -> Void = { [weak self] value in
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.streamingSummaryViewModel.progress = value }
                }
                let result: String
                #if DEBUG
                if let simulatedSummaryGeneration { result = try await simulatedSummaryGeneration(update) }
                else { result = try await LocalSummary.generate(source, template: template,
                    locale: locale, progress: progress, snapshot: update) }
                #else
                result = try await LocalSummary.generate(source, template: template,
                    locale: locale, progress: progress, snapshot: update)
                #endif
                var generatedTitle: String?
                var titleError: Error?
                if note.shouldReplaceTitleFromGeneratedSummary() {
                    streamingSummaryViewModel.progress = .finishing
                    do {
                        generatedTitle = try await LocalSummary.generateTitle(from: result, locale: locale)
                    } catch is CancellationError { throw CancellationError() }
                    catch { titleError = error }
                }
                let autoTags = LocalNoteOrganizationSettings.autoTags()
                let autoFolder = canFileNote && note.folder == nil && LocalNoteOrganizationSettings.autoFolders()
                let library = autoTags ? try persistenceController.tagLibrary() : []
                var organization: LocalNoteOrganization?
                if autoTags || autoFolder {
                    streamingSummaryViewModel.progress = .organizingTags
                    do {
                        #if DEBUG
                        if let simulatedOrganization { organization = try await simulatedOrganization(result, library) }
                        else {
                            organization = try await LocalNoteTags.generateOrganization(from: result, transcript: source,
                                library: library, locale: locale, autoTags: autoTags, autoFolder: autoFolder)
                        }
                        #else
                        organization = try await LocalNoteTags.generateOrganization(from: result, transcript: source,
                            library: library, locale: locale, autoTags: autoTags, autoFolder: autoFolder)
                        #endif
                    } catch is CancellationError { throw CancellationError() }
                    catch { organization = nil }
                }
                try Task.checkCancellation()
                guard !note.isDeleted else { return }
                guard (note.transcription ?? "") == source else {
                    throw LocalError.message("This transcript changed during generation. Your current note was preserved; generate a summary again.")
                }
                let tags = autoTags && LocalNoteOrganizationSettings.autoTags()
                    ? LocalNoteTags.completedNames(organization?.tags, transcript: source, summary: result, library: library)
                    : nil
                let folder = autoFolder && LocalNoteOrganizationSettings.autoFolders() ? organization?.folder : nil
                try persistenceController.saveNoteChanges(note, values: note.generatedSummaryValues(result, template: template.key, generatedTitle: generatedTitle),
                                                           replacingTags: tags, autoFolder: folder)
                await summaryNotifications.summarySaved(noteID: note.id)
                JotleyEngagement.shared.completedSummary(result: result)
                let warnings = [titleError.map { "Title: \($0.localizedDescription)" }].compactMap { $0 }
                if !warnings.isEmpty { report(LocalError.message("Summary saved. " + warnings.joined(separator: " "))) }
                NotificationCenter.default.post(name: Notification.Name("SummaryGenerationComplete"), object: nil,
                    userInfo: ["noteID": note.objectID, "summary": result])
            } catch is CancellationError { } catch { report(error) }
        }
        inference = task; await task.value; inference = nil
    }
    func cancelInference() { inference?.cancel() }
}
@MainActor final class StreamingSummaryViewModel: ObservableObject {
    @Published var summary = ""
    @Published var progress: LocalSummaryProgress = .preparing
    var displayedText: String { summary }
}
