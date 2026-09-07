import Defaults
import SwiftUI

struct HomeCalendarView: View {
    @Default(.showMonthOnHome) private var showMonth

    var body: some View {
        Group {
            if showMonth {
                CalendarMonthView(showTimeline: { showMonth = false }, selectDate: { _ in showMonth = false })
            } else {
                CalendarTimelineView(compact: true, showMonth: { showMonth = true })
            }
        }
        .frame(height: 130, alignment: .top)
    }
}
