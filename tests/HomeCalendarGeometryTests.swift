import Foundation

@main
enum HomeCalendarGeometryTests {
    static func main() {
        let utc = calendar("UTC")
        let center = date("2026-09-07T12:34:56Z")
        let days = HomeCalendarGeometry.days(centeredOn: center, calendar: utc)
        require(days.count == 7, "The rendered window must contain exactly seven days")
        require(Set(days.map(\.id)).count == 7, "Every day must have a stable, distinct midnight identity")
        require(days[3].id == date("2026-09-07T00:00:00Z"), "The requested date must occupy the middle day")
        require(days.first!.id == date("2026-09-04T00:00:00Z") && days.last!.id == date("2026-09-10T00:00:00Z"),
                "The window must extend three calendar days in each direction")
        require(days.allSatisfy { $0.width == 24 * 96 }, "Ordinary days must use 96 points per elapsed hour")
        require(HomeCalendarGeometry.offset(of: center.addingTimeInterval(50 * 60), in: days)
                - HomeCalendarGeometry.offset(of: center, in: days) == 80,
                "A 50-minute class must receive 80 points for readable title wrapping")
        verifyContinuousMapping(days)

        let span = HomeCalendarGeometry.span(of: days)!
        let width = days.reduce(0) { $0 + $1.width }
        require(HomeCalendarGeometry.offset(of: span.start.addingTimeInterval(-1), in: days) == 0,
                "Dates before the window must clamp to its start")
        require(HomeCalendarGeometry.offset(of: span.end.addingTimeInterval(1), in: days) == width,
                "Dates after the window must clamp to its end")
        require(HomeCalendarGeometry.date(at: -1, in: days) == span.start, "Negative offsets must clamp to the window start")
        require(HomeCalendarGeometry.date(at: width + 1, in: days) == span.end,
                "Offsets past the window must clamp to its end")
        require(HomeCalendarGeometry.span(of: []) == nil && HomeCalendarGeometry.date(at: 0, in: []) == nil,
                "An empty window has no date interval")
        require(HomeCalendarGeometry.offset(of: center, in: []) == 0, "An empty window has zero offset")
        require(HomeCalendarGeometry.needsRecentering(visibleDate: center, in: []), "An empty window must be initialized")

        require(HomeCalendarGeometry.needsRecentering(visibleDate: days[1].id.addingTimeInterval(-0.001), in: days),
                "Entering the first day must trigger recentering")
        require(!HomeCalendarGeometry.needsRecentering(visibleDate: days[1].id, in: days),
                "The second day start remains inside the safe window")
        require(!HomeCalendarGeometry.needsRecentering(visibleDate: days[5].interval.end.addingTimeInterval(-0.001), in: days),
                "The penultimate day remains inside the safe window")
        require(HomeCalendarGeometry.needsRecentering(visibleDate: days[5].interval.end, in: days),
                "Entering the last day must trigger recentering")
        require(HomeCalendarGeometry.needsRecentering(visibleDate: span.start.addingTimeInterval(-86400), in: days)
                && HomeCalendarGeometry.needsRecentering(visibleDate: span.end.addingTimeInterval(86400), in: days),
                "Dates outside either edge must trigger recentering")

        let newYork = calendar("America/New_York")
        verifyDayLength("2026-03-08T12:00:00-04:00", hours: 23, calendar: newYork)
        verifyDayLength("2026-11-01T12:00:00-05:00", hours: 25, calendar: newYork)
        let autumn = HomeCalendarGeometry.days(centeredOn: date("2026-11-01T12:00:00-05:00"), calendar: newYork)
        let firstOneThirty = date("2026-11-01T01:30:00-04:00")
        let secondOneThirty = date("2026-11-01T01:30:00-05:00")
        require(HomeCalendarGeometry.offset(of: secondOneThirty, in: autumn)
                - HomeCalendarGeometry.offset(of: firstOneThirty, in: autumn) == 96,
                "Repeated local times must retain separate positions one elapsed hour apart")

        let lordHowe = calendar("Australia/Lord_Howe")
        verifyDayLength("2026-10-04T12:00:00+11:00", hours: 23.5, calendar: lordHowe)
        verifyDayLength("2026-04-05T12:00:00+10:30", hours: 24.5, calendar: lordHowe)
        verifyDayLength("2026-09-07T12:00:00+05:45", hours: 24, calendar: calendar("Asia/Kathmandu"))

        for zone in [newYork, lordHowe] {
            for direction in [-1.0, 1.0] {
                verifyRepeatedRecentering(from: center, direction: direction, calendar: zone)
            }
        }
        print("Home calendar geometry: all checks passed (continuous seven-day window, clamping, DST, inverse mapping, 2,400 scrolling steps).")
    }

