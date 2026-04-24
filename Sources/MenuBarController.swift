import AppKit
import CoreGraphics

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings = SettingsWindowController()
    private let mirror = MirrorController()

    private var fullScreenHotkeyID: UInt32?
    private var interactiveHotkeyID: UInt32?

    private var previousApp: NSRunningApplication?
    private var captureInProgress = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "ScreenPipe"
            )
            image?.isTemplate = true
            button.image = image
        }

        statusItem.menu = makeMenu()
        registerHotkeys()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: "Capture Full Screen", action: #selector(captureFullFromMenu), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Capture Area…", action: #selector(captureAreaFromMenu), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())

        let mirrorItem = menu.addItem(withTitle: "Show Claude Panel", action: #selector(toggleMirror), keyEquivalent: "j")
        mirrorItem.target = self

        menu.addItem(.separator())

        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let permsItem = menu.addItem(withTitle: "Grant Permissions…", action: #selector(openPermissions), keyEquivalent: "")
        permsItem.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit ScreenPipe", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        return menu
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        HotkeyManager.shared.unregisterAll()
        fullScreenHotkeyID = nil
        interactiveHotkeyID = nil

        fullScreenHotkeyID = HotkeyManager.shared.register(Preferences.fullScreenHotkey) { [weak self] in
            self?.trigger(mode: .fullScreen)
        }
        interactiveHotkeyID = HotkeyManager.shared.register(Preferences.interactiveHotkey) { [weak self] in
            self?.trigger(mode: .interactive)
        }
    }

    private func trigger(mode: ScreenshotMode) {
        Log.info("hotkey fired mode=\(mode) captureInProgress=\(captureInProgress)")
        guard !captureInProgress else {
            Log.info("ignored — capture in progress")
            return
        }
        captureInProgress = true

        let current = NSWorkspace.shared.frontmostApplication
        Log.info("frontmost app: \(current?.localizedName ?? "nil") bundleID=\(current?.bundleIdentifier ?? "nil")")
        if current?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = current
        }

        let hasScreen = CGPreflightScreenCaptureAccess()
        Log.info("screen-capture access preflight: \(hasScreen)")
        if !hasScreen {
            Log.info("requesting screen capture access explicitly (our bundle)…")
            let granted = CGRequestScreenCaptureAccess()
            Log.info("CGRequestScreenCaptureAccess returned: \(granted)")
            captureInProgress = false
            return
        }

        let hasAX = Permissions.accessibilityTrusted(prompt: false)
        Log.info("accessibility trusted: \(hasAX)")
        if !hasAX {
            Log.info("requesting accessibility explicitly…")
            _ = Permissions.accessibilityTrusted(prompt: true)
            // Keep going — screenshot still works without AX; only paste needs it
        }

        ScreenshotService.capture(mode: mode) { [weak self] url in
            guard let self = self else { return }
            guard let url = url else {
                Log.error("capture failed — no file produced")
                self.captureInProgress = false
                return
            }
            Log.info("capture saved: \(url.path)")
            self.showComposer(for: url)
        }
    }

    private func showComposer(for url: URL) {
        // Open the panel if it isn't already (picker will appear).
        if !mirror.isVisible {
            mirror.show()
        }
        if mirror.isVisible {
            mirror.stageImage(url: url)
        } else {
            // User cancelled the picker — throw the screenshot away.
            ScreenshotService.discard(url)
        }
        captureInProgress = false
    }

    // MARK: - Menu actions

    @objc private func captureFullFromMenu() {
        trigger(mode: .fullScreen)
    }

    @objc private func captureAreaFromMenu() {
        trigger(mode: .interactive)
    }

    @objc private func toggleMirror() {
        mirror.toggle()
    }

    @objc private func openSettings() {
        settings.show(onHotkeysChanged: { [weak self] in
            self?.registerHotkeys()
        })
    }

    @objc private func openPermissions() {
        Permissions.requestAccessibility()
        Permissions.requestScreenRecording()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        let full = Preferences.fullScreenHotkey.displayString
        let area = Preferences.interactiveHotkey.displayString
        if let item = menu.items.first(where: { $0.action == #selector(captureFullFromMenu) }) {
            item.title = "Capture Full Screen (\(full))"
        }
        if let item = menu.items.first(where: { $0.action == #selector(captureAreaFromMenu) }) {
            item.title = "Capture Area… (\(area))"
        }
    }
}
