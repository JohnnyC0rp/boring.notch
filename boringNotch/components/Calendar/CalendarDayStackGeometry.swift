import Foundation

/// Days keep a fixed row height while their horizontal timeline preserves elapsed time.
enum CalendarDayStackGeometry {
    static let rowHeight = 94.0
    static let rowSpacing = 8.0
    static let rowStride = rowHeight + rowSpacing
    static let pointsPerHour = 96.0

    struct Day: Identifiable {
        let interval: DateInterval

        var id: Date { interval.start }
    }

    struct Position: Equatable {
        let day: Date
        let intraDayOffset: Double
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

    static func position(at offset: Double, in days: [Day]) -> Position? {
        guard !days.isEmpty else { return nil }
        let y = min(max(offset, 0), documentHeight(for: days))
        let index = min(Int(floor(y / rowStride)), days.count - 1)
        return Position(day: days[index].id, intraDayOffset: y - Double(index) * rowStride)
    }

    static func offset(of position: Position, in days: [Day]) -> Double {
        guard let first = days.first else { return 0 }
        guard let index = days.firstIndex(where: { $0.id == position.day }) else {
            return position.day < first.id ? 0 : documentHeight(for: days)
        }
        let y = Double(index) * rowStride + min(max(position.intraDayOffset, 0), rowStride)
        return min(y, documentHeight(for: days))
    }

    static func needsRecentering(position: Position, in days: [Day]) -> Bool {
        guard let index = days.firstIndex(where: { $0.id == position.day }) else { return true }
        return index < 1 || index >= days.count - 3
    }

    static func documentHeight(for days: [Day]) -> Double {
        max(0, Double(days.count) * rowStride - rowSpacing)
    }
}
