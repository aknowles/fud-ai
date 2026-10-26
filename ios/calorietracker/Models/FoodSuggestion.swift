import Foundation

/// When the user's next usual meal is, learned from when they log breakfast, lunch and dinner.
struct UsualMeal: Equatable {
    let mealType: MealType
    /// Minutes from now until the meal's usual time today.
    let minutesAway: Int
    /// Average calories the user logs for this meal.
    let typicalCalories: Int

    /// Days of history to learn from, and how many days a meal must appear on to count.
    static let windowDays = 14
    static let minimumDays = 3

    static func next(after now: Date, entries: [FoodEntry], calendar: Calendar = .current) -> UsualMeal? {
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)) else { return nil }
        let today = calendar.startOfDay(for: now)
        let history = entries.filter { $0.timestamp >= start && $0.timestamp < today }
        let nowMinute = minuteOfDay(now, calendar: calendar)

        let candidates: [UsualMeal] = [MealType.breakfast, .lunch, .dinner].compactMap { meal in
            let byDay = Dictionary(grouping: history.filter { $0.mealType == meal }) { calendar.startOfDay(for: $0.timestamp) }
            guard byDay.count >= minimumDays else { return nil }
            // Each day's first entry for the meal marks when it started.
            let starts = byDay.values.compactMap { $0.map(\.timestamp).min() }.map { minuteOfDay($0, calendar: calendar) }
            let usualMinute = starts.reduce(0, +) / starts.count
            guard usualMinute > nowMinute else { return nil }
            let calories = byDay.values.map { $0.reduce(0) { $0 + $1.calories } }
            return UsualMeal(mealType: meal, minutesAway: usualMinute - nowMinute,
                             typicalCalories: calories.reduce(0, +) / calories.count)
        }
        return candidates.min { $0.minutesAway < $1.minutesAway }
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// What the suggestion screen knows about the user's day.
struct SuggestionContext: Equatable {
    var caloriesLeft: Int
    var nextMeal: UsualMeal?
    var isFasting: Bool

    /// Waiting wins during a fast, or when the next usual meal is close and eating now
    /// would leave too little for it.
    var prefersWaiting: Bool {
        if isFasting { return true }
        guard let nextMeal, nextMeal.minutesAway <= Self.closeMinutes else { return false }
        return caloriesLeft - nextMeal.typicalCalories < Self.spareCalories
    }

    static let closeMinutes = 90
    static let spareCalories = 150
}

/// A goal an option would break if eaten now.
enum SuggestionFlag: Equatable, Hashable {
    case calories
    case over(OptionalNutrient)
}

/// One choice on the suggestion screen, with the day's totals after eating it.
struct SuggestionOption: Identifiable {
    let id = UUID()
    /// The entry that is shown and, if picked, reviewed and logged unchanged.
    let entry: FoodEntry
    let reason: String
    let tweak: String?
    var flags: [SuggestionFlag] = []
    var caloriesAfter: Int = 0
    var limitsAfter: [(nutrient: OptionalNutrient, amount: Double, goal: Int)] = []
}

enum SuggestionRanking {
    /// Fills in each option's after-eating totals and flags against the calorie goal and
    /// every limit in the health profile.
    static func evaluate(
        _ options: [SuggestionOption],
        today: [FoodEntry],
        calorieGoal: Int,
        goals: OptionalNutrientGoals,
        profile: HealthProfile
    ) -> [SuggestionOption] {
        let limits = orderedLimits(in: profile)
        let eaten = today.reduce(0) { $0 + $1.calories }
        return options.map { option in
            var evaluated = option
            evaluated.caloriesAfter = eaten + option.entry.calories
            evaluated.flags = calorieGoal > 0 && evaluated.caloriesAfter > calorieGoal ? [.calories] : []
            evaluated.limitsAfter = limits.map { nutrient in
                let amount = amountOf(nutrient, in: today) + amountOf(nutrient, in: [option.entry])
                let goal = goals.goal(for: nutrient)
                if goal > 0, amount > Double(goal) { evaluated.flags.append(.over(nutrient)) }
                return (nutrient, amount, goal)
            }
            return evaluated
        }
    }

    /// The AI's order, with options that break a goal moved after those that do not.
    static func ranked(_ options: [SuggestionOption]) -> [SuggestionOption] {
        options.filter { $0.flags.isEmpty } + options.filter { !$0.flags.isEmpty }
    }

    /// A small saved food to tide the user over while waiting: at most `maxCalories`,
    /// most protein and fiber per calorie.
    static func bridgeSnack(from saved: [FoodEntry], maxCalories: Int = 150) -> FoodEntry? {
        func value(_ entry: FoodEntry) -> Double {
            (entry.protein + (entry.fiber ?? 0)) / Double(max(entry.calories, 1))
        }
        return saved
            .filter { $0.calories > 0 && $0.calories <= maxCalories }
            .max { lhs, rhs in
                value(lhs) == value(rhs) ? lhs.calories > rhs.calories : value(lhs) < value(rhs)
            }
    }

    /// Limit-style nutrients from the profile, in profile order.
    static func orderedLimits(in profile: HealthProfile) -> [OptionalNutrient] {
        var seen = Set<OptionalNutrient>()
        return profile.rules.filter { $0.direction == .limit && seen.insert($0.nutrient).inserted }.map(\.nutrient)
    }

    static func amountOf(_ nutrient: OptionalNutrient, in entries: [FoodEntry]) -> Double {
        switch nutrient {
        case .addedSugar: entries.reduce(0) { $0 + ($1.addedSugar ?? 0) }
        case .sodium, .potassium, .calcium, .magnesium: DASHScorecard.total(nutrient, in: entries)
        default: entries.reduce(0) { $0 + ($1.supplementalNutrients[nutrient.rawValue] ?? 0) }
        }
    }
}
