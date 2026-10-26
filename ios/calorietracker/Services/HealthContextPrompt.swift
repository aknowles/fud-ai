import Foundation

/// The fork's health section of the Coach and voice prompts: each active health-profile
/// entry with its guidance, its goals against today's totals, the DASH score, and any
/// conflicts between entries, so advice weighs them without the user asking.
enum HealthContextPrompt {
    static func lines(
        foods: [FoodEntry],
        goals: OptionalNutrientGoals = .current,
        profile: HealthProfile = HealthProfileStore.shared.profile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        guard !profile.entries.isEmpty else { return [] }
        let today = foods.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        var lines: [String] = ["", "## Health goals"]
        for kind in profile.entries {
            lines.append("- " + kind.promptGuidance)
        }
        lines.append("- Advise within these goals. Never suggest starting, stopping or changing a medicine; for medical questions, suggest asking their doctor.")

        let rules = profile.rules
        let conflicts = profile.conflicts
        let estimated = rules.contains { $0.nutrient == .purines || $0.nutrient == .alcohol }
        let note = estimated ? " (purines and alcohol are estimates)" : ""
        lines.append(today.isEmpty ? "- Nothing logged yet today. Today's goals\(note):" : "- Today so far\(note):")
        var listed = Set<OptionalNutrient>()
        for rule in rules where listed.insert(rule.nutrient).inserted {
            let conflicted = conflicts.contains { $0.nutrient == rule.nutrient }
            lines.append("  - " + line(for: rule, value: total(rule.nutrient, in: today),
                                       goal: goals.goal(for: rule.nutrient), conflicted: conflicted))
        }

        if profile.contains(.dash) {
            let scorecard = DASHScorecard(entries: foods, date: now, goals: goals, calendar: calendar)
            let count = scorecard.lines.count
            let plan = DASHPreset.appliedVariant(in: goals).map { " (\($0.sodiumMilligrams) mg sodium plan)" } ?? ""
            lines.append("- DASH score\(plan): today \(scorecard.todayScore) of \(count) goals met; 7-day average \(scorecard.weekScore) of \(count) over \(scorecard.loggedDaysInWeek) logged days.")
        }

        for conflict in conflicts {
            lines.append("- Conflict on \(label(for: conflict.nutrient).lowercased()): \(conflict.raisedBy.joined(separator: " and ")) raises it, \(conflict.limitedBy.joined(separator: " and ")) limits it. Do not pick a side; point it out and suggest the user ask their doctor which goal applies.")
        }
        return lines
    }

    private static func line(for rule: HealthRule, value: Double, goal: Int, conflicted: Bool) -> String {
        let amount = Int(value.rounded())
        let name = label(for: rule.nutrient)
        let unit = rule.nutrient.unit
        if conflicted { return "\(name): \(amount) \(unit), goal \(goal) \(unit) (entries disagree)" }
        var text = "\(name): \(amount) of \(goal) \(unit) \(rule.direction == .limit ? "limit" : "target")"
        if goal > 0 {
            if rule.direction == .limit, value > Double(goal) { text += " (over)" }
            if rule.direction == .target, value >= Double(goal) { text += " (met)" }
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
        case .sodium, .potassium, .calcium, .magnesium: DASHScorecard.total(nutrient, in: entries)
        default: entries.reduce(0) { $0 + ($1.supplementalNutrients[nutrient.rawValue] ?? 0) }
        }
    }
}
