import Defaults
import SwiftUI

/// A stationary thumbwheel; dragging changes time spacing without resizing the control.
struct CalendarScaleControl: View {
    @Default(.calendarTimelineScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false
    @State private var dragOrigin: Double?
    @State private var isHovered = false

    private var percentage: Int {
        Int((CalendarTimelineScale.clamped(scale) * 100).rounded())
    }

    var body: some View {
        Canvas { context, size in
            let phase = reduceMotion ? 0 : (CalendarTimelineScale.clamped(scale) * 40).truncatingRemainder(dividingBy: 5)
            for index in -1...6 {
                let x = CGFloat(index) * 5 + phase
                let distance = abs(x - size.width / 2) / (size.width / 2)
                let height = max(4, 12 - distance * 7)
                let tick = CGRect(x: x, y: (size.height - height) / 2, width: 1.5, height: height)
                context.fill(Path(roundedRect: tick, cornerRadius: 0.75), with: .color(.white.opacity(max(0.25, 1 - distance * 0.6))))
            }
        }
        .frame(width: 24, height: 16)
        .clipped()
        .frame(width: 32, height: 20)
        .background(.white.opacity(isHovered || isDragging ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, active, _ in active = true }
                .onChanged { value in
                    if dragOrigin == nil {
                        dragOrigin = CalendarTimelineScale.clamped(scale)
                        SharingStateManager.shared.beginInteraction()
                    }
                    let proposed = (dragOrigin ?? 1.0) + value.translation.width / 160
                    setScale(proposed)
                    if !CalendarTimelineScale.range.contains(proposed) {
                        // Reverse immediately at a limit, without unwinding the overshoot first.
                        dragOrigin = CalendarTimelineScale.clamped(proposed) - value.translation.width / 160
                    }
                }
                .onEnded { _ in finishDragging() }
        )
        .onChange(of: isDragging) { _, active in
            if !active { finishDragging() }
        }
        .onDisappear { finishDragging() }
        .contextMenu {
            Button("Zoom In") { setScale(scale + 0.05) }
                .disabled(CalendarTimelineScale.clamped(scale) >= CalendarTimelineScale.range.upperBound)
            Button("Zoom Out") { setScale(scale - 0.05) }
                .disabled(CalendarTimelineScale.clamped(scale) <= CalendarTimelineScale.range.lowerBound)
            Divider()
            Button("Reset to 100%") { setScale(1.0) }
        }
        .help("Timeline scale: \(percentage)%. Drag left or right; right-click to reset.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline scale")
        .accessibilityValue("\(percentage) percent")
        .accessibilityHint("Adjusts horizontal time spacing in both calendar timelines.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setScale(scale + 0.05)
            case .decrement: setScale(scale - 0.05)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Reset to 100%") { setScale(1.0) }
    }

    private func setScale(_ value: Double) {
        let next = (CalendarTimelineScale.clamped(value) * 100).rounded() / 100
        if scale != next { scale = next }
    }

    private func finishDragging() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        SharingStateManager.shared.endInteraction()
    }
}
