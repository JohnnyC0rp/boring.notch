import AppKit
import SwiftUI

extension View {
    func calendarTodayShortcut(_ action: @escaping () -> Void) -> some View {
        background(CalendarTodayKeyHandler(action: action))
    }
}

/// The notch is a nonactivating panel, so its calendar needs an explicit key responder.
private struct CalendarTodayKeyHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CalendarTodayKeyView {
        CalendarTodayKeyView(action: action)
    }

    func updateNSView(_ view: CalendarTodayKeyView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: CalendarTodayKeyView, coordinator: ()) {
        view.removeMonitor()
    }
}

@MainActor
enum CalendarTodayShortcutRouting {
    static func shouldHandle(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .keyDown, event.window === window, window.isKeyWindow,
              event.charactersIgnoringModifiers?.lowercased() == "t",
              event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty else { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
        return true
    }
}

@MainActor
final class CalendarTodayKeyView: NSView {
    var action: () -> Void
    private var monitor: Any?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard let window else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window,
                  CalendarTodayShortcutRouting.shouldHandle(event, in: window) else { return event }
            if !event.isARepeat { self.action() }
            return nil
        }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, self.monitor != nil else { return }
            // Claim only this panel; the application behind it keeps its place.
            window.makeKey()
            window.makeFirstResponder(self)
        }
    }

    func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
            window?.resignKey()
        }
    }
}
