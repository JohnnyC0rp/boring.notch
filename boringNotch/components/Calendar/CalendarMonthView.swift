import Defaults
import SwiftUI

/// A quiet date overview beside the player; selecting a day opens its timeline.
struct CalendarMonthView: View {
    var showTimeline: (() -> Void)? = nil
    var selectDate: ((Date) -> Void)? = nil
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.weekStartDay) private var weekStartDay
    @State private var displayedMonth = Date()

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartDay.firstWeekday
        return calendar
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 3) {
                header(today: context.date)
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        let weekday = (calendar.firstWeekday - 1 + index) % 7
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                    ForEach(Array(CalendarMonthGeometry.cells(containing: displayedMonth, calendar: calendar).enumerated()), id: \.offset) { _, date in
                        if let date {
                            dayButton(date, today: context.date)
                        } else {
                            Color.clear.frame(height: 15)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .frame(height: 130, alignment: .top)
            .onChange(of: calendar.startOfDay(for: context.date)) { oldDay, newDay in
                if calendar.isDate(displayedMonth, equalTo: oldDay, toGranularity: .month) {
                    displayedMonth = newDay
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func header(today: Date) -> some View {
        HStack(spacing: 5) {
            Text(displayedMonth.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(displayedMonth.formatted(.dateTime.year()))
                .font(.system(size: 10))
                .foregroundStyle(.gray)
            Spacer(minLength: 0)
            if !calendar.isDate(displayedMonth, equalTo: today, toGranularity: .month) {
                Button("Today") { displayedMonth = today }
                    .font(.system(size: 9, weight: .medium))
                    .help("Return to the current month")
            }
            monthArrow("chevron.left", offset: -1)
            monthArrow("chevron.right", offset: 1)
            if let showTimeline {
                Button(action: showTimeline) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 10))
                        .frame(width: 18, height: 19)
                }
                .accessibilityLabel("Show day timeline")
                .help("Show day timeline")
            }
        }
        .frame(height: 19)
    }

    private func monthArrow(_ symbol: String, offset: Int) -> some View {
        Button {
            let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
            displayedMonth = calendar.date(byAdding: .month, value: offset, to: start) ?? start
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.gray)
                .frame(width: 16, height: 19)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(offset < 0 ? "Previous month" : "Next month")
    }

    private func dayButton(_ date: Date, today: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: today)
        return Button {
            coordinator.calendarDate = date
            if let selectDate {
                selectDate(date)
            } else {
                withAnimation(.smooth(duration: 0.2)) { coordinator.currentView = .calendar }
            }
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 10, weight: isToday ? .bold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isToday ? .white : calendar.isDateInWeekend(date) ? Color.gray : Color.white.opacity(0.86))
                .frame(width: 21, height: 15)
                .background(isToday ? Color.red : .clear, in: RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .help("Show timeline for \(date.formatted(date: .abbreviated, time: .omitted))")
    }
}
