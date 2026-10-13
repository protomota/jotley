import SwiftUI
import AppKit

struct InlineEditableSummaryTextView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let accentColor: NSColor
    let textColor: NSColor
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage(string: text)
        textStorage.addLayoutManager(layoutManager)

        let textView = SummaryInlineEditableTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = textColor
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isRichText = false

        applyTheme(to: textView)

        textView.onContentHeightChange = { newHeight in
            DispatchQueue.main.async {
                if abs(measuredHeight - newHeight) > 0.5 {
                    measuredHeight = newHeight
                }
            }
        }

        textView.recalculateContentHeight()

        if isFocused {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        guard let textView = nsView as? SummaryInlineEditableTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }

        applyTheme(to: textView)

        if isFocused {
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
        }

        textView.recalculateContentHeight()
    }

    private func applyTheme(to textView: SummaryInlineEditableTextView) {
        textView.textColor = textColor
        textView.insertionPointColor = accentColor
        textView.selectedTextAttributes = [
            .backgroundColor: accentColor.withAlphaComponent(0.3),
            .foregroundColor: textColor
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineEditableSummaryTextView

        init(parent: InlineEditableSummaryTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SummaryInlineEditableTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            textView.recalculateContentHeight()
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }
    }
}
private final class SummaryInlineEditableTextView: NSTextView {
    var onContentHeightChange: ((CGFloat) -> Void)?
    private var lastReportedHeight: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
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

    func recalculateContentHeight() {
        guard let layoutManager, let textContainer else { return }

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
