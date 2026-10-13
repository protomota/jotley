import SwiftUI
import CoreData
import Combine

// Retains the existing view-facing model while all capture and inference run locally.
@MainActor final class NotesListViewModel: ObservableObject {
    let viewContext: NSManagedObjectContext
    let recorder: ProcessTapRecorder
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
    #endif
    private var recordingLease: UUID?
    private var stopTask: Task<Void, Never>?
    private var baseText = ""
    private var baseUtterances: [TranscriptUtterance] = []
    init(viewContext: NSManagedObjectContext, recorder: ProcessTapRecorder, persistenceController: SharedPersistenceController) {
        self.viewContext = viewContext; self.recorder = recorder; self.persistenceController = persistenceController
        streamingSummaryViewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        recorder.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
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
        guard !recorder.isRecording, !recorder.isBusy, !operationInProgress, !LocalAppModel.shared.busy else { return }
        guard let note = createBlankNote() else { return }
        await resumeTranscriptionOnNote(note: note)
    }
    func resumeTranscriptionOnNote(note: Note) async {
        guard !recorder.isRecording, !recorder.isBusy, !operationInProgress, !LocalAppModel.shared.busy else { return }
        operationInProgress = true; defer { operationInProgress = false }
        do {
            guard note.managedObjectContext === viewContext, !note.isDeleted else {
                throw LocalError.message("This note is unavailable.")
            }
            recordingLease = try persistenceController.beginRecording(note)
            let id = note.id ?? UUID(); note.id = id
            note.sourceURL = "Recordings/\(id.uuidString)"
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
            let system = UserDefaults.standard.object(forKey: "recordSystemAudio") as? Bool ?? true
            try await recorder.start(root: persistenceController.root, noteID: id, systemAudio: system)
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
                newNoteBeingRecorded = nil; isTranscriptionPaused = false; operationInProgress = false; stopTask = nil
                if JotleyAppDelegate.shared?.recordingNotesViewModel === self { JotleyAppDelegate.shared?.recordingNotesViewModel = nil }
            }
            _ = await recorder.stop()
            do {
                try persistenceController.save()
            } catch { report(error) }
            if let error = recorder.errorMessage, !recorder.hasOnlySpeechWarning { syncErrorMessage = error; showSyncError = true }
        }
        stopTask = task; await task.value
    }
    func isTranscriptLoading(for _: Note) -> Bool { false }
    func summaryLoadingStartedAt(for noteID: NSManagedObjectID) -> Date? { generatingSummaryNoteID == noteID ? generatingSummaryStartedAt : nil }
    func beginSummaryGeneration(for id: NSManagedObjectID) { isGeneratingSummary = true; generatingSummaryNoteID = id; generatingSummaryStartedAt = Date() }
    func endSummaryGeneration(for id: NSManagedObjectID) { if generatingSummaryNoteID == id { isGeneratingSummary = false; generatingSummaryNoteID = nil; generatingSummaryStartedAt = nil } }
    func retrySavedAudio(note: Note) {
        guard !recorder.isRecording, !recorder.isBusy, !isGeneratingSummary, !operationInProgress else { return }
        LocalAppModel.shared.selected = note.id; LocalAppModel.shared.transcribe()
    }

    func toggleSelection(for note: Note, isCommandKeyPressed: Bool = false) {
        LocalAppModel.shared.selected = note.id
        try? LocalAppModel.shared.reload()
        NotificationCenter.default.post(name: Notification.Name("JotVibeSaveCurrentNote"), object: nil)
        if isCommandKeyPressed {
            if selectedNoteIDs.contains(note.objectID) { selectedNoteIDs.remove(note.objectID) }
            else { selectedNoteIDs.insert(note.objectID) }
        } else { selectedNoteIDs = [note.objectID] }
        selectedDetailTab = note.hasMeaningfulSummaryText ? DetailTab.summary.rawValue : DetailTab.transcript.rawValue
    }
    func clearSelection() { selectedNoteIDs.removeAll() }
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
            try persistenceController.deleteNoteAndAudio(note)
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
        isGeneratingSummary = true; generatingSummaryNoteID = note.objectID; generatingSummaryStartedAt = Date()
        streamingSummaryViewModel.summary = ""; streamingSummaryViewModel.progress = .preparing
        let template = LocalSummaryTemplate.resolve(templateKey)
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Finish on-device note summary")
        let task = Task { @MainActor in
            JotleyEngagement.shared.beginProcessing()
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                JotleyEngagement.shared.endProcessing()
            }
            defer { isGeneratingSummary = false; generatingSummaryNoteID = nil; generatingSummaryStartedAt = nil; streamingSummaryViewModel.summary = ""; streamingSummaryViewModel.progress = .preparing }
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
                else { result = try await LocalSummary.generate(note.transcription ?? "", template: template,
                    locale: Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US"), progress: progress, snapshot: update) }
                #else
                result = try await LocalSummary.generate(note.transcription ?? "", template: template,
                    locale: Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US"), progress: progress, snapshot: update)
                #endif
                var generatedTitle: String?
                var titleError: Error?
                if note.shouldReplaceTitleFromGeneratedSummary() {
                    streamingSummaryViewModel.progress = .finishing
                    do {
                        generatedTitle = try await LocalSummary.generateTitle(from: result,
                            locale: Locale(identifier: UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "en-US"))
                    } catch is CancellationError { throw CancellationError() }
                    catch { titleError = error }
                }
                try Task.checkCancellation(); guard !note.isDeleted else { return }
                try persistenceController.saveNoteChanges(note,
                    values: note.generatedSummaryValues(result, template: template.key, generatedTitle: generatedTitle))
                JotleyEngagement.shared.completedSummary(result: result)
                if let titleError { report(LocalError.message("Summary saved, but the title could not be generated: \(titleError.localizedDescription)")) }
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
