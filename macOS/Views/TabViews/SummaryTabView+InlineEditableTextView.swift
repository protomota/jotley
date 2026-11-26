import SwiftUI
import AppKit

struct InlineEditableSummaryTextView: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let accentColor: NSColor
    let textColor: NSColor
    var fontSize = NSFont.systemFontSize

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
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
        // SwiftUI owns the frame. AppKit must not grow it past the field border.
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isRichText = false

        applyTheme(to: textView)

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
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let layoutManager = nsView.layoutManager, let container = nsView.textContainer else { return nil }

        // SwiftUI can probe several widths. Restore the drawing width after
        // measuring so an unused proposal cannot rewrap the visible text.
        let drawingSize = container.containerSize
        defer { container.containerSize = drawingSize }
        container.containerSize = NSSize(width: width, height: drawingSize.height)
        layoutManager.ensureLayout(for: container)
        let height = max(layoutManager.usedRect(for: container).maxY, layoutManager.extraLineFragmentRect.maxY)
        return CGSize(width: width, height: ceil(height))
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
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }
}
