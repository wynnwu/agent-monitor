import SwiftUI
import Carbon.HIToolbox

/// A click-to-record control that captures a key combo (virtual keyCode + modifiers)
/// and writes it into `HotKeyPreferences`.
struct ShortcutRecorder: NSViewRepresentable {
    let prefs: HotKeyPreferences

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.display = prefs.display
        view.onCapture = { keyCode, modifiers, display in
            prefs.keyCode = keyCode
            prefs.modifiers = modifiers
            prefs.display = display
        }
        return view
    }

    func updateNSView(_ view: KeyRecorderView, context: Context) {
        if !view.recording {
            view.display = prefs.display
            view.needsDisplay = true
        }
    }
}

final class KeyRecorderView: NSView {
    var display: String = ""
    var recording = false
    var onCapture: ((UInt32, UInt32, String) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { // Esc cancels recording
            recording = false
            needsDisplay = true
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else {
            NSSound.beep() // require at least one of ⌘ ⌃ ⌥
            return
        }
        let carbon = Self.carbonModifiers(flags)
        let label = Self.modifierSymbols(flags) + Self.keyName(for: event)
        onCapture?(UInt32(event.keyCode), carbon, label)
        display = label
        recording = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(recording ? 0.16 : 0.08).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke(); path.stroke()

        let text = recording ? "Recording… (Esc cancels)" : (display.isEmpty ? "Click to record" : display)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    static func keyName(for event: NSEvent) -> String {
        if let chars = event.charactersIgnoringModifiers, let c = chars.first,
           c.isLetter || c.isNumber || c.isPunctuation || c.isSymbol {
            return chars.uppercased()
        }
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default: return "key\(event.keyCode)"
        }
    }
}
