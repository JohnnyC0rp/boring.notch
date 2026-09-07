import Foundation

/// All positions use elapsed time within a calendar day, including 23- and 25-hour days.
enum CalendarTimelineGeometry {
    static let pointsPerHour = 92.0
    static let minimumHitWidth = 24.0

    struct Interval {
        let id: String
        let start: Date
        let end: Date
    }

    struct Placement: Identifiable {
        let id: String
        let x: Double
        let width: Double
        let hitX: Double
        let hitWidth: Double
        let lane: Int
    }

    static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func position(of date: Date, in day: DateInterval, pointsPerHour: Double = pointsPerHour) -> Double {
        min(max(date.timeIntervalSince(day.start), 0), day.duration) / 3600 * pointsPerHour
    }

    static func hourTicks(in day: DateInterval) -> [Date] {
        // Advancing actual hours preserves both occurrences of a repeated autumn hour.
        var ticks = stride(from: 0.0, through: day.duration, by: 3600).map {
            day.start.addingTimeInterval($0)
        }
        if ticks.last != day.end { ticks.append(day.end) }
        return ticks
    }

    static func layout(_ intervals: [Interval], in day: DateInterval, pointsPerHour: Double = pointsPerHour) -> [Placement] {
        let dayWidth = day.duration / 3600 * pointsPerHour
        var laneEnds: [Double] = []
        return intervals
            .filter {
                $0.start < day.end && $0.end >= $0.start &&
                    ($0.end > day.start || ($0.start == $0.end && $0.start >= day.start))
            }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end > $1.end }
                return $0.id < $1.id
            }
            .map { interval in
                let x = position(of: interval.start, in: day, pointsPerHour: pointsPerHour)
                let width = position(of: interval.end, in: day, pointsPerHour: pointsPerHour) - x
                let hitWidth = min(max(width, minimumHitWidth), dayWidth)
                let hitX = max(0, min(x - (hitWidth - width) / 2, dayWidth - hitWidth))
                // Tiny meetings get a usable target, without pretending they last longer.
                let lane = laneEnds.firstIndex(where: { $0 <= hitX }) ?? laneEnds.count
                if lane == laneEnds.count {
                    laneEnds.append(hitX + hitWidth)
                } else {
                    laneEnds[lane] = hitX + hitWidth
                }
                return Placement(id: interval.id, x: x, width: width,
                                 hitX: hitX, hitWidth: hitWidth, lane: lane)
            }
    }
}
