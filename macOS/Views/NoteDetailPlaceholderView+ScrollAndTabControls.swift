import SwiftUI
import AppKit

extension NoteDetailPlaceholderView {

    func teardownDetailScrollTracking() {
        if let token = detailScrollObserverToken {
            NotificationCenter.default.removeObserver(token)
            detailScrollObserverToken = nil
        }

        if let token = detailScrollEndObserverToken {
            NotificationCenter.default.removeObserver(token)
            detailScrollEndObserverToken = nil
        }

        observedDetailScrollView = nil
        shouldShowScrollToLatestControl = false
    }

    func scheduleDetailScrollStateUpdate() {
        guard let scrollView = observedDetailScrollView else {
            if shouldShowScrollToLatestControl {
                shouldShowScrollToLatestControl = false
            }
            return
        }

        DispatchQueue.main.async {
            updateDetailScrollState(using: scrollView)
        }
    }

    func updateDetailScrollState(using scrollView: NSScrollView) {
        guard isRecordingThisNote, selectedTab == DetailTab.transcript.rawValue else {
            if shouldShowScrollToLatestControl {
                withAnimation(.easeInOut(duration: 0.2)) {
                    shouldShowScrollToLatestControl = false
                }
            }
            return
        }

        guard let documentView = scrollView.documentView else {
            if shouldShowScrollToLatestControl {
                shouldShowScrollToLatestControl = false
            }
            return
        }

        let contentHeight = documentView.bounds.height
        let viewportHeight = scrollView.contentView.bounds.height
        let offsetY = scrollView.contentView.bounds.origin.y

        let isScrollable = contentHeight > viewportHeight + 2
        let isAtBottom = offsetY + viewportHeight >= contentHeight - 20
        let shouldShowControl = isScrollable && !isAtBottom

        if shouldShowControl != shouldShowScrollToLatestControl {
            withAnimation(.easeInOut(duration: 0.2)) {
                shouldShowScrollToLatestControl = shouldShowControl
            }
        }
    }

    func scrollToLatestTranscription() {
        guard detailScrollProxy != nil else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            detailScrollProxy?.scrollTo(detailScrollBottomAnchorID, anchor: .bottom)
        }

        withAnimation(.easeOut(duration: 0.15)) {
            shouldShowScrollToLatestControl = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            scheduleDetailScrollStateUpdate()
        }
    }

    // Simple transcript tab button (for when not recording)
    var transcriptTabButton: some View {
        let isViewingTranscript = selectedTab == DetailTab.transcript.rawValue
        let isLoadingTranscript = viewModel.isTranscriptLoading(for: note)
        let iconColor = isViewingTranscript ? Color.white : Color.themePrimaryAccent
        let trackColor = isViewingTranscript ? Color.white.opacity(0.3) : Color.themePrimaryAccent.opacity(0.3)

        return Button {
            selectedTab = DetailTab.transcript.rawValue
        } label: {
            HStack(spacing: 8) {
                if isLoadingTranscript {
                    ZStack {
                        Circle()
                            .stroke(trackColor, lineWidth: 2)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0, to: 0.2)
                            .stroke(iconColor, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .rotationEffect(Angle(degrees: animatingTranscriptRotation))
                            .onAppear {
                                animatingTranscriptRotation = 0
                                withAnimation(Animation.linear(duration: TabLoadingAnimation.spinnerRotationDuration).repeatForever(autoreverses: false)) {
                                    animatingTranscriptRotation = 360
                                }
                            }
                            .onDisappear {
                                animatingTranscriptRotation = 0
                            }
                    }
                } else {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(iconColor)
                }
                Text("Transcript")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isViewingTranscript ? Color.themePrimaryAccent : Color.themePrimaryAccent.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .floatingTooltip("View Transcript")
        .accessibilityIdentifier("noteDetailTranscriptTab")
    }

    var jumpToRecordingTabButton: some View {
        Button {
            viewModel.jumpToActiveRecordingNote()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.themePrimaryAccent)
                Text("Transcribing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.themePrimaryAccent)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color.themePrimaryAccent.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(Color.themePrimaryAccent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .floatingTooltip("Jump to active transcription")
        .accessibilityIdentifier("noteDetailJumpToRecordingTab")
    }

}
