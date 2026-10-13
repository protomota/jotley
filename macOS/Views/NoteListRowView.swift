import SwiftUI
import CoreData
import AppKit

// MARK: - Note List Row View

struct NoteListRowView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var note: Note
    let isSelected: Bool
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showContextMenu = false
    @State private var contextMenuScale: CGFloat = 0.92
    @State private var contextMenuOpacity: Double = 0

    private var trimmedSummary: String {
        note.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var trimmedTranscription: String {
        note.transcription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var hasRenderedSummary: Bool {
        !trimmedSummary.isEmpty &&
            trimmedSummary != "Generating summary..." &&
            trimmedSummary != "Transcription in progress..."
    }

    private var hasUsableTranscription: Bool {
        guard !trimmedTranscription.isEmpty else { return false }

        return trimmedTranscription != "Transcribing audio..." &&
            trimmedTranscription != "Loading transcript..." &&
            trimmedTranscription != "Loading content..." &&
            trimmedTranscription != "Transcription in progress..." &&
            !trimmedTranscription.hasPrefix("Transcription failed:")
    }

    private var isGenerating: Bool {
        let summaryIsGenerating = trimmedSummary == "Generating summary..." ||
            trimmedSummary == "Transcription in progress..."
        let transcriptionIsGenerating = trimmedTranscription == "Transcribing audio..." ||
            trimmedTranscription == "Loading transcript..." ||
            trimmedTranscription == "Loading content..." ||
            trimmedTranscription == "Transcription in progress..."

        return summaryIsGenerating || transcriptionIsGenerating
    }

    @ViewBuilder
    private var statusIconView: some View {
        if isGenerating {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.themePrimaryAccent)
                .accessibilityIdentifier("noteRowGeneratingIcon")
                .help("Processing note")
        }
    }

    private var previewText: String {
        if hasRenderedSummary, let summary = note.summary {
            return summary.previewSnippet()
        } else if hasUsableTranscription, let transcription = note.transcription {
            return transcription.previewSnippet()
        }
        return ""
    }

    var body: some View {
        // Compute the preview once per body pass — it was previously evaluated twice
        // (the `!isEmpty` guard and the `Text`), doubling the per-row string work.
        let preview = previewText
        ZStack {
            // Main row content
            VStack(alignment: .leading, spacing: 2) {
                Text(note.titleOrUntitled)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.themeTextPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(note.timestampOrNow, style: hasRenderedSummary ? .time : .date)
                        .font(.system(size: 11))
                        .foregroundColor(Color.themeTextSecondary)

                    statusIconView

                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundColor(Color.themeTextSecondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.themePrimaryAccent.opacity(0.3) : (isHovering ? Color.themeAccent.opacity(0.1) : Color.themeContentBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.themePrimaryAccent : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .background(
                ReliableHoverTracker(isHovering: $isHovering)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onDisappear {
                // LazyVStack recycles rows; ensure hover state doesn't get stuck
                // when AppKit skips a mouseExited event during reorder or scroll.
                isHovering = false
            }
            .overlay(
                RightClickHandler {
                    showContextMenu = true
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        contextMenuScale = 1.0
                        contextMenuOpacity = 1.0
                    }
                }
            )

            // Context menu overlay - aligned right
            if showContextMenu {
                Color.black.opacity(0.001) // Invisible tap catcher
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        dismissContextMenu()
                    }

                HStack {
                    Spacer()
                    NoteContextMenuView(
                        onDelete: {
                            dismissContextMenu()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onDelete()
                            }
                        }
                    )
                    .scaleEffect(contextMenuScale, anchor: .trailing)
                    .opacity(contextMenuOpacity)
                    .padding(.trailing, 8)
                }
            }
        }
        .tint(Color.themePrimaryAccent)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 4))
        .listRowSeparator(.hidden)
        .onChange(of: showContextMenu) { _, newValue in
            if !newValue {
                contextMenuScale = 0.92
                contextMenuOpacity = 0
            }
        }
    }

    private func dismissContextMenu() {
        withAnimation(.easeOut(duration: 0.15)) {
            contextMenuScale = 0.92
            contextMenuOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showContextMenu = false
        }
    }
}

// MARK: - Context Menu View

struct NoteContextMenuView: View {
    let onDelete: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            onDelete()
        } label: {
            Text("Delete")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovering ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.themePrimaryAccent : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Reliable Hover Tracker
//
// SwiftUI's `.onHover` can miss `mouseExited` when rows are recycled by
// LazyVStack (scroll, reorder, CloudKit re-fetch), leaving a row visually
// "stuck" as hovered. This uses an NSTrackingArea with `.inVisibleRect` so
// macOS always recomputes tracking against the current frame, and actively
// re-checks the cursor position whenever tracking areas update.

struct ReliableHoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> HoverNSView {
        let view = HoverNSView()
        view.onHoverChange = { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
        return view
    }

    func updateNSView(_ nsView: HoverNSView, context: Context) {
        nsView.onHoverChange = { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
    }

    final class HoverNSView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let ta = trackingArea { removeTrackingArea(ta) }
            let ta = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(ta)
            trackingArea = ta

            // Reconcile with the actual cursor position — fixes the case where
            // the view just moved out from under the mouse (scroll/reorder) and
            // the system never fired mouseExited.
            if let window = self.window {
                let mouseLocWindow = window.mouseLocationOutsideOfEventStream
                let localPoint = convert(mouseLocWindow, from: nil)
                onHoverChange?(bounds.contains(localPoint))
            } else {
                onHoverChange?(false)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChange?(false)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { onHoverChange?(false) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Pass clicks through to the SwiftUI button underneath.
            return nil
        }
    }
}

// MARK: - Right Click Handler

struct RightClickHandler: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickNSView {
        let view = RightClickNSView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickNSView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    class RightClickNSView: NSView {
        var onRightClick: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            return frame.contains(point) ? self : nil
        }
    }
}
