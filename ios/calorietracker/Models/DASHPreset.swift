import Foundation

/// The DASH (Dietary Approaches to Stop Hypertension) daily targets this fork tracks.
///
/// Sodium is a limit; potassium, calcium and magnesium are targets. The values are the
/// published DASH eating-plan figures for a 2,000 kcal diet (NIH/NHLBI). No new data is
/// stored: the preset only writes the existing per-nutrient goals in `OptionalNutrientGoals`.
enum DASHPreset {
    enum SodiumVariant: String, CaseIterable, Identifiable {
        /// The standard DASH sodium limit.
        case standard
        /// The lower-sodium DASH variant.
        case lower

        var id: String { rawValue }

        var sodiumMilligrams: Int {
            switch self {
            case .standard: 2_300
            case .lower: 1_500
            }
        }

        var displayName: String {
            switch self {
            case .standard: String(localized: "DASH (2,300 mg sodium)")
            case .lower: String(localized: "Lower-sodium DASH (1,500 mg)")
            }
        }
    }

    static let potassiumMilligrams = 4_700
    static let calciumMilligrams = 1_250
    static let magnesiumMilligrams = 500

    /// The four nutrients the scorecard reads, in display order.
    static let nutrients: [OptionalNutrient] = [.sodium, .potassium, .calcium, .magnesium]

    static func goal(for nutrient: OptionalNutrient, sodium variant: SodiumVariant) -> Int? {
        switch nutrient {
        case .sodium: variant.sodiumMilligrams
        case .potassium: potassiumMilligrams
        case .calcium: calciumMilligrams
        case .magnesium: magnesiumMilligrams
        default: nil
        }
    }

    /// `goals` with the four DASH values applied; every other goal is left as it was.
    static func applying(_ variant: SodiumVariant, to goals: OptionalNutrientGoals) -> OptionalNutrientGoals {
        var updated = goals
        for nutrient in nutrients {
            if let value = goal(for: nutrient, sodium: variant) {
                updated.setGoal(value, for: nutrient)
            }
        }
        return updated
    }

    /// The variant whose four values `goals` currently hold exactly, or nil.
    static func appliedVariant(in goals: OptionalNutrientGoals) -> SodiumVariant? {
        SodiumVariant.allCases.first { variant in
            nutrients.allSatisfy { goals.goal(for: $0) == goal(for: $0, sodium: variant) }
        }
    }
}

/// Day-level DASH numbers for the scorecard: one day plus a rolling average over the
/// seven days ending on that day. Days without any food entries do not count toward
/// the average, so a week with three logged days averages those three.
struct DASHScorecard: Equatable {
    struct Line: Equatable, Identifiable {
        let nutrient: OptionalNutrient
        let today: Double
        let weeklyAverage: Double
        let goal: Int
        /// False when no food was logged that day (or in the week), so an empty day never
        /// "meets" a limit just by being empty.
        let todayLogged: Bool
        let weekLogged: Bool

        var id: String { nutrient.rawValue }
        var isLimit: Bool { nutrient.goalStyle == "limit" }

        /// True when the day meets the DASH rule for this nutrient (under a limit, at or above a target).
        var todayMeetsGoal: Bool { todayLogged && meets(today) }
        var weekMeetsGoal: Bool { weekLogged && meets(weeklyAverage) }

        private func meets(_ value: Double) -> Bool {
            guard goal > 0 else { return false }
            return isLimit ? value <= Double(goal) : value >= Double(goal)
        }
    }

    let lines: [Line]
    let loggedDaysInWeek: Int

    static let windowDays = 7

    var todayScore: Int { lines.filter(\.todayMeetsGoal).count }
    var weekScore: Int { lines.filter(\.weekMeetsGoal).count }

    @MainActor
    init(foodStore: FoodStore, date: Date, goals: OptionalNutrientGoals, calendar: Calendar = .current) {
        self.init(date: date, goals: goals, calendar: calendar) { foodStore.entries(for: $0) }
    }

    /// The same scorecard over a plain entry list, for callers that hold entries rather than the store.
    init(entries: [FoodEntry], date: Date, goals: OptionalNutrientGoals, calendar: Calendar = .current) {
        self.init(date: date, goals: goals, calendar: calendar) { day in
            entries.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
        }
    }

    private init(date: Date, goals: OptionalNutrientGoals, calendar: Calendar, entriesOn: (Date) -> [FoodEntry]) {
        let day = calendar.startOfDay(for: date)
        let days = (0..<Self.windowDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: day) }
        var totals: [OptionalNutrient: Double] = [:]
        var loggedDays = 0
        var todayTotals: [OptionalNutrient: Double] = [:]
        var todayLogged = false

        for (offset, windowDay) in days.enumerated() {
            let entries = entriesOn(windowDay)
            if entries.isEmpty { continue }
            loggedDays += 1
            for nutrient in DASHPreset.nutrients {
                let total = Self.total(nutrient, in: entries)
                totals[nutrient, default: 0] += total
                if offset == 0 { todayTotals[nutrient] = total }
            }
            if offset == 0 { todayLogged = true }
        }

        let divisor = Double(max(loggedDays, 1))
        lines = DASHPreset.nutrients.map { nutrient in
            Line(
                nutrient: nutrient,
                today: todayTotals[nutrient] ?? 0,
                weeklyAverage: (totals[nutrient] ?? 0) / divisor,
                goal: goals.goal(for: nutrient),
                todayLogged: todayLogged,
                weekLogged: loggedDays > 0
            )
        }
        loggedDaysInWeek = loggedDays
    }

    nonisolated static func total(_ nutrient: OptionalNutrient, in entries: [FoodEntry]) -> Double {
        switch nutrient {
        case .sodium: entries.reduce(0) { $0 + ($1.sodium ?? 0) }
        case .potassium: entries.reduce(0) { $0 + ($1.potassium ?? 0) }
        case .calcium: entries.reduce(0) { $0 + ($1.calcium ?? 0) }
        case .magnesium: entries.reduce(0) { $0 + ($1.magnesium ?? 0) }
        default: 0
        }
    }
}
