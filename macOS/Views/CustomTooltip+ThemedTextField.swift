import SwiftUI
import AppKit

// MARK: - Custom Themed TextField

// Center single-line text within larger controls without changing note-title layout.
final class ThemedTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawing = super.drawingRect(forBounds: rect)
        if usesSingleLineMode {
            let activeFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let height = min(drawing.height, ceil(activeFont.ascender - activeFont.descender + activeFont.leading))
            drawing.origin.y += (drawing.height - height) / 2
            drawing.size.height = height
        }
        return drawing
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

// Custom NSTextField that properly sets cursor color
class ThemedNSTextField: NSTextField {
    var cursorColor: NSColor = .controlAccentColor
    var minimumHeight: CGFloat = 0
    var maxDisplayLines: Int = 1 {
        didSet {
            configureLineWrapping()
            invalidateIntrinsicContentSize()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            updateFieldEditorColors()
        }
        return result
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func layout() {
        super.layout()

        guard maxDisplayLines > 1 else { return }
        let width = bounds.width
        if width > 0, abs(preferredMaxLayoutWidth - width) > 0.5 {
            preferredMaxLayoutWidth = width
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        guard maxDisplayLines > 1 else {
            size.height = max(size.height, minimumHeight)
            return size
        }

        let activeFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = ceil(activeFont.ascender - activeFont.descender + activeFont.leading)
        let maxHeight = lineHeight * CGFloat(maxDisplayLines)
        let textToMeasure = (stringValue.isEmpty ? (placeholderString ?? "") : stringValue) as NSString
        let measuredWidth = bounds.width > 0 ? bounds.width : 800
        let measuredRect = textToMeasure.boundingRect(
            with: NSSize(width: measuredWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: activeFont]
        )
        let measuredHeight = max(lineHeight, ceil(measuredRect.height))

        size.height = min(measuredHeight, maxHeight) + 2
        return size
    }

    func updateFieldEditorColors() {
        if let fieldEditor = self.currentEditor() as? NSTextView {
            fieldEditor.insertionPointColor = cursorColor
            fieldEditor.selectedTextAttributes = [
                .backgroundColor: cursorColor.withAlphaComponent(0.3),
                .foregroundColor: NSColor.white
            ]
        }
    }

    func configureLineWrapping() {
        let lines = max(1, maxDisplayLines)
        let isMultiline = lines > 1
        maximumNumberOfLines = lines

        if let cell = cell as? NSTextFieldCell {
            cell.usesSingleLineMode = !isMultiline
            cell.wraps = isMultiline
            cell.isScrollable = !isMultiline
            cell.lineBreakMode = isMultiline ? .byWordWrapping : .byTruncatingTail
            cell.truncatesLastVisibleLine = isMultiline
        }

        lineBreakMode = isMultiline ? .byWordWrapping : .byTruncatingTail
    }
}

// SwiftUI wrapper for themed text field
struct ThemedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont?
    var textColor: NSColor?
    var onCommit: (() -> Void)?
    var maxLines: Int = 1
    var minimumHeight: CGFloat = 0

    @ObservedObject private var themeManager = ThemeManager.shared

    func makeNSView(context: Context) -> ThemedNSTextField {
        let textField = ThemedNSTextField()
        if minimumHeight > 0 {
            textField.cell = ThemedTextFieldCell(textCell: "")
            textField.isEditable = true
            textField.isSelectable = true
        }
        textField.minimumHeight = minimumHeight
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.stringValue = text

        if let font = font {
            textField.font = font
        }
        if let textColor = textColor {
            textField.textColor = textColor
        }

        // Set cursor color
        textField.cursorColor = NSColor(themeManager.currentThemeColor.color)
        textField.maxDisplayLines = max(1, maxLines)
        textField.configureLineWrapping()

        return textField
    }

    func updateNSView(_ nsView: ThemedNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.minimumHeight = minimumHeight
        nsView.placeholderString = placeholder
        nsView.cursorColor = NSColor(themeManager.currentThemeColor.color)

        if let font = font {
            nsView.font = font
        }
        if let textColor = textColor {
            nsView.textColor = textColor
        }
        nsView.maxDisplayLines = max(1, maxLines)
        nsView.configureLineWrapping()

        // Update colors if currently editing
        if nsView.currentEditor() != nil {
            nsView.updateFieldEditorColors()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ThemedTextField
        // Suppress the end-editing onCommit when Enter already fired one.
        // resignFirstResponder triggers controlTextDidEndEditing, so without
        // this flag text fields can receive two onCommit calls
        // for a single Return press and create duplicate notes.
        private var didFireOnCommitFromReturnKey = false

        init(_ parent: ThemedTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
            if let themedField = textField as? ThemedNSTextField {
                themedField.invalidateIntrinsicContentSize()
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let textField = obj.object as? ThemedNSTextField else { return }
            textField.updateFieldEditorColors()
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if didFireOnCommitFromReturnKey {
                didFireOnCommitFromReturnKey = false
                return
            }
            parent.onCommit?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                didFireOnCommitFromReturnKey = true
                parent.onCommit?()
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}
