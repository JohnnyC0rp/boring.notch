import Defaults
import EventKit
import SwiftUI

/// A continuous strip of time beside the player, with a bounded rolling data window.
@MainActor
struct HomeCalendarTimelineView: View {
    let showMonth: () -> Void
    @ObservedObject private var manager = CalendarManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @State private var windowCenter: Date
    @State private var displayedDate: Date
    @State private var targetDate: Date
    @State private var resetID = 0
    @State private var reloadID = 0
    @State private var events: [EventModel] = []
    @State private var selectedEvent: EventModel?
    @State private var pendingInitialPosition = true
    @State private var loading = true
    @State private var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @State private var reminderAccess = EKEventStore.authorizationStatus(for: .reminder)

    init(showMonth: @escaping () -> Void) {
        self.showMonth = showMonth
        let date = BoringViewCoordinator.shared.calendarDate
        _windowCenter = State(initialValue: date)
        _displayedDate = State(initialValue: date)
        _targetDate = State(initialValue: Self.initialPosition(for: date))
    }

    private var days: [HomeCalendarGeometry.Day] {
        HomeCalendarGeometry.days(centeredOn: windowCenter, events: events.map {
            .init(id: $0.homeTimelineID, start: $0.start, end: $0.end,
                  isAllDay: $0.isAllDay, isReminder: $0.type.isReminder)
        })
    }
    private var hasAccess: Bool { calendarAccess == .fullAccess || reminderAccess == .fullAccess }
    private var requestID: String { "\(days.first!.id.timeIntervalSince1970)-\(reloadID)" }
    private var visibleEvents: [EventModel] {
        events.filter {
            if $0.isAllDay && hideAllDayEvents { return false }
            if case .reminder(let completed) = $0.type { return !hideCompletedReminders || !completed }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            if hasAccess {
                ZStack {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HomeCalendarScrollView(days: days, targetDay: displayedDate, targetDate: targetDate, resetID: resetID,
                                               height: 100, onScroll: didScroll) {
                            HStack(spacing: HomeCalendarGeometry.daySpacing) {
                                ForEach(days) { day in
                                    HomeCalendarDayLane(day: day, events: timedEvents(on: day.interval), now: context.date) {
                                        selectedEvent = $0
                                    }
                                }
                            }
                            .frame(height: 100)
                            .background(.black)
                        }
                    }
                    if let selectedEvent {
                        HomeCalendarEventDetails(event: selectedEvent) { self.selectedEvent = nil }
                    }
                }
                .frame(height: 100)
                .clipped()
            } else {
                permissionState.frame(height: 100)
            }
        }
        .foregroundStyle(.white)
        .frame(height: 130, alignment: .top)
        .calendarTodayShortcut { jump(to: Date(), showCurrentTime: true) }
        .task(id: requestID) { await reload() }
        .onChange(of: manager.selectedCalendarIDs) { _, _ in reloadID += 1 }
        .onChange(of: coordinator.calendarDate) { _, date in
            if !Calendar.current.isDate(date, inSameDayAs: displayedDate) { jump(to: date) }
        }
        .onChange(of: visibleEvents) { _, events in
            if let selectedEvent, !events.contains(where: { $0.homeTimelineID == selectedEvent.homeTimelineID }) {
                self.selectedEvent = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in reloadID += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadID += 1 }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(displayedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            if loading { ProgressView().controlSize(.mini) }
            Spacer(minLength: 0)
            let day = CalendarTimelineGeometry.dayInterval(for: displayedDate)
            let special = visibleEvents.filter {
                if $0.type.isReminder { return $0.start >= day.start && $0.start < day.end }
                return $0.isAllDay && $0.start < day.end && $0.end > day.start
            }
            if !special.isEmpty {
                Menu {
                    ForEach(special, id: \.homeTimelineID) { event in
                        Button("\(event.type.isReminder ? "Reminder" : "All-day"): \(event.title)") {
                            selectedEvent = event
                        }
                    }
                } label: {
                    Label("\(special.count)", systemImage: "rectangle.stack")
                        .font(.system(size: 9))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("All-day events and reminders")
                .accessibilityLabel("\(special.count) all-day events and reminders")
            }
            dayArrow("chevron.left", offset: -1)
            Button("Today") { jump(to: Date(), showCurrentTime: true) }
                .help("Today (T)")
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white.opacity(0.08), in: Capsule())
            dayArrow("chevron.right", offset: 1)
            Button(action: showMonth) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
            .help("Show month")
            .accessibilityLabel("Show month calendar")
        }
        .buttonStyle(.plain)
        .frame(height: 21)
    }

