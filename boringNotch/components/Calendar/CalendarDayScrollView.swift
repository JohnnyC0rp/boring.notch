import AppKit
import SwiftUI

/// A frozen day gutter beside a shared two-axis timeline viewport.
struct CalendarDayScrollView<Labels: View, Content: View>: NSViewRepresentable {
    let days: [CalendarDayStackGeometry.Day]
    let targetDay: Date
    let targetX: CGFloat
    let resetID: Int
    let onScroll: (CalendarDayStackGeometry.Position, Bool) -> Void
    @ViewBuilder let labels: () -> Labels
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CalendarDayScrollContainer {
        let container = CalendarDayScrollContainer()
        let coordinator = context.coordinator
        let hosting = NSHostingView(rootView: content())
        let labelHosting = NSHostingView(rootView: labels())
        hosting.isFlipped = true
        labelHosting.isFlipped = true
        hosting.sizingOptions = []
        labelHosting.sizingOptions = []
        container.scrollView.documentView = hosting
        container.gutter.documentView = labelHosting
        coordinator.hosting = hosting
        coordinator.labelHosting = labelHosting
        container.scrollView.contentView.postsBoundsChangedNotifications = true
        coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: container.scrollView.contentView, queue: .main
        ) { [weak container, weak coordinator] _ in
            guard let container, let coordinator else { return }
            let origin = container.scrollView.contentView.bounds.origin
            container.gutter.scroll(to: NSPoint(x: 0, y: origin.y))
            let vertical = abs(origin.y - coordinator.lastOrigin.y) > 0.1
            let moved = vertical || abs(origin.x - coordinator.lastOrigin.x) > 0.1
            coordinator.lastOrigin = origin
            guard moved, !coordinator.updating,
                  let position = CalendarDayStackGeometry.position(at: origin.y, in: coordinator.days) else { return }
            coordinator.onScroll?(position, vertical)
        }
        return container
    }

    func updateNSView(_ container: CalendarDayScrollContainer, context: Context) {
        let coordinator = context.coordinator
        let origin = container.scrollView.contentView.bounds.origin
        let previousPosition = CalendarDayStackGeometry.position(at: origin.y, in: coordinator.days)
        let changedWindow = coordinator.days.first?.id != days.first?.id
        let shouldReset = coordinator.resetID != resetID
        coordinator.updating = true
        coordinator.days = days
        coordinator.resetID = resetID
        coordinator.onScroll = onScroll
        let width = (days.map { $0.interval.duration }.max() ?? 86400) / 3600 * CalendarDayStackGeometry.pointsPerHour
        let height = CalendarDayStackGeometry.documentHeight(for: days)
        coordinator.hosting?.rootView = content()
        coordinator.hosting?.frame = NSRect(x: 0, y: 0, width: width, height: height)
        coordinator.labelHosting?.rootView = labels()
        coordinator.labelHosting?.frame = NSRect(x: 0, y: 0, width: 47, height: height)
        if changedWindow || shouldReset {
            let position = shouldReset ? CalendarDayStackGeometry.Position(day: targetDay, intraDayOffset: 0)
                : previousPosition ?? .init(day: targetDay, intraDayOffset: 0)
            container.scrollView.move(to: NSPoint(x: shouldReset ? targetX : origin.x,
                                                 y: CalendarDayStackGeometry.offset(of: position, in: days)))
        }
        let updatedOrigin = container.scrollView.contentView.bounds.origin
        container.gutter.scroll(to: NSPoint(x: 0, y: updatedOrigin.y))
        coordinator.lastOrigin = updatedOrigin
        coordinator.updating = false
    }

    static func dismantleNSView(_ container: CalendarDayScrollContainer, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        coordinator.observer = nil
        coordinator.onScroll = nil
        container.scrollView.documentView = nil
        container.gutter.documentView = nil
    }

    final class Coordinator {
        var hosting: NSHostingView<Content>?
        var labelHosting: NSHostingView<Labels>?
        var days: [CalendarDayStackGeometry.Day] = []
        var resetID: Int?
        var observer: NSObjectProtocol?
        var updating = false
        var lastOrigin = NSPoint.zero
        var onScroll: ((CalendarDayStackGeometry.Position, Bool) -> Void)?
    }
}

final class CalendarDayScrollContainer: NSView {
    let scrollView = CalendarDayNativeScrollView()
    let gutter = NSClipView()
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        gutter.drawsBackground = false
        addSubview(gutter)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gutter.frame = NSRect(x: 0, y: 0, width: 47, height: bounds.height)
        scrollView.frame = NSRect(x: 55, y: 0, width: max(0, bounds.width - 55), height: bounds.height)
    }

    override func scrollWheel(with event: NSEvent) { scrollView.scrollWheel(with: event) }
}

final class CalendarDayNativeScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        // Each axis keeps its job: days travel vertically, hours horizontally.
        move(to: NSPoint(x: contentView.bounds.minX - event.scrollingDeltaX * scale,
                         y: contentView.bounds.minY - event.scrollingDeltaY * scale))
    }

    func move(to point: NSPoint) {
        let size = documentView?.frame.size ?? .zero
        let maximumX = max(0, size.width - contentView.bounds.width)
        let maximumY = max(0, size.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: min(max(0, point.x), maximumX), y: min(max(0, point.y), maximumY)))
        reflectScrolledClipView(contentView)
    }
}
