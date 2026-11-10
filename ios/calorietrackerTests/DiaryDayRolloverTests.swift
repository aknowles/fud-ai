import Foundation
import Testing
@testable import calorietracker

/// Reopening the app on a new day lands on today, so a morning log is not filed under yesterday.
struct DiaryDayRolloverTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func returningTheNextMorningMovesFromYesterdayToToday() {
        let result = DiaryDayRollover.selectedDate(date(9, 22), leftAt: date(9, 22), now: date(10, 7), calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: date(10, 7)))
    }

    @Test func returningTheNextMorningAlsoLeavesAnOlderBrowsedDay() {
        let result = DiaryDayRollover.selectedDate(date(5, 12), leftAt: date(9, 22), now: date(10, 7), calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: date(10, 7)))
    }

    @Test func returningTheSameDayKeepsABrowsedPastDay() {
        let result = DiaryDayRollover.selectedDate(date(7, 12), leftAt: date(10, 8), now: date(10, 9), calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: date(7, 12)))
    }

    @Test func midnightWhileOpenFollowsTodayButNotABrowsedPastDay() {
        let followed = DiaryDayRollover.selectedDate(date(9, 23), leftAt: date(9, 23), now: date(10, 0),
                                                     calendar: calendar, onlyIfViewingThatDay: true)
        #expect(calendar.isDate(followed, inSameDayAs: date(10, 0)))

        let kept = DiaryDayRollover.selectedDate(date(6, 12), leftAt: date(9, 23), now: date(10, 0),
                                                 calendar: calendar, onlyIfViewingThatDay: true)
        #expect(calendar.isDate(kept, inSameDayAs: date(6, 12)))
    }
}
