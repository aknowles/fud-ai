import Foundation

/// "Keep it steady" goals compare a day with the user's own usual intake instead of a fixed
/// number. Warfarin is the case: vitamin K changes its effect, so the advice is to eat about
/// the same amount each day, not to avoid greens.
enum SteadyBand {
    /// Days of history before the day in question, and how many must have food logged.
    static let windowDays = 14
    static let minimumDays = 3
    /// How far a day may drift from the usual amount: half of it, but at least the floor.
    static let relativeSwing = 0.5
    static let minimumSwing: [OptionalNutrient: Double] = [.vitaminK: 40]

    /// The average daily amount over logged days in the window before `day`, or nil when
    /// there is not enough history.
    static func usual(
        _ nutrient: OptionalNutrient,
        entries: [FoodEntry],
        before day: Date,
        calendar: Calendar = .current
    ) -> Double? {
        let end = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: end) else { return nil }
        let byDay = Dictionary(grouping: entries.filter { $0.timestamp >= start && $0.timestamp < end }) {
            calendar.startOfDay(for: $0.timestamp)
        }
        guard byDay.count >= minimumDays else { return nil }
        return byDay.values.map { $0.total(of: nutrient) }.reduce(0, +) / Double(byDay.count)
    }

    static func range(around usual: Double, for nutrient: OptionalNutrient) -> ClosedRange<Double> {
        let swing = max(usual * relativeSwing, minimumSwing[nutrient] ?? 0)
        return max(0, usual - swing)...(usual + swing)
    }

    /// True when `amount` is above the usual range. A day under it may simply not be over yet,
    /// so only going over counts during the day.
    static func isAbove(_ amount: Double, usual: Double, for nutrient: OptionalNutrient) -> Bool {
        amount > range(around: usual, for: nutrient).upperBound
    }
}
