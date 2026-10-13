import AppKit
import CoreData
import Combine
import Sparkle
let kJotleyObsidianSyncFolderBookmarkDefaultsKey = "jotleyObsidianSyncFolderBookmark"
@MainActor final class JotleyAppDelegate: NSObject, NSApplicationDelegate {
    static var shared: JotleyAppDelegate?
    override init() { super.init(); Self.shared = self }
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var primaryRecordingMenuItem: NSMenuItem?
    private var recorderStateObserver: NSObjectProtocol?
    var recordingNotesViewModel: NotesListViewModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        JotleyUpdates.shared.start()
    }
    weak var activeNotesViewModel: NotesListViewModel?
    func bringMainWindowToFrontAndEnsureSingle() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NotificationCenter.default.post(name: Notification.Name("JotleyForceAllEditorsSave"), object: nil)
        Task { @MainActor in
            await (recordingNotesViewModel ?? activeNotesViewModel)?.stopRecording()
            do { try LocalAppModel.shared.store?.save(); sender.reply(toApplicationShouldTerminate: true) }
            catch { sender.reply(toApplicationShouldTerminate: false) }
        }
        return .terminateLater
    }

    func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = statusItemImage()
            button.toolTip = "Jotley Quick Record"
            button.target = self
            button.action = #selector(handleStatusItemButtonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()

        let primaryRecordingItem = NSMenuItem(title: "Quick Record", action: #selector(handlePrimaryRecordingActionFromStatusItem), keyEquivalent: "")
        primaryRecordingItem.target = self
        menu.addItem(primaryRecordingItem)
        primaryRecordingMenuItem = primaryRecordingItem

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Jotley", action: #selector(handleOpenFromStatusItem), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Jotley", action: #selector(handleQuitFromStatusItem), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
        self.statusItem = statusItem
        setupRecorderStateObserver()
        refreshStatusItemState()
    }

    func setupRecorderStateObserver() {
        if let recorderStateObserver {
            NotificationCenter.default.removeObserver(recorderStateObserver)
        }

        recorderStateObserver = NotificationCenter.default.addObserver(
            forName: .processTapRecordingStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatusItemState()
        }
    }

    @objc func handleStatusItemButtonClick(_ sender: NSStatusBarButton) {
        refreshStatusItemState()
        guard let statusItem else { return }

        if let menu = statusMenu {
            statusItem.popUpMenu(menu)
        } else {
            handlePrimaryRecordingActionFromStatusItem()
        }
    }

    @objc func handlePrimaryRecordingActionFromStatusItem() {
        if LocalAppModel.shared.recorder.isRecording {
            Task { @MainActor in
                await (recordingNotesViewModel ?? activeNotesViewModel)?.stopRecording()
                refreshStatusItemState()
            }
        } else {
            handleQuickRecordFromStatusItem()
            refreshStatusItemState()
        }
    }

    @objc func handleQuickRecordFromStatusItem() {
        // Call the single recording coordinator directly. (Previously this posted
        // a process-wide `.createNewNoteFromMeeting` broadcast that every live
        // NotesListViewModel handled, starting one stream each.)
        bringMainWindowToFrontAndEnsureSingle()
        Task { await activeNotesViewModel?.startNewNote() }
    }

    @objc func handleOpenFromStatusItem() {
        bringMainWindowToFrontAndEnsureSingle()
    }

    @objc func handleQuitFromStatusItem() {
        NSApp.terminate(nil)
    }

    func refreshStatusItemState() {
        let isRecording = LocalAppModel.shared.recorder.isRecording
        primaryRecordingMenuItem?.title = isRecording ? "Stop Recording" : "Quick Record"

        guard let button = statusItem?.button else { return }
        // Keep the Jotley brand mark in the menu bar at all times. It used to morph
        // into a generic "stop" glyph while recording, which read as a bug. Stopping
        // is still available via the menu's "Stop Recording" item and the in-app
        // controls; the menu-bar icon stays consistent.
        button.image = statusItemImage()
        button.toolTip = isRecording ? "Jotley — Recording (open menu to stop)" : "Jotley Quick Record"
    }

    /// The menu-bar icon: the Jotley brand mark, template-rendered so it adapts to
    /// light/dark menu bars. Falls back to the SF Symbol if the asset is missing.
    private func statusItemImage() -> NSImage? {
        if let brand = NSImage(named: "jotley-toolbar-icon") {
            brand.isTemplate = true
            brand.size = NSSize(width: 18, height: 18)
            return brand
        }

        let fallback = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Jotley Quick Record")
        fallback?.isTemplate = true
        return fallback
    }

}

// Sparkle is enabled by the direct-download release configuration, not by
// unsigned source builds or App Store variants. No note/audio content is sent.
@MainActor final class JotleyUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = JotleyUpdates()
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private var postponedInstall: (() -> Void)?
    private var installTimer: Timer?
    var isEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "JotleyEnableSparkle") as? Bool == true }
    static func allowsUpdate(recording: Bool, recorderBusy: Bool, processing: Bool) -> Bool {
        !recording && !recorderBusy && !processing
    }
    var isIdle: Bool {
        Self.allowsUpdate(recording: LocalAppModel.shared.recorder.recording,
                          recorderBusy: LocalAppModel.shared.recorder.isBusy,
                          processing: LocalAppModel.shared.busy || JotleyEngagement.shared.processingCount > 0)
    }
    func start() {
        guard isEnabled, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.automaticChecks = updater.automaticallyChecksForUpdates }
            }
        ]
        controller.startUpdater()
    }
    func check() { guard isIdle else { return }; controller?.updater.checkForUpdates() }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard isIdle else { throw LocalError.message("Finish recording or processing your note before checking for updates.") }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !isIdle else { return false }
        postponedInstall = installHandler
        installTimer?.invalidate()
        installTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isIdle else { return }
                self.installTimer?.invalidate(); self.installTimer = nil
                let install = self.postponedInstall; self.postponedInstall = nil
                install?()
            }
        }
        return true
    }
}
