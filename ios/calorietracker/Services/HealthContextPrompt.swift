import Foundation

/// The fork's health section of the Coach and voice prompts: each active health-profile
/// entry with its guidance, its goals against today's totals, the DASH score, and any
/// conflicts between entries, so advice weighs them without the user asking.
enum HealthContextPrompt {
    static func lines(
        foods: [FoodEntry],
        goals: OptionalNutrientGoals = .current,
        profile: HealthProfile = HealthProfileStore.shared.profile,
        plan: [PlannedMeal] = MealPlanStore.shared.meals,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let planned = planLines(plan: plan, foods: foods, profile: profile.effective(on: now, calendar: calendar),
                                now: now, calendar: calendar)
        let full = profile
        let profile = profile.effective(on: now, calendar: calendar)
        guard !profile.isEmpty else { return planned }
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
        lines += doseLines(profile: profile, full: full, today: today, now: now, calendar: calendar)
        lines += sensitivityLines(profile.sensitivityList, today: today)
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
        return lines + planned
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

    private static func sensitivityLines(_ sensitivities: Sensitivities, today: [FoodEntry]) -> [String] {
        guard !sensitivities.isEmpty else { return [] }
        var groups: [String] = []
        for level in SensitivityLevel.allCases {
            var labels = SensitivityKind.allCases.filter { sensitivities.level(for: $0) == level }.map(\.label)
            labels += sensitivities.custom.filter { $0.level == level }.map(\.term)
            if level == .avoid || level == .limit, let cutoff = sensitivities.caffeineCutoffMinutes,
               sensitivities.level(for: .caffeine) == level, let index = labels.firstIndex(of: "caffeine") {
                labels[index] = "caffeine after \(clock(minutes: cutoff))"
            }
            guard !labels.isEmpty else { continue }
            let verb = switch level {
            case .avoid: "avoid"
            case .limit: "go easy on"
            case .note: "note"
            }
            groups.append("\(verb) \(listed(labels))")
        }
        var lines = ["- Food sensitivities (not allergies): \(groups.joined(separator: "; ")). Weigh them when suggesting food."]
        let hits = today.compactMap { entry -> String? in
            let found = sensitivities.matches(for: entry).filter { $0.level != .note }
            return found.isEmpty ? nil : "\(entry.name) (\(found.map(\.label).joined(separator: ", ")))"
        }
        if !hits.isEmpty { lines.append("- Logged today with a sensitivity: \(hits.joined(separator: "; ")).") }
        return lines
    }

    /// Planned meals for the rest of today and tomorrow that are not logged yet.
    private static func planLines(plan: [PlannedMeal], foods: [FoodEntry], profile: HealthProfile, now: Date,
                                  calendar: Calendar) -> [String] {
        let limits = SuggestionRanking.orderedLimits(in: profile)
        var lines: [String] = []
        for (offset, label) in [(0, "Today"), (1, "Tomorrow")] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let dayFoods = foods.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
            for meal in plan.filter({ calendar.isDate($0.day, inSameDayAs: day) && !$0.isLogged(in: dayFoods) })
                .sorted(by: { (MealSlotTime.defaults[$0.mealType] ?? 0) < (MealSlotTime.defaults[$1.mealType] ?? 0) }) {
                let source = meal.source.map { " (\($0))" } ?? ""
                var text = "- \(label), \(meal.mealType.rawValue)\(source): "
                if let chosen = meal.chosen {
                    let amounts = limits.compactMap { nutrient -> String? in
                        chosen.entry.amount(of: nutrient).map { "\(nutrient.promptName.lowercased()) \(Int($0.rounded())) \(nutrient.unit)" }
                    }
                    text += "planned \(chosen.entry.name) (\(([String(chosen.entry.calories) + " kcal"] + amounts).joined(separator: ", ")))"
                }
                let others = meal.options.filter { $0.id != meal.chosen?.id }.map(\.entry.name)
                if !others.isEmpty { text += "\(meal.chosen == nil ? "options" : "; other options"): \(others.joined(separator: ", "))" }
                lines.append(text + ".")
            }
        }
        return lines.isEmpty ? [] : ["", "## Meal plan"] + lines + ["- Weigh what is still planned when advising on food now."]
    }

    private static func doseLines(profile: HealthProfile, full: HealthProfile, today: [FoodEntry], now: Date,
                                  calendar: Calendar) -> [String] {
        var lines: [String] = []
        let windows = DoseTiming.upcomingWindows(on: now, after: calendar.startOfDay(for: now), profile: full, calendar: calendar)
        for kind in profile.entries where kind.supportsDoseTimes {
            guard let schedule = profile.doseSchedule(for: kind), !schedule.times.isEmpty else { continue }
            let doses = schedule.times.map { clock(minutes: $0) }.joined(separator: ", ")
            let rules = profile.doseWindows(for: kind).map { rule -> String in
                let ranges = windows.filter { $0.kind == kind && $0.rule == rule }
                    .map { "\(clock($0.start, calendar)) to \(clock($0.end, calendar))" }
                return "keep \(rule.foods.promptName) out of \(ranges.joined(separator: " and "))"
            }
            lines.append("- \(kind.displayName) doses at \(doses). Today: \(rules.joined(separator: "; ")).")
        }
        let clashes = today.flatMap { entry in
            DoseTiming.conflicts(for: entry, profile: full, calendar: calendar).map { conflict in
                let gap = abs(conflict.minutesFromDose)
                let side = conflict.minutesFromDose < 0 ? "before" : "after"
                return "\(entry.name) at \(clock(entry.timestamp, calendar)), \(gap) min \(side) the \(clock(conflict.dose, calendar)) dose"
            }
        }
        if !clashes.isEmpty {
            lines.append("- Logged inside a dose window today: \(clashes.joined(separator: "; ")). Mention it if relevant.")
        }
        return lines
    }

    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func clock(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

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