    private func dayArrow(_ symbol: String, offset: Int) -> some View {
        Button {
            if let date = Calendar.current.date(byAdding: .day, value: offset, to: displayedDate) { jump(to: date) }
        } label: {
            Image(systemName: symbol).font(.system(size: 9)).frame(width: 15, height: 20)
        }
        .help(offset < 0 ? "Previous day" : "Next day")
        .accessibilityLabel(offset < 0 ? "Previous day" : "Next day")
    }

    private func timedEvents(on day: DateInterval) -> [EventModel] {
        visibleEvents.filter {
            !$0.isAllDay && !$0.type.isReminder && $0.start < day.end &&
                ($0.end > day.start || ($0.start == $0.end && $0.start >= day.start))
        }
    }

    private func didScroll(to date: Date) {
        pendingInitialPosition = false
        if !Calendar.current.isDate(date, inSameDayAs: displayedDate) {
            displayedDate = date
            coordinator.calendarDate = date
        }
        if HomeCalendarGeometry.needsRecentering(visibleDate: date, in: days) {
            windowCenter = date
        }
    }

    private func jump(to date: Date, showCurrentTime: Bool = false) {
        let needsReload = !Calendar.current.isDate(date, inSameDayAs: windowCenter)
        selectedEvent = nil
        displayedDate = date
        windowCenter = date
        coordinator.calendarDate = date
        targetDate = showCurrentTime ? Date().addingTimeInterval(-3600) : Self.initialPosition(for: date)
        pendingInitialPosition = !showCurrentTime || loading || needsReload
        resetID += 1
    }

    private static func initialPosition(for date: Date) -> Date {
        if Defaults[.autoScrollToNextEvent] && Calendar.current.isDateInToday(date) {
            return Date().addingTimeInterval(-3600)
        }
        return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
    }

    private func reload() async {
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        guard hasAccess, let span = HomeCalendarGeometry.span(of: days) else {
            events = []
            loading = false
            return
        }
        loading = true
        let result = await manager.events(from: span.start, to: span.end)
        guard !Task.isCancelled, span == HomeCalendarGeometry.span(of: days) else { return }
        events = result
        if let selectedEvent {
            self.selectedEvent = result.first { $0.homeTimelineID == selectedEvent.homeTimelineID }
        }
        if pendingInitialPosition {
            pendingInitialPosition = false
            if Defaults[.autoScrollToNextEvent], !Calendar.current.isDateInToday(displayedDate) {
                let day = CalendarTimelineGeometry.dayInterval(for: displayedDate)
                if let first = timedEvents(on: day).first {
                    targetDate = max(first.start, day.start).addingTimeInterval(-1800)
                }
            }
            resetID += 1
        }
        loading = false
    }

