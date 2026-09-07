import Foundation

/// A rolling window with one elapsed-time scale and each day's unused nights removed.
enum HomeCalendarGeometry {
    static let pointsPerHour = 96.0

    struct Day: Identifiable, Equatable {
        let interval: DateInterval
        let visibleInterval: DateInterval

        init(interval: DateInterval, visibleInterval: DateInterval? = nil) {
            self.interval = interval
            self.visibleInterval = visibleInterval ?? interval
        }

        var id: Date { interval.start }
        var width: Double { visibleInterval.duration / 3600 * pointsPerHour }
        func isTimeVisible(_ date: Date) -> Bool { date >= visibleInterval.start && date < visibleInterval.end }
    }

    static func days(centeredOn date: Date, events: [CalendarTimelineGeometry.Interval] = [], calendar: Calendar = .current) -> [Day] {
        let center = calendar.startOfDay(for: date)
        return (-3...3).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: center)!
            let interval = calendar.dateInterval(of: .day, for: day)!
            return Day(interval: interval, visibleInterval: CalendarTimelineGeometry.visibleRange(in: interval, events: events, calendar: calendar))
        }
    }

    static func span(of days: [Day]) -> DateInterval? {
        guard let first = days.first, let last = days.last else { return nil }
        return DateInterval(start: first.interval.start, end: last.interval.end)
    }

    static func offset(of date: Date, in days: [Day]) -> Double {
        var offset = 0.0
        for day in days {
            if date < day.interval.end {
                return offset + CalendarTimelineGeometry.position(of: date, in: day.visibleInterval, pointsPerHour: pointsPerHour)
            }
            offset += day.width
        }
        return offset
    }

    static func date(at offset: Double, in days: [Day]) -> Date? {
        var remaining = max(0, offset)
        for (index, day) in days.enumerated() {
            if remaining < day.width || index == days.count - 1 {
                return day.visibleInterval.start.addingTimeInterval(min(remaining / pointsPerHour * 3600, day.visibleInterval.duration))
            }
            remaining -= day.width
        }
        return nil
    }

    /// Reset the whole viewport inside its requested day, even before 07:00 or after 19:00.
    static func viewportOffset(near date: Date, on requestedDay: Date, viewportWidth: Double, in days: [Day]) -> Double {
        guard let day = days.first(where: { requestedDay >= $0.interval.start && requestedDay < $0.interval.end }) else {
            return offset(of: date, in: days)
        }
        let leading = offset(of: day.interval.start, in: days)
        let local = CalendarTimelineGeometry.position(of: date, in: day.visibleInterval, pointsPerHour: pointsPerHour)
        return leading + min(local, max(0, day.width - max(0, viewportWidth)))
    }

    static func needsRecentering(visibleDate: Date, in days: [Day], calendar: Calendar = .current) -> Bool {
        guard days.count >= 3 else { return true }
        return visibleDate < days[1].interval.start || visibleDate >= days[days.count - 2].interval.end
    }
}
