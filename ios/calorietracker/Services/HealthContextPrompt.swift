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
        let full = profile
        let profile = profile.effective(on: now, calendar: calendar)
        guard !profile.isEmpty else { return [] }
        let today = foods.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        var lines: [String] = ["", "## Health goals"]
        for kind in profile.entries {
            lines.append("- " + kind.promptGuidance)
        }
        for kind in profile.entries {
            guard let course = full.course(for: kind) else { continue }
            let tail = kind.courseTailDays > 0
                ? "; its food rules last through \(day(course.lastDay(tailDays: kind.courseTailDays, calendar: calendar)))" : ""
            lines.append("- \(kind.displayName) course: \(day(course.start)) to \(day(course.end))\(tail).")
        }
        let avoid = profile.avoidList
        if !avoid.isEmpty {
            lines.append("- Foods to avoid: \(listed(avoid.labels)). Never suggest a food that contains them, and say so when an option might.")
        }
        let interactions = Set(profile.avoidedFoodFlags.map(\.flag))
        let clashes = today.compactMap { entry -> String? in
            let hits = FoodFlag.allCases.filter { interactions.contains($0) && entry.foodFlags.contains($0) }
            return hits.isEmpty ? nil : "\(entry.name) (\(hits.map(\.promptName).joined(separator: ", ")))"
        }
        if !clashes.isEmpty {
            lines.append("- Logged today despite a medicine interaction: \(clashes.joined(separator: "; ")). Mention it if relevant.")
        }
        lines.append("- Advise within these goals. Never suggest starting, stopping or changing a medicine; for medical questions, suggest asking their doctor.")

        let rules = profile.rules
        let conflicts = profile.conflicts
        let estimated = estimatedNutrients.filter { nutrient in rules.contains { $0.nutrient == nutrient } }
            .map { $0.promptName.lowercased() }
        let note = estimated.isEmpty ? "" : " (\(listed(estimated)) \(estimated.count == 1 ? "is an estimate" : "are estimates"))"
        if !rules.isEmpty {
            lines.append(today.isEmpty ? "- Nothing logged yet today. Today's goals\(note):" : "- Today so far\(note):")
        }
        var shown = Set<OptionalNutrient>()
        for rule in rules where shown.insert(rule.nutrient).inserted {
            let conflicted = conflicts.contains { $0.nutrient == rule.nutrient }
            let value = total(rule.nutrient, in: today)
            if rule.direction == .steady {
                let usual = SteadyBand.usual(rule.nutrient, entries: foods, before: now, calendar: calendar)
                lines.append("  - " + steadyLine(for: rule.nutrient, value: value, usual: usual))
                continue
            }
            lines.append("  - " + line(for: rule, value: value, goal: goals.goal(for: rule.nutrient), conflicted: conflicted))
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

    private static func steadyLine(for nutrient: OptionalNutrient, value: Double, usual: Double?) -> String {
        let name = label(for: nutrient)
        let unit = nutrient.unit
        let amount = Int(value.rounded())
        guard let usual else { return "\(name): \(amount) \(unit) so far (keep steady; not enough history for their usual amount yet)" }
        let above = SteadyBand.isAbove(value, usual: usual, for: nutrient) ? ", above their usual range" : ""
        return "\(name): \(amount) \(unit) so far, usual \(Int(usual.rounded())) \(unit) a day (keep steady\(above))"
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

    private static func label(for nutrient: OptionalNutrient) -> String { nutrient.promptName }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Nutrients that come from AI estimates or reference tables rather than labels.
    private static let estimatedNutrients: [OptionalNutrient] = [.purines, .alcohol, .phosphorus, .oxalate, .tyramine]

    /// "a", "a and b", "a, b and c".
    private static func listed(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    private static func total(_ nutrient: OptionalNutrient, in entries: [FoodEntry]) -> Double {
        entries.total(of: nutrient)
    }
}
