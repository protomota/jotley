import SwiftUI
import AppKit

struct SelectableSummaryTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let accentColor: NSColor
    let textColor: NSColor
    @Binding var measuredHeight: CGFloat
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = SummarySelectableTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.allowsUndo = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.autoresizingMask = [.width]

        textView.onDoubleClick = onDoubleClick
        textView.onContentHeightChange = { newHeight in
            DispatchQueue.main.async {
                if abs(measuredHeight - newHeight) > 0.5 {
                    measuredHeight = newHeight
                }
            }
        }

        applyContent(to: textView)
        textView.lastAppliedString = attributedString
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        guard let textView = nsView as? SummarySelectableTextView else { return }
        textView.onDoubleClick = onDoubleClick
        applyTheme(to: textView)

        // Fast path: `renderedSummary` upstream is memoized, so unchanged content hands
        // us the SAME instance — skip the O(n) `attributedString()` copy + compare that
        // otherwise ran on every SwiftUI graph update and surfaced as App Hanging.
        if textView.lastAppliedString === attributedString { return }
        textView.lastAppliedString = attributedString

        // Only re-typeset when the content actually changed. Theme and click-handler
        // updates don't affect height, so recalculating here would force a full text
        // layout on every SwiftUI graph update — the source of the main-thread hangs.
        if textView.attributedString() != attributedString {
            textView.textStorage?.setAttributedString(attributedString)
            textView.markContentChanged()
            textView.recalculateContentHeight()
        }
    }

    private func applyContent(to textView: SummarySelectableTextView) {
        textView.textStorage?.setAttributedString(attributedString)
        applyTheme(to: textView)
        textView.markContentChanged()
        textView.recalculateContentHeight()
    }

    private func applyTheme(to textView: SummarySelectableTextView) {
        textView.linkTextAttributes = [
            .foregroundColor: accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: accentColor.withAlphaComponent(0.3),
            .foregroundColor: textColor
        ]
    }
}

private final class SummarySelectableTextView: NSTextView {
    var onDoubleClick: (() -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    /// The last attributed-string instance applied to this view. Compared by identity
    /// (`===`) so a memoized, unchanged summary skips the O(n) re-typeset entirely.
    var lastAppliedString: NSAttributedString?
    private var lastReportedHeight: CGFloat = 0
    private var lastMeasuredWidth: CGFloat = -1
    private var contentVersion: Int = 0
    private var lastMeasuredContentVersion: Int = -1

    /// Bump when the text storage content changes so the next height recalculation
    /// knows a re-typeset is genuinely needed.
    func markContentChanged() {
        contentVersion &+= 1
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recalculateContentHeight()
    }

    override func layout() {
        super.layout()
        recalculateContentHeight()
    }

    /// Recomputes content height, but only when the width or content actually changed.
    /// `ensureLayout` triggers a full text-layout pass; calling it on every frame change
    /// and SwiftUI update (the feedback loop with `measuredHeight`) pins the main thread
    /// and can hang the app. The width/content guard limits that feedback loop
    /// to a single pass per content or width change.
    func recalculateContentHeight() {
        guard let layoutManager, let textContainer else { return }

        let width = bounds.width
        let widthUnchanged = abs(width - lastMeasuredWidth) <= 0.5
        let contentUnchanged = contentVersion == lastMeasuredContentVersion
        if widthUnchanged && contentUnchanged { return }

        lastMeasuredWidth = width
        lastMeasuredContentVersion = contentVersion

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let measured = max(
            ceil(usedRect.height + (textContainerInset.height * 2)),
            ContentLayoutConstants.standardMinHeight
        )

        if abs(lastReportedHeight - measured) > 0.5 {
            lastReportedHeight = measured
            onContentHeightChange?(measured)
        }
    }
}
