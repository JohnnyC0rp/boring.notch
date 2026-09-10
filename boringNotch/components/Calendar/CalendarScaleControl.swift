import Defaults
import SwiftUI

/// A stationary thumbwheel; dragging changes time spacing without resizing the control.
struct CalendarScaleControl: View {
    var minimumScale: Double = 0

    @Default(.calendarTimelineScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false
    @State private var dragOrigin: Double?
    @State private var isHovered = false

    private var lowerBound: Double {
        CalendarTimelineScale.clamped(minimumScale)
    }

    private var effectiveScale: Double {
        max(lowerBound, CalendarTimelineScale.clamped(scale))
    }

    private var fitsDay: Bool {
        CalendarTimelineScale.clamped(scale) <= lowerBound
    }

    private var scaleDescription: String {
        fitsDay ? "Fit day" : "\(Int((effectiveScale * 100).rounded()))%"
    }

    var body: some View {
        Canvas { context, size in
            let phase = reduceMotion ? 0 : (effectiveScale * 40).truncatingRemainder(dividingBy: 5)
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
                        dragOrigin = effectiveScale
                        SharingStateManager.shared.beginInteraction()
                    }
                    let proposed = (dragOrigin ?? 1.0) + value.translation.width / 160
                    setScale(proposed)
                    if proposed < lowerBound || proposed > CalendarTimelineScale.range.upperBound {
                        // Reverse immediately at a limit, without unwinding the overshoot first.
                        dragOrigin = max(lowerBound, CalendarTimelineScale.clamped(proposed)) - value.translation.width / 160
                    }
                }
                .onEnded { _ in finishDragging() }
        )
        .onChange(of: isDragging) { _, active in
            if !active { finishDragging() }
        }
        .onDisappear { finishDragging() }
        .contextMenu {
            Button("Zoom In") { setScale(effectiveScale + 0.05) }
                .disabled(effectiveScale >= CalendarTimelineScale.range.upperBound)
            Button("Zoom Out") { setScale(effectiveScale - 0.05) }
                .disabled(fitsDay)
            Divider()
            Button("Fit Day") { setScale(0) }
                .disabled(fitsDay)
            Button("Reset to 100%") { setScale(1.0) }
        }
        .help("Timeline scale: \(scaleDescription). Drag left or right; right-click for Fit Day or reset.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline scale")
        .accessibilityValue(fitsDay ? "Fit day" : "\(Int((effectiveScale * 100).rounded())) percent")
        .accessibilityHint("Adjusts horizontal time spacing in both calendar timelines.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setScale(effectiveScale + 0.05)
            case .decrement: setScale(effectiveScale - 0.05)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Fit Day") { setScale(0) }
        .accessibilityAction(named: "Reset to 100%") { setScale(1.0) }
    }

    private func setScale(_ value: Double) {
        let rounded = (CalendarTimelineScale.clamped(value) * 100).rounded() / 100
        let next = value <= lowerBound || rounded <= lowerBound ? 0 : rounded
        if scale != next { scale = next }
    }

    private func finishDragging() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        SharingStateManager.shared.endInteraction()
    }
}
