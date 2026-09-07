import Defaults
import EventKit
import SwiftUI

struct CalendarTimelineView: View {
    let compact: Bool
    let showMonth: (() -> Void)?
    @ObservedObject private var manager = CalendarManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @State private var events: [EventModel] = []
    @State private var selectedEvent: EventModel?
    @State private var reloadID = 0
    @State private var scrollID = 0
    @State private var loading = true
    @State private var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @State private var reminderAccess = EKEventStore.authorizationStatus(for: .reminder)

    init(compact: Bool = false, showMonth: (() -> Void)? = nil) {
        self.compact = compact
        self.showMonth = showMonth
    }

    private var rowHeight: CGFloat { compact ? 49 : 86 }
    private var rowSpacing: CGFloat { compact ? 4 : 8 }
    private var pointsPerHour: Double { compact ? 54 : CalendarTimelineGeometry.pointsPerHour }
    private var firstDay: Date { Calendar.current.startOfDay(for: coordinator.calendarDate) }
    private var secondDay: Date { Calendar.current.date(byAdding: .day, value: 1, to: firstDay)! }
    private var hasAccess: Bool { calendarAccess == .fullAccess || reminderAccess == .fullAccess }
    private var requestID: String { "\(firstDay.timeIntervalSince1970)-\(reloadID)" }

    var body: some View {
        VStack(spacing: compact ? 4 : 10) {
            header
            if hasAccess {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    timeline(now: context.date)
                }
            } else {
                permissionState
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: compact ? 130 : 238, alignment: .top)
        .task(id: requestID) { await reload() }
        .onChange(of: manager.selectedCalendarIDs) { _, _ in reloadID += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in reloadID += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadID += 1
        }
        .onChange(of: hideAllDayEvents) { _, _ in clearHiddenSelection() }
        .onChange(of: hideCompletedReminders) { _, _ in clearHiddenSelection() }
        .onExitCommand { selectedEvent = nil }
    }

