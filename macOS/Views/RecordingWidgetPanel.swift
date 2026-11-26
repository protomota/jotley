import AppKit
import SwiftUI

final class RecordingWidgetPanel: NSPanel, NSWindowDelegate {
    private static let positionXKey = "recordingWidgetPositionX"
    private static let positionYKey = "recordingWidgetPositionY"

    private let windowSize = CGSize(width: 220, height: 52)

    init(viewModel: RecordingWidgetViewModel, onWidgetTapped: (() -> Void)? = nil) {

        let frame = NSRect(origin: RecordingWidgetPanel.initialOrigin(windowSize: windowSize), size: windowSize)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isMovable = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
        delegate = self

        let widgetView = RecordingWidgetView(viewModel: viewModel, onWidgetTapped: onWidgetTapped)
        let hostingView = NSHostingView(rootView: widgetView)
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        contentView = hostingView
    }

    func windowDidMove(_ notification: Notification) {
        savePosition()
    }

    private func savePosition() {
        let origin = frame.origin
        UserDefaults.standard.set(origin.x, forKey: Self.positionXKey)
        UserDefaults.standard.set(origin.y, forKey: Self.positionYKey)
    }

    private static func initialOrigin(windowSize: CGSize) -> CGPoint {
        let defaults = UserDefaults.standard
        let savedX = defaults.object(forKey: positionXKey) as? Double
        let savedY = defaults.object(forKey: positionYKey) as? Double

        if let savedX, let savedY {
            return CGPoint(x: savedX, y: savedY)
        }

        guard let screen = NSScreen.main else {
            return CGPoint(x: 20, y: 20)
        }

        let frame = screen.visibleFrame
        let x = frame.maxX - windowSize.width - 24
        let y = frame.minY + 24
        return CGPoint(x: x, y: y)
    }
}
