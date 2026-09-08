//
//  CalendarSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import EventKit
import SwiftUI

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.calendarWeekView) var calendarWeekView
    @Default(.weekStartDay) var weekStartDay

    var body: some View {
        Form {
            Defaults.Toggle(key: .showCalendar) {
                Text("Show calendar")
            }
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("Hide completed reminders")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("Hide all-day events")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("Auto-scroll to next event")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("Always show full event titles")
            }
            Defaults.Toggle(key: .joinMeetingOnEventTap) {
                Text("Join meeting when tapping an event")
            }
            Defaults.Toggle(key: .calendarWeekView) {
                Text("Weekly view")
            }
            if calendarWeekView {
                Picker("Week starts on", selection: $weekStartDay) {
                    ForEach(WeekStartDay.allCases) { day in
                        Text(day.localizedString).tag(day)
                    }
                }
            }
            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Calendar access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Calendar Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    calendarPicker(calendarManager.eventCalendars)
                    Button("Refresh Calendars", systemImage: "arrow.clockwise") {
                        Task { await calendarManager.reloadCalendarAndReminderLists() }
                    }
                    Text("Includes calendars from every account available to Apple Calendar. Selection applies to both calendar views.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Reminder access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Reminder Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    calendarPicker(calendarManager.reminderLists)
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Calendar")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }

    @ViewBuilder
    private func calendarPicker(_ calendars: [CalendarModel]) -> some View {
        if calendars.isEmpty {
            Text("No calendars available.")
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Text("\(calendars.filter { calendarManager.getCalendarSelected($0) }.count) of \(calendars.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") {
                    Task { await calendarManager.setCalendarsSelected(calendars, isSelected: true) }
                }
                Button("Deselect All") {
                    Task { await calendarManager.setCalendarsSelected(calendars, isSelected: false) }
                }
            }
            .controlSize(.small)

            let groups = Dictionary(grouping: calendars, by: \.account)
            ForEach(groups.keys.sorted(), id: \.self) { account in
                VStack(alignment: .leading, spacing: 12) {
                    Text(account)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach((groups[account] ?? []).sorted {
                        $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }, id: \.id) { calendar in
                        Toggle(isOn: Binding(
                            get: { calendarManager.getCalendarSelected(calendar) },
                            set: { isSelected in
                                Task { await calendarManager.setCalendarSelected(calendar, isSelected: isSelected) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(nsColor: calendar.color))
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(calendar.title)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(calendar.title)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