    private var header: some View {
        HStack(spacing: compact ? 4 : 9) {
            Text(compact ? firstDay.formatted(.dateTime.month(.abbreviated).day()) : firstDay.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: compact ? 11 : 14, weight: .semibold))
                .lineLimit(1)
            if loading { ProgressView().controlSize(.mini) }
            Spacer(minLength: compact ? 2 : 8)
            if !compact {
                Text("DAY TIMELINE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Button { navigate(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: compact ? 9 : 12))
                    .frame(width: compact ? 14 : 22, height: compact ? 19 : 24)
            }
            .help("Previous day")
            .accessibilityLabel("Previous day")
            Button("Today") {
                selectedEvent = nil
                coordinator.calendarDate = Date()
                scrollID += 1
            }
            .font(.system(size: compact ? 9 : 11, weight: .medium))
            .padding(.horizontal, compact ? 5 : 9)
            .padding(.vertical, compact ? 3 : 5)
            .background(.white.opacity(0.09), in: Capsule())
            Button { navigate(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: compact ? 9 : 12))
                    .frame(width: compact ? 14 : 22, height: compact ? 19 : 24)
            }
            .help("Next day")
            .accessibilityLabel("Next day")
            if let showMonth {
                Button(action: showMonth) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .frame(width: 19, height: 19)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .help("Show month")
                .accessibilityLabel("Show month calendar")
            }
        }
        .buttonStyle(.plain)
        .frame(height: compact ? 19 : 26)
    }

    private func timeline(now: Date) -> some View {
        VStack(spacing: rowSpacing) {
            ScrollViewReader { proxy in
                HStack(spacing: compact ? 4 : 8) {
                    VStack(spacing: rowSpacing) {
                        dayLabel(firstDay, now: now)
                        if selectedEvent == nil { dayLabel(secondDay, now: now) }
                    }
                    ScrollView(.horizontal, showsIndicators: !compact) {
                        VStack(alignment: .leading, spacing: rowSpacing) {
                            dayTrack(firstDay, now: now)
                            if selectedEvent == nil { dayTrack(secondDay, now: now) }
                        }
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                ForEach(0..<26) { hour in
                                    Color.clear
                                        .frame(width: pointsPerHour, height: 1)
                                        .id(hour)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .onAppear { scrollToRelevantTime(proxy: proxy, now: now) }
                    .onChange(of: firstDay) { _, _ in scrollToRelevantTime(proxy: proxy, now: now) }
                    .onChange(of: scrollID) { _, _ in scrollToRelevantTime(proxy: proxy, now: now) }
                    .onChange(of: loading) { _, isLoading in
                        if !isLoading { scrollToRelevantTime(proxy: proxy, now: now) }
                    }
                }
            }
            .frame(height: selectedEvent == nil ? rowHeight * 2 + rowSpacing : rowHeight)
            if let event = selectedEvent {
                CalendarTimelineDetails(event: event, showIdentity: compact || selectedBlockIsShort(event), compact: compact) { selectedEvent = nil }
                    .frame(height: rowHeight)
            }
            if !compact {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.and.right")
                    Text(selectedEvent == nil ? "Scroll through the hours · Select an event for details" : "Selected event · Use the back arrow to return to two days")
                    Spacer(minLength: 0)
                    if calendarAccess != .fullAccess {
                        Button("Calendar access") { requestCalendarAccess() }
                            .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func dayLabel(_ date: Date, now: Date) -> some View {
        let today = Calendar.current.isDate(date, inSameDayAs: now)
        let dayEvents = visibleEvents(on: date)
        let special = dayEvents.filter { $0.isAllDay || $0.type.isReminder }
        return VStack(alignment: .leading, spacing: compact ? 1 : 5) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: compact ? 6 : 9, weight: .semibold))
                .foregroundStyle(today ? Color.red : .white.opacity(0.5))
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: compact ? 15 : 23, weight: .semibold, design: .rounded))
                .foregroundStyle(today ? Color.red : .white)
            if special.isEmpty && !compact {
                Text(today ? "TODAY" : date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            } else if !special.isEmpty {
                Menu {
                    ForEach(special, id: \.timelineID) { event in
                        Button {
                            select(event, on: date)
                        } label: {
                            Text("\(event.type.isReminder ? "Reminder" : "All-day"): \(event.title)")
                        }
                    }
                } label: {
                    Label("\(special.count)", systemImage: "rectangle.stack")
                        .font(.system(size: compact ? 7 : 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("All-day events and reminders")
                .accessibilityLabel("\(special.count) all-day events and reminders")
            }
            if !loading && dayEvents.allSatisfy({ $0.isAllDay || $0.type.isReminder }) && (!compact || special.isEmpty) {
                Text(compact ? "Free" : "No timed\nevents")
                    .font(.system(size: compact ? 7 : 8))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, compact ? 1 : 3)
        .frame(width: compact ? 24 : 47, height: rowHeight, alignment: .topLeading)
    }

    private func dayTrack(_ date: Date, now: Date) -> some View {
        let day = CalendarTimelineGeometry.dayInterval(for: date)
        let topDay = CalendarTimelineGeometry.dayInterval(for: firstDay)
        let nextDay = CalendarTimelineGeometry.dayInterval(for: secondDay)
        let width = max(topDay.duration, nextDay.duration) / 3600 * pointsPerHour
        let dayEvents = visibleEvents(on: date)
        return CalendarTimelineTrack(
            day: day,
            events: dayEvents.filter { !$0.isAllDay && !$0.type.isReminder },
            selectedEvent: selectedEvent,
            now: now,
            width: width,
            height: rowHeight,
            compact: compact,
            pointsPerHour: pointsPerHour
        ) { select($0, on: date) }
    }

    private func visibleEvents(on date: Date) -> [EventModel] {
        let day = CalendarTimelineGeometry.dayInterval(for: date)
        return events.filter { event in
            guard !hideAllDayEvents || !event.isAllDay else { return false }
            if case .reminder(let completed) = event.type {
                return (!hideCompletedReminders || !completed) && event.start >= day.start && event.start < day.end
            }
            return event.start < day.end && (event.end > day.start || (event.start == event.end && event.start >= day.start))
        }
    }

    private func select(_ event: EventModel, on date: Date) {
        // Keep tomorrow's selected block visible when its row becomes the detail pane.
        selectedEvent = event
        coordinator.calendarDate = date
        scrollID += 1
    }

    private func selectedBlockIsShort(_ event: EventModel) -> Bool {
        let day = CalendarTimelineGeometry.dayInterval(for: firstDay)
        let width = CalendarTimelineGeometry.position(of: event.end, in: day, pointsPerHour: pointsPerHour)
            - CalendarTimelineGeometry.position(of: event.start, in: day, pointsPerHour: pointsPerHour)
        return width <= 35
    }

    private func navigate(by days: Int) {
        selectedEvent = nil
        coordinator.calendarDate = Calendar.current.date(byAdding: .day, value: days, to: firstDay)!
    }

    private func scrollToRelevantTime(proxy: ScrollViewProxy, now: Date) {
        let day = CalendarTimelineGeometry.dayInterval(for: firstDay)
        let target: Date
        if let selectedEvent, !selectedEvent.isAllDay && !selectedEvent.type.isReminder {
            target = selectedEvent.start
        } else if !autoScrollToNextEvent {
            target = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay)!
        } else if now >= day.start && now < day.end {
            target = now
        } else {
            target = visibleEvents(on: firstDay).first(where: { !$0.isAllDay && !$0.type.isReminder })?.start
                ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: firstDay)!
        }
        let hour = max(0, Int(CalendarTimelineGeometry.position(of: target, in: day, pointsPerHour: pointsPerHour)
                              / pointsPerHour) - 1)
        proxy.scrollTo(hour, anchor: .leading)
    }

    private func reload() async {
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        guard hasAccess else {
            events = []
            selectedEvent = nil
            loading = false
            return
        }
        loading = true
        let start = firstDay
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let result = await manager.events(from: start, to: end)
        guard !Task.isCancelled, start == firstDay else { return }
        events = result
        if let selectedEvent {
            self.selectedEvent = result.first(where: { $0.timelineID == selectedEvent.timelineID })
        }
        loading = false
    }

    private func clearHiddenSelection() {
        if let selectedEvent, !visibleEvents(on: firstDay).contains(where: { $0.timelineID == selectedEvent.timelineID }) {
            self.selectedEvent = nil
        }
    }

    private var permissionState: some View {
        VStack(spacing: compact ? 5 : 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: compact ? 16 : 24, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("Your days, at a glance")
                .font(.system(size: compact ? 10 : 13, weight: .medium))
            if !compact {
                Text("Allow calendar access to see your events here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Button(calendarAccess == .notDetermined ? "Connect Calendar" : (compact ? "Calendar Privacy Settings" : "Open Calendar Privacy Settings")) {
                requestCalendarAccess()
            }
            .buttonStyle(.bordered)
            .controlSize(compact ? .mini : .small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestCalendarAccess() {
        if calendarAccess == .notDetermined {
            Task {
                await manager.checkCalendarAuthorization()
                reloadID += 1
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct CalendarTimelineTrack: View {
    let day: DateInterval
    let events: [EventModel]
    let selectedEvent: EventModel?
    let now: Date
    let width: CGFloat
    let height: CGFloat
    let compact: Bool
    let pointsPerHour: Double
    let select: (EventModel) -> Void

    private var placements: [CalendarTimelineGeometry.Placement] {
        CalendarTimelineGeometry.layout(events.map { .init(id: $0.timelineID, start: $0.start, end: $0.end) }, in: day, pointsPerHour: pointsPerHour)
    }

    var body: some View {
        let layout = placements
        let laneCount = (layout.map(\.lane).max() ?? 0) + 1
        let laneHeight: CGFloat = compact ? 31 : (laneCount == 1 ? 57 : 34)
        let contentHeight = max(compact ? 34 : 60, CGFloat(laneCount) * laneHeight)
        let currentDay = now >= day.start && now < day.end
        let progress = CalendarTimelineGeometry.position(of: now, in: day, pointsPerHour: pointsPerHour)
        VStack(spacing: compact ? 2 : 3) {
            ZStack(alignment: .topLeading) {
                ForEach(CalendarTimelineGeometry.hourTicks(in: day), id: \.self) { tick in
                    Text(tickLabel(tick))
                        .font(.system(size: compact ? 7 : 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .offset(x: CalendarTimelineGeometry.position(of: tick, in: day, pointsPerHour: pointsPerHour) + 3)
                }
                if currentDay {
                    Text(now.formatted(.dateTime.hour().minute()))
                        .font(.system(size: compact ? 7 : 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, compact ? 3 : 4)
                        .background(.red, in: Capsule())
                        .offset(x: max(0, progress - (compact ? 15 : 19)))
                }
            }
            .frame(width: width, height: compact ? 10 : 13, alignment: .topLeading)
            ScrollView(.vertical, showsIndicators: laneCount > (compact ? 1 : 2)) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.035))
                        .frame(width: day.duration / 3600 * pointsPerHour)
                    Rectangle()
                        .fill(.white.opacity(0.025))
                        .frame(width: progress)
                        .allowsHitTesting(false)
                    ForEach(CalendarTimelineGeometry.hourTicks(in: day), id: \.self) { tick in
                        Rectangle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 1)
                            .offset(x: CalendarTimelineGeometry.position(of: tick, in: day, pointsPerHour: pointsPerHour))
                            .allowsHitTesting(false)
                    }
                    ForEach(layout) { placement in
                        if let event = events.first(where: { $0.timelineID == placement.id }) {
                            eventBlock(event, placement: placement, laneHeight: laneHeight)
                        }
                    }
                    if currentDay {
                        Rectangle()
                            .fill(.red)
                            .frame(width: 1.5)
                            .offset(x: progress)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: width, height: contentHeight, alignment: .topLeading)
            }
            .frame(height: height - (compact ? 12 : 17))
        }
        .frame(width: width, height: height)
    }

    private func eventBlock(_ event: EventModel, placement: CalendarTimelineGeometry.Placement, laneHeight: CGFloat) -> some View {
        let color = Color(event.calendar.color)
        let isSelected = event.timelineID == selectedEvent?.timelineID
        let blockHeight = laneHeight - 4
        return Button { select(event) } label: {
            ZStack(alignment: .leading) {
                Color.clear
                HStack(spacing: compact ? 3 : 5) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2)
                    if placement.width > (compact ? 23 : 35) {
                        VStack(alignment: .leading, spacing: laneHeight > 35 ? 3 : 1) {
                            Text(event.title)
                                .font(.system(size: compact ? 9 : (laneHeight > 35 ? 11 : 10), weight: .medium))
                                .lineLimit(1)
                            if let location = event.location, !location.isEmpty {
                                Text(location.replacingOccurrences(of: "\n", with: ", "))
                                    .font(.system(size: compact ? 7 : (laneHeight > 35 ? 9 : 8)))
                                    .foregroundStyle(color.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, compact ? 2 : (laneHeight > 35 ? 6 : 3))
                .padding(.horizontal, placement.width > (compact ? 23 : 35) ? (compact ? 3 : 6) : 0)
                .frame(width: max(1, placement.width), height: blockHeight, alignment: .leading)
                .background(color.opacity(isSelected ? 0.3 : 0.15), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? color : color.opacity(0.22), lineWidth: 1)
                }
                .clipped()
                .offset(x: placement.x - placement.hitX)
            }
            .frame(width: placement.hitWidth, height: blockHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(event.end < now && Calendar.current.isDateInToday(day.start) ? 0.55 : 1)
        .offset(x: placement.hitX, y: CGFloat(placement.lane) * laneHeight + 2)
        .help("\(event.title)\n\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))\(event.location.map { "\n\($0)" } ?? "")")
        .accessibilityLabel("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened)) to \(event.end.formatted(date: .omitted, time: .shortened)), \(event.location ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tickLabel(_ tick: Date) -> String {
        let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        let label = tick.formatted(format)
        let repeats = CalendarTimelineGeometry.hourTicks(in: day).filter {
            $0 < day.end && $0.formatted(format) == label
        }.count > 1
        return repeats ? "\(label) \(TimeZone.current.abbreviation(for: tick) ?? "")" : label
    }
}

private struct CalendarTimelineDetails: View {
    @Environment(\.openURL) private var openURL
    let event: EventModel
    let showIdentity: Bool
    let compact: Bool
    let close: () -> Void

    private var duration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, event.end.timeIntervalSince(event.start))) ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 5 : 12) {
            Button(action: close) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: compact ? 8 : 11, weight: .medium))
                    .frame(width: compact ? 18 : 28, height: compact ? 18 : 28)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to two days")
            .accessibilityLabel("Back to two days")
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                    if showIdentity || event.isAllDay || event.type.isReminder {
                        Text(event.title)
                            .font(.system(size: compact ? 9 : 11, weight: .semibold))
                            .lineLimit(compact ? 1 : nil)
                        if !compact, let location = event.location, !location.isEmpty {
                            Text(location).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    if compact {
                        Text(timeDescription + (!event.isAllDay && !event.type.isReminder ? " · \(duration)" : ""))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        if let location = event.location, !location.isEmpty {
                            Text(location.replacingOccurrences(of: "\n", with: ", "))
                                .font(.system(size: 8)).foregroundStyle(.white.opacity(0.6))
                        }
                        Label(event.calendar.title, systemImage: "circle.fill")
                            .font(.system(size: 8)).foregroundStyle(Color(event.calendar.color))
                    } else {
                        HStack(spacing: 8) {
                            Circle().fill(Color(event.calendar.color)).frame(width: 5, height: 5)
                            Text(event.calendar.title).lineLimit(1)
                            Text("·").foregroundStyle(.white.opacity(0.3))
                            Text(timeDescription)
                            if !event.isAllDay && !event.type.isReminder {
                                Text("· \(duration)").foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(notes.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: compact ? 8 : 10)).foregroundStyle(.white.opacity(0.6))
                            .textSelection(.enabled)
                    }
                    if !event.participants.isEmpty {
                        Label(event.participants.map { $0.name + ($0.isOrganizer ? " (organizer)" : "") }.joined(separator: ", "), systemImage: "person.2")
                            .font(.system(size: compact ? 8 : 10)).foregroundStyle(.white.opacity(0.6))
                    }
                    if let url = event.url {
                        Link(destination: url) {
                            Label(url.host ?? "Event link", systemImage: "link")
                                .font(.system(size: compact ? 8 : 10))
                        }
                    }
                    if let zone = event.timeZone, zone != .current {
                        Text("Event time zone: \(zone.identifier)").font(.system(size: compact ? 8 : 9)).foregroundStyle(.white.opacity(0.4))
                    }
                    Button(event.type.isReminder ? "Open in Reminders ↗" : "Open in Calendar ↗") {
                        if let url = event.calendarAppURL() { openURL(url) }
                    }
                    .font(.system(size: compact ? 8 : 10, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, compact ? 2 : 6)
            }
        }
        .padding(compact ? 5 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var timeDescription: String {
        if event.isAllDay { return "All-day" }
        if event.type.isReminder { return "Due \(event.start.formatted(date: .omitted, time: .shortened))" }
        let sameDay = Calendar.current.isDate(event.start, inSameDayAs: event.end)
        return "\(event.start.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)) – \(event.end.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened))"
    }
}

private extension EventModel {
    var timelineID: String { "\(id)-\(start.timeIntervalSince1970)" }
}
