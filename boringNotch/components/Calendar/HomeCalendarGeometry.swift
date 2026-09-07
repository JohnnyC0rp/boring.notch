import Foundation

/// A rolling window with one continuous elapsed-time scale across calendar days.
enum HomeCalendarGeometry {
    static let pointsPerHour = 96.0

    struct Day: Identifiable {
        let interval: DateInterval

        var id: Date { interval.start }
        var width: Double { interval.duration / 3600 * pointsPerHour }
    }

    static func days(centeredOn date: Date, calendar: Calendar = .current) -> [Day] {
        let center = calendar.startOfDay(for: date)
        return (-3...3).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: center)!
            return Day(interval: calendar.dateInterval(of: .day, for: day)!)
        }
    }

    static func span(of days: [Day]) -> DateInterval? {
        guard let first = days.first, let last = days.last else { return nil }
        return DateInterval(start: first.interval.start, end: last.interval.end)
    }

    static func offset(of date: Date, in days: [Day]) -> Double {
        guard let span = span(of: days) else { return 0 }
        return min(max(date.timeIntervalSince(span.start), 0), span.duration) / 3600 * pointsPerHour
    }

    static func date(at offset: Double, in days: [Day]) -> Date? {
        guard let span = span(of: days) else { return nil }
        let elapsed = min(max(offset / pointsPerHour * 3600, 0), span.duration)
        return span.start.addingTimeInterval(elapsed)
    }

    static func needsRecentering(visibleDate: Date, in days: [Day], calendar: Calendar = .current) -> Bool {
        guard days.count >= 3 else { return true }
        return visibleDate < days[1].interval.start || visibleDate >= days[days.count - 2].interval.end
    }
}
