import Foundation

/// The fork's health section of the Coach and voice prompts: gout limits, sodium and the
/// DASH preset, each with today's totals, so advice weighs them without the user asking.
///
/// This first version reads the existing `OptionalNutrientGoals`; the health profile
/// will replace that source and keep this one entry point.
enum HealthContextPrompt {
    static func lines(
        foods: [FoodEntry],
        goals: OptionalNutrientGoals = .current,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let today = foods.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        var lines: [String] = [
            "",
            "## Health goals (gout and blood pressure)",
            "- The user manages gout. Favor low-purine choices, and name the purine load when comparing foods or suggesting meals. Alcohol (beer and spirits most) and added sugar (sweetened drinks) are the other dietary triggers.",
            "- Advise within these goals. Never suggest starting, stopping or changing a medicine; for medical questions, suggest asking their doctor.",
        ]

        lines.append(today.isEmpty
            ? "- Nothing logged yet today. Today's limits (purines and alcohol are estimates):"
            : "- Today so far (purines and alcohol are estimates):")
        for nutrient in [OptionalNutrient.purines, .alcohol, .addedSugar, .sodium] {
            lines.append("  - " + line(for: nutrient, value: total(nutrient, in: today), goal: goals.goal(for: nutrient)))
        }

        guard let variant = DASHPreset.appliedVariant(in: goals) else {
            lines.append("- DASH eating plan: off.")
            return lines
        }
        let scorecard = DASHScorecard(entries: foods, date: now, goals: goals, calendar: calendar)
        let count = scorecard.lines.count
        lines.append("- DASH eating plan: on (\(variant.sodiumMilligrams) mg sodium). Today \(scorecard.todayScore) of \(count) DASH goals met; 7-day average \(scorecard.weekScore) of \(count) over \(scorecard.loggedDaysInWeek) logged days.")
        for dashLine in scorecard.lines where dashLine.nutrient != .sodium {
            lines.append("  - " + line(for: dashLine.nutrient, value: dashLine.today, goal: dashLine.goal))
        }
        return lines
    }

    private static func line(for nutrient: OptionalNutrient, value: Double, goal: Int) -> String {
        let isLimit = nutrient.goalStyle == "limit"
        let amount = Int(value.rounded())
        var text = "\(label(for: nutrient)): \(amount) of \(goal) \(nutrient.unit) \(isLimit ? "limit" : "target")"
        if goal > 0 {
            if isLimit, value > Double(goal) { text += " (over)" }
            if !isLimit, value >= Double(goal) { text += " (met)" }
        }
        return text
    }

    /// Fixed English names, so the prompt does not change with the app language.
    private static func label(for nutrient: OptionalNutrient) -> String {
        switch nutrient {
        case .purines: "Purines"
        case .alcohol: "Alcohol"
        case .addedSugar: "Added sugar"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .magnesium: "Magnesium"
        default: nutrient.rawValue
        }
    }

    private static func total(_ nutrient: OptionalNutrient, in entries: [FoodEntry]) -> Double {
        switch nutrient {
        case .addedSugar: entries.reduce(0) { $0 + ($1.addedSugar ?? 0) }
        case .sodium: DASHScorecard.total(.sodium, in: entries)
        default: entries.reduce(0) { $0 + ($1.supplementalNutrients[nutrient.rawValue] ?? 0) }
        }
    }
}
