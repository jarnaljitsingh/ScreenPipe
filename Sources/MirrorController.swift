import AppKit

final class MirrorController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    static let maxStagedImages = 10

    private var panel: MirrorPanel?
    private var outputView: NSTextView?
    private var scrollView: NSScrollView?
    private var inputField: SmartPasteField?
    private var stagedStack: NSStackView?
    private var stagedContainer: NSView?
    private var stagedHeightConstraint: NSLayoutConstraint?
    private let mirror = TerminalMirror()

    private var stagedImageURLs: [URL] = []
    private var isAtBottom = true

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        Log.info("mirror toggle. visible=\(isVisible)")
        if isVisible { hide() } else { show() }
    }

    func show() {
        Log.info("mirror show()")
        if let panel = panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        guard let picked = pickTerminalWindow() else {
            Log.info("no window picked")
            return
        }
        mirror.setTarget(picked)

        buildPanel(title: picked.name)
        mirror.onUpdate = { [weak self] text in self?.render(text) }
        mirror.onError = { [weak self] msg in self?.showError(msg) }
        mirror.start()
    }

    func hide() {
        mirror.stop()
        panel?.orderOut(nil)
    }

    /// Called from the hotkey flow. Adds the image to the staged strip.
    func stageImage(url: URL) {
        guard stagedImageURLs.count < Self.maxStagedImages else {
            Log.info("max staged images (\(Self.maxStagedImages)) reached — discarding \(url.lastPathComponent)")
            ScreenshotService.discard(url)
            flashInputPlaceholder("Max 10 images — send first")
            return
        }
        Log.info("staging image: \(url.lastPathComponent)")
        stagedImageURLs.append(url)
        rebuildStagedStrip()

        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        if let field = inputField { panel?.makeFirstResponder(field) }
    }

    private func removeStaged(url: URL) {
        stagedImageURLs.removeAll { $0 == url }
        ScreenshotService.discard(url)
        rebuildStagedStrip()
    }

    private func clearAllStaged(discardFiles: Bool) {
        if discardFiles {
            for u in stagedImageURLs { ScreenshotService.discard(u) }
        }
        stagedImageURLs.removeAll()
        rebuildStagedStrip()
    }

    private func rebuildStagedStrip() {
        guard let stack = stagedStack else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for url in stagedImageURLs {
            let thumb = StagedThumbnailView(url: url) { [weak self] in
                self?.removeStaged(url: url)
            }
            stack.addArrangedSubview(thumb)
        }
        let hasItems = !stagedImageURLs.isEmpty
        stagedContainer?.isHidden = !hasItems
        stagedHeightConstraint?.constant = hasItems ? 64 : 0
    }

    private func flashInputPlaceholder(_ text: String) {
        guard let field = inputField else { return }
        let previous = field.placeholderString ?? ""
        field.placeholderString = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            field.placeholderString = previous
        }
    }

    // MARK: - UI

    private func pickTerminalWindow() -> TerminalWindowInfo? {
        let windows = TerminalMirror.listWindows()
        if windows.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No terminal windows found"
            alert.informativeText = "Open a Terminal or iTerm2 window running Claude Code first, then try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return nil
        }

        let alert = NSAlert()
        alert.messageText = "Which terminal window?"
        alert.informativeText = windows.count == 1
            ? "Only one terminal window is open. Click Open Panel to mirror it."
            : "Pick the terminal window to mirror."
        alert.alertStyle = .informational

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 400, height: 26))
        for (i, w) in windows.enumerated() {
            let label = w.name.isEmpty ? "Window #\(w.id)" : w.name
            popup.addItem(withTitle: "\(w.app.rawValue): \(label)")
            popup.item(at: i)?.representedObject = w.id
        }

        if let remembered = Preferences.lastMirrorWindowName,
           let idx = windows.firstIndex(where: { $0.name == remembered }) {
            popup.selectItem(at: idx)
        }

        alert.accessoryView = popup
        alert.addButton(withTitle: "Open Panel")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            let idx = popup.indexOfSelectedItem
            if idx >= 0 && idx < windows.count {
                Preferences.lastMirrorWindowName = windows[idx].name
                return windows[idx]
            }
        }
        return nil
    }

    private func buildPanel(title: String) {
        let panel = MirrorPanel(
            contentRect: NSRect(x: 120, y: 120, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = title.isEmpty ? "Claude Code" : title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.titlebarAppearsTransparent = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = container

        // Output
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.backgroundColor = NSColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        textView.textColor = NSColor(white: 0.95, alpha: 1)
        textView.insertionPointColor = NSColor(white: 0.95, alpha: 1)
        textView.drawsBackground = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        // Staged strip
        let staged = NSView()
        staged.translatesAutoresizingMaskIntoConstraints = false
        staged.wantsLayer = true
        staged.layer?.backgroundColor = NSColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1).cgColor
        staged.layer?.cornerRadius = 6
        staged.isHidden = true

        let stagedScroll = NSScrollView()
        stagedScroll.translatesAutoresizingMaskIntoConstraints = false
        stagedScroll.hasHorizontalScroller = false
        stagedScroll.hasVerticalScroller = false
        stagedScroll.horizontalScrollElasticity = .allowed
        stagedScroll.drawsBackground = false
        stagedScroll.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stagedScroll.documentView = stack

        staged.addSubview(stagedScroll)

        // Input field (supports long-paste → token collapse)
        let field = SmartPasteField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = "Type, press Enter to send"
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.target = self
        field.action = #selector(submit)

        container.addSubview(scroll)
        container.addSubview(staged)
        container.addSubview(field)

        let heightC = staged.heightAnchor.constraint(equalToConstant: 0)
        heightC.isActive = true

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: staged.topAnchor, constant: -6),

            staged.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            staged.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            staged.bottomAnchor.constraint(equalTo: field.topAnchor, constant: -6),

            stagedScroll.topAnchor.constraint(equalTo: staged.topAnchor),
            stagedScroll.leadingAnchor.constraint(equalTo: staged.leadingAnchor),
            stagedScroll.trailingAnchor.constraint(equalTo: staged.trailingAnchor),
            stagedScroll.bottomAnchor.constraint(equalTo: staged.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: stagedScroll.contentView.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: stagedScroll.contentView.centerYAnchor),
            stack.heightAnchor.constraint(equalTo: stagedScroll.contentView.heightAnchor),

            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            field.heightAnchor.constraint(equalToConstant: 28),
        ])

        self.panel = panel
        self.outputView = textView
        self.scrollView = scroll
        self.inputField = field
        self.stagedContainer = staged
        self.stagedStack = stack
        self.stagedHeightConstraint = heightC

        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    private func render(_ text: String) {
        guard let textView = outputView, let scroll = scrollView else { return }
        let doc = scroll.documentView
        let visibleMax = (doc?.frame.height ?? 0) - scroll.contentView.bounds.height
        isAtBottom = scroll.contentView.bounds.origin.y >= visibleMax - 8

        textView.string = text
        if isAtBottom {
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func showError(_ msg: String) {
        outputView?.string = msg
    }

    @objc private func submit() {
        guard let field = inputField else { return }
        let text = field.expandedStringValue()
        Log.info("submit() expanded_len=\(text.count) stagedCount=\(stagedImageURLs.count)")
        if !stagedImageURLs.isEmpty {
            mirror.sendImages(urls: stagedImageURLs, message: text)
            clearAllStaged(discardFiles: false)
        } else if !text.isEmpty {
            mirror.send(text: text)
        }
        field.stringValue = ""
        field.clearTokens()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if !stagedImageURLs.isEmpty {
                clearAllStaged(discardFiles: true)
                return true
            }
        }
        return false
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        if let field = client as? SmartPasteField {
            return field.customEditor
        }
        return nil
    }

    func windowWillClose(_ notification: Notification) {
        mirror.stop()
        panel = nil
        outputView = nil
        scrollView = nil
        inputField = nil
        stagedStack = nil
        stagedContainer = nil
        stagedImageURLs.removeAll()
    }
}

