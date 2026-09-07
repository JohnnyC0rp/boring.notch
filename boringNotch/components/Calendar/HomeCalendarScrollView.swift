import AppKit
import SwiftUI

/// Native wheel routing and viewport preservation for the continuous Home timeline.
struct HomeCalendarScrollView<Content: View>: NSViewRepresentable {
    let days: [HomeCalendarGeometry.Day]
    let targetDay: Date
    let targetDate: Date
    let resetID: Int
    var centerTarget = false
    var onPositioned: () -> Void = {}
    let height: CGFloat
    let onScroll: (Date) -> Void
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HomeCalendarNativeScrollView {
        let scrollView = HomeCalendarNativeScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        let hosting = NSHostingView(rootView: content())
        hosting.sizingOptions = []
        scrollView.documentView = hosting
        context.coordinator.hosting = hosting
        return scrollView
    }

    func updateNSView(_ scrollView: HomeCalendarNativeScrollView, context: Context) {
        let coordinator = context.coordinator
        let rebasedOffset = HomeCalendarGeometry.rebasedOffset(scrollView.contentView.bounds.minX, from: coordinator.days, to: days)
        let changedLayout = coordinator.days != days
        let shouldReset = coordinator.resetID != resetID
        coordinator.days = days
        coordinator.resetID = resetID
        let width = HomeCalendarGeometry.width(of: days)
        coordinator.hosting?.rootView = content()
        coordinator.hosting?.frame = NSRect(x: 0, y: 0, width: width, height: height)
        if shouldReset {
            scrollView.position(on: targetDay, near: targetDate, in: days, centered: centerTarget) {
                DispatchQueue.main.async { [weak coordinator] in
                    guard coordinator?.resetID == resetID else { return }
                    onPositioned()
                }
            }
        } else if changedLayout {
            scrollView.move(to: rebasedOffset)
        }
        scrollView.didScroll = { [weak scrollView, weak coordinator] in
            guard let scrollView, let coordinator else { return }
            let center = scrollView.contentView.bounds.midX
            if let date = HomeCalendarGeometry.date(at: center, in: coordinator.days) {
                onScroll(date)
            }
        }
    }

    static func dismantleNSView(_ scrollView: HomeCalendarNativeScrollView, coordinator: Coordinator) {
        scrollView.didScroll = nil
        scrollView.documentView = nil
        coordinator.hosting = nil
    }

    final class Coordinator {
        var hosting: NSHostingView<Content>?
        var days: [HomeCalendarGeometry.Day] = []
        var resetID: Int?
    }
}

final class HomeCalendarNativeScrollView: NSScrollView {
    var didScroll: (() -> Void)?
    private var pendingPosition: (day: Date, date: Date, days: [HomeCalendarGeometry.Day], centered: Bool, completion: (() -> Void)?)?

    override func layout() {
        super.layout()
        applyPendingPosition()
    }

    func position(on day: Date, near date: Date, in days: [HomeCalendarGeometry.Day], centered: Bool = false, completion: (() -> Void)? = nil) {
        pendingPosition = (day, date, days, centered, completion)
        needsLayout = true
        applyPendingPosition()
    }

    private func applyPendingPosition() {
        guard let request = pendingPosition, contentView.bounds.width > 0 else { return }
        pendingPosition = nil
        move(to: HomeCalendarGeometry.viewportOffset(near: request.date, on: request.day,
                                                    viewportWidth: contentView.bounds.width, in: request.days, centered: request.centered))
        request.completion?()
    }

    override func scrollWheel(with event: NSEvent) {
        pendingPosition = nil
        // One lane, one direction: a mouse wheel should not need a Shift-key secret handshake.
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let distance = delta * (event.hasPreciseScrollingDeltas ? 1 : 12)
        move(to: contentView.bounds.minX - distance)
        didScroll?()
    }

    func move(to offset: CGFloat) {
        let maximum = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
        contentView.scroll(to: NSPoint(x: min(max(0, offset), maximum), y: 0))
        reflectScrolledClipView(contentView)
    }
}
