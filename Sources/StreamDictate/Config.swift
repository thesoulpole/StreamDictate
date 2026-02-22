import Foundation

enum ActivationMode: String {
    case pushToTalk = "pushToTalk"
    case toggle = "toggle"
}

struct Config {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let activationMode = "activationMode"
        static let recognitionIntervalMs = "recognitionIntervalMs"
        static let debounceRevisionMs = "debounceRevisionMs"
    }

    /// Virtual keycode for the hotkey. Default: 0x36 (Right Command).
    static var hotkeyKeyCode: UInt16 {
        get {
            let val = defaults.integer(forKey: Keys.hotkeyKeyCode)
            return val == 0 ? 0x36 : UInt16(val)
        }
        set { defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode) }
    }

    /// Push-to-talk (hold key) or toggle (press on/off).
    static var activationMode: ActivationMode {
        get {
            let raw = defaults.string(forKey: Keys.activationMode) ?? ActivationMode.pushToTalk.rawValue
            return ActivationMode(rawValue: raw) ?? .pushToTalk
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.activationMode) }
    }

    /// How often to run recognition on the accumulated buffer (ms).
    static var recognitionIntervalMs: Int {
        get {
            let val = defaults.integer(forKey: Keys.recognitionIntervalMs)
            return val == 0 ? 400 : val
        }
        set { defaults.set(newValue, forKey: Keys.recognitionIntervalMs) }
    }

    /// Debounce interval for revisions that require backspace correction (ms).
    static var debounceRevisionMs: Int {
        get {
            let val = defaults.integer(forKey: Keys.debounceRevisionMs)
            return val == 0 ? 100 : val
        }
        set { defaults.set(newValue, forKey: Keys.debounceRevisionMs) }
    }
}