    private static func verifyDayLength(_ value: String, hours: Double, calendar: Calendar) {
        let days = HomeCalendarGeometry.days(centeredOn: date(value), calendar: calendar)
        require(days[3].interval.duration == hours * 3600, "Calendar day must preserve its actual duration: \(value)")
        require(days[3].width == hours * 96, "Day width must preserve fractional and shifted hours: \(value)")
        verifyContinuousMapping(days)
    }

    private static func verifyContinuousMapping(_ days: [HomeCalendarGeometry.Day]) {
        var x = 0.0
        for (index, day) in days.enumerated() {
            require(HomeCalendarGeometry.offset(of: day.id, in: days) == x, "Day boundaries must have no artificial pixel gaps")
            if index > 0 {
                require(days[index - 1].interval.end == day.interval.start, "Calendar days must form a contiguous interval")
            }
            for fraction in [0.0, 0.1234567, 0.5, 0.999999, 1.0] {
                let original = day.interval.start.addingTimeInterval(day.interval.duration * fraction)
                let offset = HomeCalendarGeometry.offset(of: original, in: days)
                let restored = HomeCalendarGeometry.date(at: offset, in: days)!
                require(abs(restored.timeIntervalSince(original)) < 0.000001,
                        "Elapsed date-to-offset mapping must round-trip within one microsecond")
            }
            x += day.width
        }
        require(HomeCalendarGeometry.offset(of: days.last!.interval.end, in: days) == x,
                "The continuous span must equal the sum of actual day widths")
    }

    private static func verifyRepeatedRecentering(from start: Date, direction: Double, calendar: Calendar) {
        var days = HomeCalendarGeometry.days(centeredOn: start, calendar: calendar)
        var visibleDate = start
        var recenterCount = 0
        for _ in 0..<600 {
            // Keep walking: seven rendered days must never become the end of the calendar.
            let expected = visibleDate.addingTimeInterval(direction * 18 * 3600)
            let offset = HomeCalendarGeometry.offset(of: expected, in: days)
            visibleDate = HomeCalendarGeometry.date(at: offset, in: days)!
            require(abs(visibleDate.timeIntervalSince(expected)) < 0.000001,
                    "Repeated scrolling must not become stuck at a finite window boundary")
            if HomeCalendarGeometry.needsRecentering(visibleDate: visibleDate, in: days, calendar: calendar) {
                days = HomeCalendarGeometry.days(centeredOn: visibleDate, calendar: calendar)
                let rebasedOffset = HomeCalendarGeometry.offset(of: visibleDate, in: days)
                let restoredLeadingDate = HomeCalendarGeometry.date(at: rebasedOffset, in: days)!
                require(abs(restoredLeadingDate.timeIntervalSince(visibleDate)) < 0.000001,
                        "Rebasing must preserve the viewport leading date without a visible jump")
                require(days.count == 7 && !HomeCalendarGeometry.needsRecentering(visibleDate: visibleDate, in: days),
                        "Recentered windows must remain bounded and put the viewport safely inside")
                recenterCount += 1
            }
        }
        require(recenterCount > 100, "Scrolling must repeatedly replace the bounded window")
        require(abs(visibleDate.timeIntervalSince(start) - direction * 600 * 18 * 3600) < 0.000001,
                "Long scrolls must preserve total elapsed displacement across DST changes")
    }

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