    private var permissionState: some View {
        VStack(spacing: 7) {
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.5))
            Text("Your day, on a timeline").font(.system(size: 11, weight: .medium))
            Button(calendarAccess == .notDetermined ? "Connect Calendar" : "Calendar Privacy Settings") {
                if calendarAccess == .notDetermined {
                    Task { await manager.checkCalendarAuthorization(); reloadID += 1 }
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered).controlSize(.mini)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeCalendarDayLane: View {
    let day: HomeCalendarGeometry.Day
    let events: [EventModel]
    let now: Date
    let select: (EventModel) -> Void

    private var layout: [CalendarTimelineGeometry.Placement] {
        CalendarTimelineGeometry.layout(events.map { .init(id: $0.homeTimelineID, start: $0.start, end: $0.end) },
                                        in: day.visibleInterval, pointsPerHour: HomeCalendarGeometry.pointsPerHour)
    }

    var body: some View {
        let placements = layout
        let laneCounts = CalendarTimelineGeometry.clusterLaneCounts(for: placements)
        let progress = position(now)
        let isToday = day.isTimeVisible(now)
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.035))
                Rectangle().fill(.white.opacity(0.025)).frame(width: progress)
                ForEach(CalendarTimelineGeometry.hourTicks(in: day.visibleInterval).dropLast(), id: \.self) { tick in
                    Rectangle().fill(.white.opacity(0.06)).frame(width: 1).offset(x: position(tick))
                }
                ForEach(placements.filter { $0.lane < 2 }) { placement in
                    if let event = events.first(where: { $0.homeTimelineID == placement.id }) {
                        let count = laneCounts[placement.id] ?? 1
                        let laneHeight: CGFloat = count == 1 ? 80 : count == 2 ? 40 : 30
                        eventBlock(event, placement: placement, laneHeight: laneHeight)
                    }
                }
                ForEach(overflowGroups(placements)) { group in
                    Menu {
                        ForEach(group.events, id: \.homeTimelineID) { event in
                            Button(event.title) { select(event) }
                        }
                    } label: {
                        Text("+\(group.events.count) overlapping")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .frame(width: group.width, height: 18, alignment: .leading)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .offset(x: group.x, y: 62)
                    .help("\(group.events.count) more overlapping events")
                }
                if isToday {
                    Rectangle().fill(.red).frame(width: 1.5).offset(x: progress)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: day.width, height: 80, alignment: .topLeading)
            ZStack(alignment: .topLeading) {
                ForEach(CalendarTimelineGeometry.hourTicks(in: day.visibleInterval), id: \.self) { tick in
                    Text(tickLabel(tick))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .offset(x: min(position(tick) + 4, day.width - 34))
                }
                Text(day.interval.start.formatted(.dateTime.weekday(.abbreviated).day()).uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.red.opacity(0.75))
                    .padding(.horizontal, 4)
                    .background(.black)
                    .offset(x: 39)
                if isToday {
                    Text(now.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .background(.red, in: Capsule())
                        .offset(x: min(max(0, progress - 18), day.width - 52))
                }
            }
            .frame(width: day.width, height: 16, alignment: .topLeading)
        }
        .frame(width: day.width, height: 100)
        .overlay(alignment: .topLeading) {
            DayBoundaryBrackets().stroke(.red.opacity(0.65), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                .frame(width: day.width - 2, height: 76)
                .offset(x: 1, y: 2)
                .allowsHitTesting(false)
                .accessibilityLabel("Start of \(day.interval.start.formatted(date: .complete, time: .omitted))")
        }
    }

    private func eventBlock(_ event: EventModel, placement: CalendarTimelineGeometry.Placement, laneHeight: CGFloat) -> some View {
        let color = Color(event.calendar.color)
        let tall = laneHeight > 40
        return Button { select(event) } label: {
            ZStack(alignment: .leading) {
                Color.clear
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2)
                    if placement.width > 28 {
                        VStack(alignment: .leading, spacing: tall ? 4 : 1) {
                            Text(event.title)
                                .font(.system(size: tall ? 11 : 9, weight: .medium))
                                .lineLimit(tall ? 3 : laneHeight > 30 ? 2 : 1)
                            if let location = event.location, !location.isEmpty {
                                Text(location.replacingOccurrences(of: "\n", with: ", "))
                                    .font(.system(size: tall ? 9 : 7))
                                    .foregroundStyle(color.opacity(0.9))
                                    .lineLimit(tall ? 2 : 1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, tall ? 5 : 2)
                .padding(.horizontal, placement.width > 28 ? 4 : 0)
                .frame(width: max(1, placement.width), height: laneHeight - 4, alignment: .leading)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.3), lineWidth: 1) }
                .clipped()
                .offset(x: placement.x - placement.hitX)
            }
            .frame(width: placement.hitWidth, height: laneHeight - 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: placement.hitX, y: CGFloat(placement.lane) * laneHeight + 2)
        .opacity(event.end < now && Calendar.current.isDateInToday(day.interval.start) ? 0.55 : 1)
        .help("\(event.title)\n\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))\(event.location.map { "\n\($0)" } ?? "")")
        .accessibilityLabel("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened)) to \(event.end.formatted(date: .omitted, time: .shortened)), \(event.location ?? "")")
    }

    private func position(_ date: Date) -> Double {
        CalendarTimelineGeometry.position(of: date, in: day.visibleInterval, pointsPerHour: HomeCalendarGeometry.pointsPerHour)
    }

    private func tickLabel(_ tick: Date) -> String {
        let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        let label = tick.formatted(format)
        let repeats = CalendarTimelineGeometry.hourTicks(in: day.visibleInterval).dropLast().filter { $0.formatted(format) == label }.count > 1
        return repeats ? "\(label) \(TimeZone.current.abbreviation(for: tick) ?? "")" : label
    }

    private struct OverflowGroup: Identifiable {
        let id: String
        var x: CGFloat
        var width: CGFloat
        var events: [EventModel]
    }

    private func overflowGroups(_ placements: [CalendarTimelineGeometry.Placement]) -> [OverflowGroup] {
        var groups: [OverflowGroup] = []
        for placement in placements.filter({ $0.lane >= 2 }).sorted(by: { $0.hitX < $1.hitX }) {
            guard let event = events.first(where: { $0.homeTimelineID == placement.id }) else { continue }
            if let last = groups.last, last.x + last.width >= placement.hitX {
                groups[groups.count - 1].width = max(last.x + last.width, placement.hitX + placement.hitWidth) - last.x
                groups[groups.count - 1].events.append(event)
            } else {
                groups.append(.init(id: placement.id, x: placement.hitX, width: placement.hitWidth, events: [event]))
            }
        }
        return groups
    }
}

private struct DayBoundaryBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [rect.minX, rect.maxX] {
            let inward = x == rect.minX ? 6.0 : -6.0
            path.move(to: CGPoint(x: x + inward, y: rect.minY))
            path.addLines([CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.minY + 8)])
            path.move(to: CGPoint(x: x + inward, y: rect.maxY))
            path.addLines([CGPoint(x: x, y: rect.maxY), CGPoint(x: x, y: rect.maxY - 8)])
        }
        return path
    }
}

