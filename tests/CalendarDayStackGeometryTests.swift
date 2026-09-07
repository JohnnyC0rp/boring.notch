import Foundation

@main
enum CalendarDayStackGeometryTests {
    static func main() {
        let utc = calendar("UTC")
        let center = date("2026-09-07T12:34:56Z")
        let days = CalendarDayStackGeometry.days(centeredOn: center, calendar: utc)
        require(days.count == 7 && Set(days.map(\.id)).count == 7,
                "The rolling window must contain seven distinct days")
        require(days[3].id == date("2026-09-07T00:00:00Z"), "The requested day must occupy the middle row")
        require(days.first!.id == date("2026-09-04T00:00:00Z") && days.last!.id == date("2026-09-10T00:00:00Z"),
                "The window must extend three calendar days in each direction")
        require(CalendarDayStackGeometry.rowHeight == 94 && CalendarDayStackGeometry.rowSpacing == 12
                && CalendarDayStackGeometry.rowStride == 106 && CalendarDayStackGeometry.pointsPerHour == 96,
                "The day stack must use the intended fixed row and horizontal hour dimensions")
        verifyWindow(days)

        let documentHeight = CalendarDayStackGeometry.documentHeight(for: days)
        require(documentHeight == 730, "Seven rows must have only six intervening gaps")
        let twoRowHeight = CalendarDayStackGeometry.documentHeight(for: Array(days.prefix(2)))
        require(twoRowHeight == 200 && twoRowHeight <= 202,
                "Two complete day rows and their gap must fit inside the 202-point viewport")
        require(CalendarDayStackGeometry.position(at: -10, in: days) == .init(day: days[0].id, intraDayOffset: 0),
                "Negative positions must clamp to the first row")
        require(CalendarDayStackGeometry.position(at: documentHeight + 10, in: days)
                == .init(day: days[6].id, intraDayOffset: 94), "Positions beyond the document must clamp to its bottom")
        require(CalendarDayStackGeometry.offset(of: .init(day: days[0].id, intraDayOffset: -1), in: days) == 0,
                "Negative within-row offsets must clamp")
        require(CalendarDayStackGeometry.offset(of: .init(day: days[6].id, intraDayOffset: 200), in: days) == documentHeight,
                "Oversized within-row offsets must stay inside the document")
        require(CalendarDayStackGeometry.offset(of: .init(day: days[0].id.addingTimeInterval(-86400), intraDayOffset: 40), in: days) == 0,
                "Days before the window must clamp to its beginning")
        require(CalendarDayStackGeometry.offset(of: .init(day: days[6].id.addingTimeInterval(86400), intraDayOffset: 40), in: days) == documentHeight,
                "Days after the window must clamp to its end")
        require(CalendarDayStackGeometry.documentHeight(for: []) == 0 && CalendarDayStackGeometry.span(of: []) == nil
                && CalendarDayStackGeometry.position(at: 0, in: []) == nil, "Empty windows must have no rows or position")
        require(CalendarDayStackGeometry.offset(of: .init(day: center, intraDayOffset: 0), in: []) == 0,
                "An empty window must have zero offset")

        for (index, day) in days.enumerated() {
            let expected = index < 1 || index >= 4
            require(CalendarDayStackGeometry.needsRecentering(position: .init(day: day.id, intraDayOffset: 17.625), in: days) == expected,
                    "Recentering must leave enough forward rows for the two-row viewport")
        }
        require(CalendarDayStackGeometry.needsRecentering(position: .init(day: center, intraDayOffset: 0), in: []),
                "A missing day must trigger window initialization")

        let newYork = calendar("America/New_York")
        verifyDayLength("2026-03-08T12:00:00-04:00", hours: 23, calendar: newYork)
        verifyDayLength("2026-11-01T12:00:00-05:00", hours: 25, calendar: newYork)
        let lordHowe = calendar("Australia/Lord_Howe")
        verifyDayLength("2026-10-04T12:00:00+11:00", hours: 23.5, calendar: lordHowe)
        verifyDayLength("2026-04-05T12:00:00+10:30", hours: 24.5, calendar: lordHowe)

        for zone in [newYork, lordHowe] {
            for direction in [-1, 1] {
                verifyRepeatedRecentering(from: center, direction: direction, calendar: zone)
            }
        }
        print("Calendar day-stack geometry: all checks passed (fixed rows, fractional offsets, DST, 2,400 recentered day steps).")
    }

