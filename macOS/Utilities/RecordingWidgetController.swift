import Foundation
import AppKit

@MainActor
final class RecordingWidgetController {
    static let widgetEnabledDefaultsKey = "showRecordingWidget"

    private var panel: RecordingWidgetPanel?
    private var viewModel: RecordingWidgetViewModel?
    private weak var recorder: ProcessTapRecorder?
    private var monitorTimer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var wasWidgetVisible = false
    private var onWidgetTapped: (() -> Void)?

    func startMonitoring(recorder: ProcessTapRecorder, onWidgetTapped: (() -> Void)? = nil) {
        self.onWidgetTapped = onWidgetTapped
        self.recorder = recorder
        stopMonitoring()
        observeSettingsChanges()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncRecordingState()
            }
        }
        syncRecordingState()
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        settingsObserver = nil
        wasWidgetVisible = false
        hidePanel()
    }

    private func syncRecordingState() {
        guard let recorder else { return }
        let isEnabled = UserDefaults.standard.object(forKey: Self.widgetEnabledDefaultsKey) as? Bool ?? true
        let shouldShowWidget = isEnabled && recorder.isRecording

        if shouldShowWidget != wasWidgetVisible {
            wasWidgetVisible = shouldShowWidget
            if shouldShowWidget {
                showPanel(recorder: recorder)
            } else {
                hidePanel()
            }
        }
    }

    private func showPanel(recorder: ProcessTapRecorder) {
        if panel == nil {
            let viewModel = RecordingWidgetViewModel(recorder: recorder)
            self.viewModel = viewModel
            let panel = RecordingWidgetPanel(
                viewModel: viewModel,
                onWidgetTapped: onWidgetTapped
            )
            self.panel = panel
            viewModel.start()
            panel.orderFrontRegardless()
        }
    }

    private func hidePanel() {
        viewModel?.stop()
        viewModel = nil
        panel?.close()
        panel = nil
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncRecordingState()
            }
        }
    }
}

import Foundation
