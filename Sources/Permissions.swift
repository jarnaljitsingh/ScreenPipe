import AppKit
import CoreGraphics

enum Permissions {
    private static let welcomeShownKey = "welcomeAlertShown"

    static func checkAtLaunch() {
        guard !UserDefaults.standard.bool(forKey: welcomeShownKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let hasAX = accessibilityTrusted(prompt: false)
            let hasScreen = CGPreflightScreenCaptureAccess()
            UserDefaults.standard.set(true, forKey: welcomeShownKey)
            if !hasAX || !hasScreen {
                showWelcomeAlert(needsAccessibility: !hasAX, needsScreen: !hasScreen)
            }
        }
    }

    @discardableResult
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestAccessibility() {
        _ = accessibilityTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    private static func showWelcomeAlert(needsAccessibility: Bool, needsScreen: Bool) {
        let alert = NSAlert()
        alert.messageText = "ScreenPipe needs a couple of permissions"
        var parts: [String] = []
        if needsScreen {
            parts.append("• Screen Recording — to capture screenshots")
        }
        if needsAccessibility {
            parts.append("• Accessibility — to paste into your terminal and send Return")
        }
        parts.append("")
        parts.append("You can grant these now or later from the menu-bar icon → “Grant Permissions…”.")
        alert.informativeText = parts.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if needsScreen { requestScreenRecording() }
            if needsAccessibility { requestAccessibility() }
        }
    }
}
