import SwiftUI

struct LiveTranscriptionView: View {
    @Binding var isPresented: Bool
    var existingNote: Note? = nil
    var isNewTranscription = false
    @EnvironmentObject var transcriptionManager: LiveTranscriptionManager
    @State var isFinishing = false
    @State private var didAttemptStart = false
    @State private var hasStartedTranscription = false
    var isResuming: Bool { existingNote != nil && !isNewTranscription }
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.4)).frame(width: 36, height: 5).padding(.top,8)
            header
            VStack(spacing: 24) {
                Spacer().frame(height: 20)
                waveformSection
                Text(transcriptionManager.transcriptionState == .listening ? "Transcribing" : transcriptionManager.transcriptionState == .paused ? "Paused" : "Ready")
                    .font(.title3).fontWeight(.medium).foregroundColor(.gray)
                    .opacity(transcriptionManager.transcriptionState == .idle && !hasStartedTranscription ? 0 : 1)
                    .accessibilityHidden(transcriptionManager.transcriptionState == .idle && !hasStartedTranscription)
                    .accessibilityIdentifier("transcriptionStatusText")
                timeDisplay
                transcriptionControls
                if transcriptionManager.busy {
                    ProgressView().accessibilityLabel(transcriptionManager.transcriptionState == .idle ? "Preparing on-device speech" : "Saving transcript")
                }
            }.padding(.horizontal,20).padding(.bottom,16)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(transcriptionManager.liveUtterances) { utterance in
                            TranscriptBubbleView(text: utterance.text,
                                timestampText: utterance.start.map { String(format: "%02d:%02d", Int($0) / 60, Int($0) % 60) },
                                allowsTextSelection: true)
                                .accessibilityIdentifier("liveTranscriptCard-\(utterance.id)")
                        }
                        Color.clear.frame(height: 1).id("liveTranscriptBottom")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .accessibilityIdentifier("liveTranscript")
                .defaultScrollAnchor(.bottom)
                .onChange(of: transcriptionManager.liveUtterances) { _, _ in
                    proxy.scrollTo("liveTranscriptBottom", anchor: .bottom)
                }
            }
            Spacer()
        }
        .background(Color.themeBackground)
        .presentationDetents([.large])
        .interactiveDismissDisabled(true)
        .task {
            guard !didAttemptStart, !isFinishing else { return }
            didAttemptStart = true
            if transcriptionManager.canStart { await transcriptionManager.startTranscription(note: existingNote) }
        }
        .alert("Transcription Needs Attention", isPresented: Binding(
            get: { transcriptionManager.errorMessage != nil && !transcriptionManager.busy },
            set: { if !$0 { Task { @MainActor in transcriptionManager.errorMessage = nil } } }
        )) {
            Button("OK", role: .cancel) { transcriptionManager.errorMessage = nil }
        } message: {
            Text(transcriptionManager.errorMessage ?? "")
        }
        .preferredColorScheme(ThemeManager.shared.effectiveColorScheme)
        .onChange(of: transcriptionManager.isTranscribing) { _, recording in
            // A Live Activity stop uses the same transcription manager from outside this
            // sheet. Close the capture page once that session has stopped.
            if recording { hasStartedTranscription = true }
            else if hasStartedTranscription, !transcriptionManager.busy, transcriptionManager.errorMessage == nil { isPresented = false }
        }
        .onAppear { transcriptionManager.captureScreenVisible = true; hasStartedTranscription = transcriptionManager.isTranscribing }
        .onDisappear { transcriptionManager.captureScreenVisible = false }
        .onChange(of: transcriptionManager.busy) { _, busy in
            if hasStartedTranscription, !busy, !transcriptionManager.isTranscribing, transcriptionManager.errorMessage == nil { isPresented = false }
        }
    }
    func finishAndClose() {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            await transcriptionManager.stopTranscription()
            isPresented = false
        }
    }
    func toggleTranscriptionPause() {
        guard !isFinishing else { return }
        switch transcriptionManager.transcriptionState {
        case .idle: Task { await transcriptionManager.startTranscription(note: existingNote) }
        case .listening: transcriptionManager.pauseTranscription()
        case .paused: Task { await transcriptionManager.resumeTranscription() }
        }
    }
}