final class MirrorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Smart paste (collapse long/multi-line paste into a token)

final class SmartPasteField: NSTextField {
    fileprivate(set) var counter = 0
    fileprivate var pastedTexts: [String: String] = [:]
    fileprivate lazy var customEditor: SmartFieldEditor = {
        let ed = SmartFieldEditor()
        ed.ownerField = self
        ed.isFieldEditor = true
        ed.isRichText = false
        return ed
    }()

    /// Returns the field's string with all paste tokens replaced by the original text.
    func expandedStringValue() -> String {
        var out = stringValue
        for (token, original) in pastedTexts {
            out = out.replacingOccurrences(of: token, with: original)
        }
        return out
    }

    func clearTokens() {
        pastedTexts.removeAll()
        counter = 0
    }
}

final class SmartFieldEditor: NSTextView {
    weak var ownerField: SmartPasteField?

    override func paste(_ sender: Any?) {
        guard let owner = ownerField else { super.paste(sender); return }
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string) else { super.paste(sender); return }

        let lineCount = text.components(separatedBy: "\n").count
        let isLong = text.count > 200 || lineCount > 1
        guard isLong else { super.paste(sender); return }

        owner.counter += 1
        let token = "[Pasted text #\(owner.counter) +\(lineCount) lines]"
        owner.pastedTexts[token] = text

        if let textStorage = self.textStorage {
            textStorage.replaceCharacters(in: selectedRange(), with: token)
        } else {
            self.insertText(token, replacementRange: selectedRange())
        }
        didChangeText()
    }
}

/// A small thumbnail tile with an overlay remove button.
final class StagedThumbnailView: NSView {
    let url: URL
    let onRemove: () -> Void

    init(url: URL, onRemove: @escaping () -> Void) {
        self.url = url
        self.onRemove = onRemove
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true

        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = NSImage(contentsOf: url)
        iv.wantsLayer = true
        addSubview(iv)

        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.title = "✕"
        btn.isBordered = false
        btn.bezelStyle = .inline
        btn.font = .systemFont(ofSize: 10, weight: .bold)
        btn.contentTintColor = .white
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        btn.layer?.cornerRadius = 9
        btn.target = self
        btn.action = #selector(tappedRemove)
        addSubview(btn)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 60),
            heightAnchor.constraint(equalToConstant: 48),

            iv.topAnchor.constraint(equalTo: topAnchor),
            iv.leadingAnchor.constraint(equalTo: leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: trailingAnchor),
            iv.bottomAnchor.constraint(equalTo: bottomAnchor),

            btn.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            btn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            btn.widthAnchor.constraint(equalToConstant: 18),
            btn.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tappedRemove() {
        onRemove()
    }
}