    private static func verifyDayLength(_ value: String, hours: Double, calendar: Calendar) {
        let days = CalendarDayStackGeometry.days(centeredOn: date(value), calendar: calendar)
        require(days[3].interval.duration == hours * 3600, "Calendar day must preserve its elapsed duration: \(value)")
        verifyWindow(days)
    }

    private static func verifyWindow(_ days: [CalendarDayStackGeometry.Day]) {
        require(days.count == 7 && Set(days.map(\.id)).count == 7, "Day identities must remain distinct across DST")
        let span = CalendarDayStackGeometry.span(of: days)!
        require(span.start == days[0].interval.start && span.end == days[6].interval.end,
                "The fetch span must include the complete seven-day window")
        for (index, day) in days.enumerated() {
            if index > 0 {
                require(days[index - 1].interval.end == day.interval.start, "Day intervals must be contiguous")
            }
            let rowStart = Double(index) * CalendarDayStackGeometry.rowStride
            require(CalendarDayStackGeometry.offset(of: .init(day: day.id, intraDayOffset: 0), in: days) == rowStart,
                    "DST must never change vertical day-row spacing")
            var fractions = [0.0, 0.123456789, 17.625, 93.999999, 94.0]
            if index < days.count - 1 { fractions.append(contentsOf: [97.125, 104, 105.999]) }
            for fraction in fractions {
                let y = rowStart + fraction
                let position = CalendarDayStackGeometry.position(at: y, in: days)!
                require(position.day == day.id && abs(position.intraDayOffset - fraction) < 0.000000001,
                        "Fractional row and gap positions must preserve their exact day-relative placement")
                require(abs(CalendarDayStackGeometry.offset(of: position, in: days) - y) < 0.000000001,
                        "Pixel positions must round-trip within one billionth of a point")
            }
        }
        require(CalendarDayStackGeometry.documentHeight(for: days) == 730,
                "DST and fractional-hour transitions must not change the document height")
    }

    private static func verifyRepeatedRecentering(from start: Date, direction: Int, calendar: Calendar) {
        var days = CalendarDayStackGeometry.days(centeredOn: start, calendar: calendar)
        var position = CalendarDayStackGeometry.Position(day: days[3].id, intraDayOffset: 17.625)
        let initialDay = position.day
        var recenterCount = 0
        for step in 1...600 {
            // Seven rendered days are a window, not a calendar with an expiry date.
            let y = CalendarDayStackGeometry.offset(of: position, in: days)
                + Double(direction) * CalendarDayStackGeometry.rowStride
            let next = CalendarDayStackGeometry.position(at: y, in: days)!
            let expectedDay = calendar.date(byAdding: .day, value: direction * step, to: initialDay)!
            require(next.day == expectedDay && next.intraDayOffset == 17.625,
                    "Scrolling must continue by calendar day without a finite edge or fractional drift")
            position = next
            if CalendarDayStackGeometry.needsRecentering(position: position, in: days) {
                days = CalendarDayStackGeometry.days(centeredOn: position.day, calendar: calendar)
                let rebasedY = CalendarDayStackGeometry.offset(of: position, in: days)
                require(CalendarDayStackGeometry.position(at: rebasedY, in: days) == position,
                        "Recentering must preserve both leading day and fractional within-row offset")
                require(days.count == 7 && !CalendarDayStackGeometry.needsRecentering(position: position, in: days),
                        "Recentered windows must remain bounded and allow two visible rows")
                recenterCount += 1
            }
        }
        require(recenterCount >= 200, "Long scrolling must repeatedly replace the bounded day window")
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
