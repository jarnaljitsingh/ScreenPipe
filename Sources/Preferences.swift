import Carbon
import Foundation

enum Preferences {
    private static let fullScreenKey = "fullScreenHotkey"
    private static let interactiveKey = "interactiveHotkey"
    private static let lastTargetBundleIDKey = "lastTargetBundleID"
    private static let lastTargetWindowTitleKey = "lastTargetWindowTitle"

    static var lastTargetBundleID: String? {
        get { UserDefaults.standard.string(forKey: lastTargetBundleIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastTargetBundleIDKey) }
    }

    static var lastTargetWindowTitle: String? {
        get { UserDefaults.standard.string(forKey: lastTargetWindowTitleKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastTargetWindowTitleKey) }
    }

    private static let lastMirrorWindowNameKey = "lastMirrorWindowName"

    static var lastMirrorWindowName: String? {
        get { UserDefaults.standard.string(forKey: lastMirrorWindowNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastMirrorWindowNameKey) }
    }

    static var fullScreenHotkey: Hotkey {
        get { load(fullScreenKey) ?? defaultFullScreen }
        set { save(newValue, key: fullScreenKey) }
    }

    static var interactiveHotkey: Hotkey {
        get { load(interactiveKey) ?? defaultInteractive }
        set { save(newValue, key: interactiveKey) }
    }

    static var defaultFullScreen: Hotkey {
        Hotkey(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: Hotkey.cmd | Hotkey.control | Hotkey.shift
        )
    }

    static var defaultInteractive: Hotkey {
        Hotkey(
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: Hotkey.cmd | Hotkey.control | Hotkey.shift
        )
    }

    private static func load(_ key: String) -> Hotkey? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    private static func save(_ hotkey: Hotkey, key: String) {
        guard let data = try? JSONEncoder().encode(hotkey) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