private struct HomeCalendarEventDetails: View {
    @Environment(\.openURL) private var openURL
    let event: EventModel
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: close) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                    .frame(width: 23, height: 23)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to timeline")
            .accessibilityLabel("Back to timeline")
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.system(size: 11, weight: .semibold))
                    Text(timeDescription).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    if let location = event.location, !location.isEmpty {
                        Text(location.replacingOccurrences(of: "\n", with: ", "))
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    }
                    Text(event.calendar.title).font(.system(size: 9)).foregroundStyle(Color(event.calendar.color))
                    if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        Text(notes).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).textSelection(.enabled)
                    }
                    if !event.participants.isEmpty {
                        Label(event.participants.map { $0.name + ($0.isOrganizer ? " (organizer)" : "") }.joined(separator: ", "), systemImage: "person.2")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    }
                    if let url = event.url {
                        Link(destination: url) { Label(url.host ?? "Event link", systemImage: "link").font(.system(size: 9)) }
                    }
                    if let zone = event.timeZone, zone != .current {
                        Text("Event time zone: \(zone.identifier)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                    }
                    Button(event.type.isReminder ? "Open in Reminders ↗" : "Open in Calendar ↗") {
                        if let url = event.calendarAppURL() { openURL(url) }
                    }
                    .buttonStyle(.plain).font(.system(size: 9, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private var timeDescription: String {
        if event.isAllDay { return "All-day" }
        if event.type.isReminder { return "Due \(event.start.formatted(date: .omitted, time: .shortened))" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        let duration = formatter.string(from: max(0, event.end.timeIntervalSince(event.start))) ?? ""
        let sameDay = Calendar.current.isDate(event.start, inSameDayAs: event.end)
        return "\(event.start.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)) – \(event.end.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)) · \(duration)"
    }
}

private extension EventModel {
    var homeTimelineID: String { "\(id)-\(start.timeIntervalSince1970)" }
}
