import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {
    var contentWithAlerts: some View {
        contentWithAlertsBase
        .sheet(isPresented: $showingTranscriptEditor) {
            LocalMacTranscriptEditor(note: note, viewModel: viewModel)
                .environmentObject(persistenceController)
        }
        .sheet(isPresented: $showingAskAI) {
            LocalMacAskNoteView(note: note).environmentObject(persistenceController)
        }
        .safeAreaInset(edge: .bottom) {
            if isGeneratingThisSummary {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.summaryProgress.title).font(.system(size: 15, weight: .semibold))
                            if let detail = viewModel.summaryProgress.detail {
                                Text(detail).font(.system(size: 13)).foregroundColor(.themeTextSecondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("noteDetailSummaryProgress")
                    if let fraction = viewModel.summaryProgress.fraction {
                        ProgressView(value: fraction).tint(.themePrimaryAccent)
                    }
                    Button { viewModel.cancelInference() } label: {
                        Label("Cancel Generation", systemImage: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal,20).frame(minWidth: 220, minHeight: 44)
                            .background(Capsule().fill(Color.themePrimaryAccent))
                    }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("noteDetailCancelGenerationButton")
                        .frame(maxWidth: .infinity)
                }.frame(maxWidth: 480).padding(12).frame(maxWidth: .infinity).background(Color.themeBackground)
            }
        }
        .onAppear(perform: handleOnAppear)
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: Notification.Name("JotVibeSaveCurrentNote"), object: nil)
            // Clean up timers
            summarySaveTimer?.invalidate()
            summarySaveTimer = nil
            transcriptSaveTimer?.invalidate()
            transcriptSaveTimer = nil
            // Only flush when the user was actively editing — an unconditional
            // save here can race the SwiftUI binding update for editable*
            // and overwrite real content with an empty @State buffer.
            if isSummaryEditorFocused {
                saveSummaryChanges()
            }
            if isTranscriptEditorFocused {
                saveTranscriptChanges()
            }
        }
        .onChange(of: viewModel.isTranscriptionPaused, handleTranscriptionPausedChanged)
        .onChange(of: viewModel.recorder.isRecording, handleRecordingChanged)
        .onChange(of: isTranscriptEditorFocused, handleTranscriptFocusChanged)
        .onChange(of: note.objectID, handleNoteChanged)
        .onChange(of: selectedTab, handleTabChanged)
        .onChange(of: note.summary, handleSummaryChanged)
        .onChange(of: note.title, handleTitleChanged)
        .onChange(of: note.transcription) { oldValue, newValue in
            guard !isTranscriptEditorFocused else { return }

            // Guard against a CloudKit store-trump merge echoing the import-time
            // "Loading transcript..." sentinel back over a real transcript while
            // the auto-summary is still running. When that happens for THIS note
            // (owner id matches) and we still hold real content, refuse the
            // downgrade and re-assert the real transcript so Core Data — and the
            // next CloudKit export — converge back to the truth. Without this the
            // transcript tab snaps back to the import spinner and the real
            // transcript is lost: the reported transcript persistence regression.
            if Note.isTranscriptionLoadingPlaceholder(newValue),
               editableTranscriptNoteID == note.objectID,
               !Note.isTranscriptionLoadingPlaceholder(editableTranscript),
               !editableTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                let realTranscript = editableTranscript
                if note.transcription != realTranscript {
                    note.transcription = realTranscript
                    if note.transcriptUtterances.isEmpty {
                        note.setTranscriptUtterances(TranscriptUtterance.fallbackUtterances(from: realTranscript))
                    }
                    do {
                        try persistenceController.save()
                    } catch {

                    }
                }
                return
            }

            // If viewing raw transcript or cleaned is not preferred/available, update editableTranscript.
            editableTranscript = newValue ?? ""
            editableTranscriptNoteID = note.objectID

        }
        .onChange(of: isSummaryEditorFocused, handleSummaryFocusChanged)
        .onChange(of: editableSummary) { oldValue, newValue in
            if oldValue != newValue {

                scheduleSummarySave()
            }
        }
        .onChange(of: editableTranscript) { oldValue, newValue in
            if oldValue != newValue {

                scheduleTranscriptSave()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // When window loses focus, save any pending changes
            if isSummaryEditorFocused {

                saveSummaryChanges()
            }
            if isTranscriptEditorFocused {

                saveTranscriptChanges()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NoteTagsUpdated"))) { notification in
            // Refresh tags when they are updated asynchronously.
            if let userInfo = notification.userInfo,
               let noteID = userInfo["noteID"] as? NSManagedObjectID,
               noteID == note.objectID {

                currentTags = note.tagNames
                viewRefreshID = UUID() // Force view refresh
            }
        }
    }

    var contentWithAlertsBase: some View {
        bodyContentView
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.themeContentBackground.ignoresSafeArea())
        .coordinateSpace(name: "contentView")

        .overlay {
            ZStack(alignment: .topLeading) {

                if showActionsPopover {
                    CustomMoreMenuOverlay(
                        isPresented: $showActionsPopover,
                        content: actionPopoverContentView
                    )
                }
            }
        }
        .alert(obsidianAlertTitle, isPresented: $showObsidianSaveAlert) {
            Button("OK", role: .cancel) {}
                .frame(minWidth: 70)
        } message: {
            Text(obsidianAlertMessage)
        }

    }
}
