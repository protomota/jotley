import SwiftUI

struct LiveTranscriptionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    var existingNote: Note? = nil
    var isNewTranscription = false
    // Present the same session manager explicitly for new and continued
    // transcription, without relying on sheet environment inheritance.
    @ObservedObject var transcriptionManager: LiveTranscriptionManager
    @State var isFinishing = false
    @State private var didAttemptStart = false
    @State private(set) var hasStartedTranscription = false
    var isResuming: Bool { existingNote != nil && !isNewTranscription }
    private var transcriptFadeHeight: CGFloat {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return 64 }
        return colorScheme == .light ? 104 : 84
    }
    var body: some View {
        GeometryReader { geometry in
        let compactControls = geometry.size.height < 740
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.4)).frame(width: 36, height: 5).padding(.top,8)
            header
            VStack(spacing: compactControls ? 8 : 12) {
                waveformSection.frame(height: compactControls ? 44 : 56)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        recordingReadout.fixedSize(horizontal: true, vertical: false)
                        transcriptionControls.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(spacing: 8) {
                        recordingReadout
                        transcriptionControls
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if transcriptionManager.busy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(transcriptionManager.transcriptionState == .idle ? "Preparing on-device speech" : "Saving transcript")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(transcriptionManager.liveUtterances) { utterance in
                            TranscriptBubbleView(text: utterance.text,
                                timestampText: utterance.timestampLabel,
                                allowsTextSelection: true)
                                .accessibilityIdentifier("liveTranscriptCard-\(utterance.id)")
                        }
                        Color.clear.frame(height: 1).id("liveTranscriptBottom")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .accessibilityIdentifier("liveTranscript")
                .defaultScrollAnchor(.bottom)
                // Fill from the top until the cards outgrow the viewport, then
                // keep the latest words visible at the bottom as before.
                .defaultScrollAnchor(.topLeading, for: .alignment)
                .modifier(JotleyTranscriptEdgeFade(background: .themeBackground, topFadeHeight: transcriptFadeHeight))
                .onChange(of: transcriptionManager.liveUtterances) { _, _ in
                    proxy.scrollTo("liveTranscriptBottom", anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
