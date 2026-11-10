import Foundation

/// Keeps the diary on today when a new day starts: reopening the app in the morning should
/// log water or breakfast to today, not to the day that was on screen the night before.
enum DiaryDayRollover {
    /// The day to show after the app was left at `leftAt` and is seen again at `now`.
    ///
    /// Same calendar day: `selected` is kept, so browsing back a few days survives a quick
    /// switch away. A later day: today, unless `onlyIfViewingThatDay` is set and `selected`
    /// was not `leftAt`'s day (used at midnight while open, when a past day being browsed stays).
    nonisolated static func selectedDate(
        _ selected: Date,
        leftAt: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        onlyIfViewingThatDay: Bool = false
    ) -> Date {
        guard !calendar.isDate(leftAt, inSameDayAs: now) else { return selected }
        if onlyIfViewingThatDay, !calendar.isDate(selected, inSameDayAs: leftAt) { return selected }
        return now
    }
}
