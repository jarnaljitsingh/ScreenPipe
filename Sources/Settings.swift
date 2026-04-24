import AppKit
import Carbon
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func show(onHotkeysChanged: @escaping () -> Void) {
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(onHotkeysChanged: onHotkeysChanged)
        let hosting = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenPipe Settings"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

struct SettingsView: View {
    let onHotkeysChanged: () -> Void

    @State private var fullScreen: Hotkey = Preferences.fullScreenHotkey
    @State private var interactive: Hotkey = Preferences.interactiveHotkey

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Shortcuts")
                .font(.headline)

            row(
                title: "Full-screen capture",
                hotkey: $fullScreen,
                onChange: {
                    Preferences.fullScreenHotkey = fullScreen
                    onHotkeysChanged()
                }
            )

            row(
                title: "Drag-select area capture",
                hotkey: $interactive,
                onChange: {
                    Preferences.interactiveHotkey = interactive
                    onHotkeysChanged()
                }
            )

            Divider()

            HStack {
                Button("Reset to defaults") {
                    fullScreen = Preferences.defaultFullScreen
                    interactive = Preferences.defaultInteractive
                    Preferences.fullScreenHotkey = fullScreen
                    Preferences.interactiveHotkey = interactive
                    onHotkeysChanged()
                }
                Spacer()
            }

            Text("Tip: use at least one modifier (⌘⌃⌥⇧) to avoid conflicts with typing.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 460, alignment: .topLeading)
    }

    @ViewBuilder
    private func row(title: String, hotkey: Binding<Hotkey>, onChange: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .frame(width: 200, alignment: .leading)
            ShortcutRecorder(hotkey: hotkey, onChange: onChange)
                .frame(height: 26)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    let onChange: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.hotkey = hotkey
        view.onChange = { newValue in
            hotkey = newValue
            onChange()
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.applyHotkey(hotkey)
    }
}

final class ShortcutRecorderView: NSView {
    var hotkey: Hotkey = Preferences.defaultFullScreen {
        didSet { updateLabel() }
    }
    var onChange: ((Hotkey) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var recording = false {
        didSet { updateLabel() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        updateStyle()

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(startRecording))
        addGestureRecognizer(click)

        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateStyle()
    }

    @objc private func startRecording() {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func becomeFirstResponder() -> Bool {
        recording = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    func applyHotkey(_ h: Hotkey) {
        recording = false
        window?.makeFirstResponder(nil)
        hotkey = h
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if Int(event.keyCode) == kVK_Escape {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        if let new = Hotkey.from(event: event) {
            self.hotkey = new
            self.onChange?(new)
        }
        recording = false
        window?.makeFirstResponder(nil)
    }

    private func updateLabel() {
        if recording {
            label.stringValue = "Press shortcut…"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = hotkey.displayString
            label.textColor = .labelColor
        }
        updateStyle()
    }

    private func updateStyle() {
        layer?.backgroundColor = (recording
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor).cgColor
        layer?.borderColor = (recording
            ? NSColor.controlAccentColor
            : NSColor.separatorColor).cgColor
    }
}
