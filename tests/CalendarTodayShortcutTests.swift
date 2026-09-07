import AppKit

@MainActor
private final class TestPanel: NSPanel {
    var keyForTest = true
    override var isKeyWindow: Bool { keyForTest }
    override func makeKey() {}
    override func resignKey() {}
}

@main
struct CalendarTodayShortcutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let panel = TestPanel(contentRect: .init(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let other = TestPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        var checks = 0
        func event(_ text: String = "t", flags: NSEvent.ModifierFlags = [], window: NSWindow? = nil,
                   type: NSEvent.EventType = .keyDown) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: (window ?? panel).windowNumber, context: nil,
                             characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 17)!
        }
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        expect(CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "Plain T returns to today")
        expect(CalendarTodayShortcutRouting.shouldHandle(event("T", flags: .shift), in: panel), "Uppercase T is supported")
        expect(CalendarTodayShortcutRouting.shouldHandle(event("T", flags: .capsLock), in: panel), "Caps Lock does not change the shortcut")
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .function, [.command, .shift]] {
            expect(!CalendarTodayShortcutRouting.shouldHandle(event(flags: flags), in: panel), "Modified shortcuts keep their original actions")
        }
        expect(!CalendarTodayShortcutRouting.shouldHandle(event("x"), in: panel), "Other letters are unaffected")
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(type: .keyUp), in: panel), "Key up does not repeat the action")
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(window: other), in: panel), "Other windows are unaffected")
        panel.keyForTest = false
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "A background calendar does not capture typing")
        panel.keyForTest = true
        let editor = NSTextView(frame: .init(x: 0, y: 0, width: 100, height: 50))
        panel.contentView?.addSubview(editor)
        editor.isEditable = true
        panel.makeFirstResponder(editor)
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "Typing T in editable text is preserved")
        editor.isEditable = false
        expect(CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "Selectable event details still allow Today")
        print("PASS \(checks) scoped calendar Today shortcut checks")
    }
}
