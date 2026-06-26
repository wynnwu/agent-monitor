import Foundation
import Observation
import Carbon.HIToolbox

/// Global-shortcut settings, persisted to UserDefaults. Default: disabled.
@MainActor
@Observable
final class HotKeyPreferences {
    var enabled: Bool { didSet { save() } }
    var keyCode: UInt32 { didSet { save() } }
    var modifiers: UInt32 { didSet { save() } }
    var display: String { didSet { save() } }

    private enum K {
        static let enabled = "hotkey.enabled"
        static let keyCode = "hotkey.keyCode"
        static let modifiers = "hotkey.modifiers"
        static let display = "hotkey.display"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: K.enabled) // default false
        keyCode = UInt32(defaults.object(forKey: K.keyCode) as? Int ?? Int(kVK_ANSI_M))
        modifiers = UInt32(defaults.object(forKey: K.modifiers) as? Int ?? Int(optionKey))
        display = defaults.string(forKey: K.display) ?? "⌥M"
    }

    private let defaults: UserDefaults

    private func save() {
        defaults.set(enabled, forKey: K.enabled)
        defaults.set(Int(keyCode), forKey: K.keyCode)
        defaults.set(Int(modifiers), forKey: K.modifiers)
        defaults.set(display, forKey: K.display)
    }
}
