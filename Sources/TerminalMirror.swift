import AppKit

enum TerminalApp: String, CaseIterable {
    case terminal = "Terminal"
    case iterm = "iTerm2"

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        }
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}

struct TerminalWindowInfo {
    let id: Int
    let name: String
    let app: TerminalApp
}

final class TerminalMirror {
    var onUpdate: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var targetWindowID: Int?
    private(set) var targetWindowName: String?
    private(set) var targetApp: TerminalApp?

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.jarnaljit.screenpipe.terminalmirror", qos: .userInitiated)
    private var lastText = ""
    private var compiledScript: NSAppleScript?

    func setTarget(_ window: TerminalWindowInfo) {
        targetWindowID = window.id
        targetWindowName = window.name
        targetApp = window.app
        lastText = ""

        switch window.app {
        case .terminal:
            compiledScript = NSAppleScript(source: """
            tell application "Terminal"
                try
                    return contents of selected tab of (first window whose id is \(window.id))
                on error
                    return ""
                end try
            end tell
            """)
        case .iterm:
            compiledScript = NSAppleScript(source: """
            tell application "iTerm2"
                try
                    return text of current session of current tab of (first window whose id is \(window.id))
                on error
                    return ""
                end try
            end tell
            """)
        }
    }

    static func listWindows() -> [TerminalWindowInfo] {
        var results: [TerminalWindowInfo] = []
        for app in TerminalApp.allCases {
            guard app.isRunning else { continue }
            let script = NSAppleScript(source: """
            tell application "\(app.rawValue)"
                set output to ""
                repeat with w in windows
                    set output to output & (id of w as string) & "|" & (name of w) & linefeed
                end repeat
                return output
            end tell
            """)
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            guard let text = result?.stringValue else { continue }
            let windows = text.split(separator: "\n").compactMap { line -> TerminalWindowInfo? in
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, let id = Int(parts[0]) else { return nil }
                return TerminalWindowInfo(id: id, name: parts[1], app: app)
            }
            results.append(contentsOf: windows)
        }
        return results
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(300))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard let script = compiledScript else { return }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            let code = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            if code == -1743 || code == -1744 {
                let appName = targetApp?.rawValue ?? "Terminal"
                DispatchQueue.main.async { [weak self] in
                    self?.onError?("Automation permission denied. Enable in\nSystem Settings → Privacy & Security → Automation → ScreenPipe → \(appName).")
                }
                self.stop()
                return
            }
            return
        }
        let raw = result.stringValue ?? ""
        guard raw != lastText else { return }
        lastText = raw
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(raw)
        }
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = targetWindowID else { return }
        guard let pid = terminalPID() else { return }
        Log.info("send: len=\(trimmed.count) windowID=\(id)")
        raiseTargetWindowInApp()
        injectBracketedPaste(trimmed, windowID: id)
        let delay = max(0.5, Double(trimmed.count) / 2000.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.postKeyToPid(keyCode: 0x24, flags: [], pid: pid)
        }
    }

    func sendImages(urls: [URL], message: String) {
        guard let pid = terminalPID(), !urls.isEmpty else {
            if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                send(text: message)
            }
            return
        }
        raiseTargetWindowInApp()
        pasteNext(urls: urls, index: 0, pid: pid, message: message)
    }

    private func pasteNext(urls: [URL], index: Int, pid: pid_t, message: String) {
        if index >= urls.count {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let id = self.targetWindowID {
                self.injectBracketedPaste(trimmed, windowID: id)
                let delay = max(0.5, Double(trimmed.count) / 2000.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Self.postKeyToPid(keyCode: 0x24, flags: [], pid: pid)
                }
            } else {
                Self.postKeyToPid(keyCode: 0x24, flags: [], pid: pid)
            }
            return
        }

        guard let data = try? Data(contentsOf: urls[index]) else {
            pasteNext(urls: urls, index: index + 1, pid: pid, message: message)
            return
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            Self.postKeyToPid(keyCode: 0x09, flags: .maskControl, pid: pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.pasteNext(urls: urls, index: index + 1, pid: pid, message: message)
            }
        }
    }

    // MARK: - helpers

    private func terminalPID() -> pid_t? {
        guard let app = targetApp else { return nil }
        return NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == app.bundleIdentifier })?
            .processIdentifier
    }

    private func raiseTargetWindowInApp() {
        guard let id = targetWindowID, let app = targetApp else { return }
        let script = NSAppleScript(source: """
        tell application "\(app.rawValue)"
            try
                set index of (first window whose id is \(id)) to 1
            end try
        end tell
        """)
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
    }

    private func injectBracketedPaste(_ text: String, windowID: Int) {
        guard let app = targetApp else { return }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let src: String
        switch app {
        case .terminal:
            src = """
            tell application "Terminal"
                set esc to (ASCII character 27)
                do script (esc & "[200~" & "\(escaped)" & esc & "[201~") in (first window whose id is \(windowID))
            end tell
            """
        case .iterm:
            src = """
            tell application "iTerm2"
                set esc to (ASCII character 27)
                tell current session of current tab of (first window whose id is \(windowID))
                    write text (esc & "[200~" & "\(escaped)" & esc & "[201~") without newline
                end tell
            end tell
            """
        }

        let script = NSAppleScript(source: src)
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
        if let err = err {
            Log.error("injectBracketedPaste error: \(err)")
        }
    }

    private static func postKeyToPid(keyCode: UInt16, flags: CGEventFlags, pid: pid_t) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}
