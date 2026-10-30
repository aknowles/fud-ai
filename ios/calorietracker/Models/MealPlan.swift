import Foundation
import Observation

/// One food that could be eaten at a planned meal, with the allergens and notable ingredients
/// the AI listed and why it ranks where it does.
struct PlannedOption: Codable, Identifiable {
    var id = UUID()
    var entry: FoodEntry
    var contains: [String] = []
    var reason: String?
    /// Sides and components served with the dish, e.g. ["rice pilaf", "green beans"];
    /// the entry's nutrition covers them.
    var includes: [String]?
}

/// A meal known ahead: one planned food (a recipe or saved meal) or a set of options (a day
/// on a cafe menu), with the one the user or the AI picked.
struct PlannedMeal: Codable, Identifiable {
    var id = UUID()
    /// Start of the planned day.
    var day: Date
    var mealType: MealType
    /// Where it comes from, e.g. "Work cafe" or "Recipe".
    var source: String?
    var options: [PlannedOption]
    /// The user's own pick.
    var chosenID: UUID?
    /// The AI's suggestion, counted until the user picks.
    var suggestedID: UUID?
    /// Repeats on this weekday every week ("Taco Tuesday"); the store fills in the coming
    /// weeks' copies from this meal.
    var repeatsWeekly: Bool?
    /// The repeating meal this one was copied from.
    var repeatOf: UUID?
    /// Days a copy of this repeating meal was removed on, so they are not filled in again.
    var skippedDays: [Date]?

    var isRepeating: Bool { repeatsWeekly == true }
    /// True for a repeating meal and its copies.
    var isPartOfRepeat: Bool { isRepeating || repeatOf != nil }

    /// A copy of this meal on `day`, with fresh option IDs, the same pick, and the foods at
    /// the usual time for the meal.
    func occurrence(on day: Date, entries: [FoodEntry], calendar: Calendar = .current) -> PlannedMeal {
        let time = MealSlotTime.time(for: mealType, on: day, entries: entries, calendar: calendar)
        var ids: [UUID: UUID] = [:]
        let copies = options.map { option -> PlannedOption in
            var copy = option
            copy.id = UUID()
            copy.entry = option.entry.duplicatedForLogging(at: time, mealType: mealType)
            ids[option.id] = copy.id
            return copy
        }
        return PlannedMeal(day: calendar.startOfDay(for: day), mealType: mealType, source: source, options: copies,
                           chosenID: chosenID.flatMap { ids[$0] }, suggestedID: suggestedID.flatMap { ids[$0] }, repeatOf: id)
    }

    /// The option the plan counts: the user's pick, else the suggestion; a single-option meal
    /// is always picked.
    var chosen: PlannedOption? {
        options.first { $0.id == chosenID } ?? options.first { $0.id == suggestedID } ?? (options.count == 1 ? options.first : nil)
    }

    /// True when `chosen` is only the AI's suggestion.
    var isSuggestion: Bool {
        options.count > 1 && !options.contains { $0.id == chosenID } && chosen != nil
    }

    /// True when the diary already has the chosen food (or any option) logged that day.
    func isLogged(in dayEntries: [FoodEntry]) -> Bool {
        let names = Set(options.map { $0.entry.name.lowercased() })
        return dayEntries.contains { names.contains($0.name.lowercased()) }
    }
}

/// Usual start time of each meal, learned from the diary, for dose windows and ordering.
enum MealSlotTime {
    static let defaults: [MealType: Int] = [.breakfast: 8 * 60, .lunch: 12 * 60 + 30, .dinner: 18 * 60 + 30,
                                            .snack: 15 * 60, .other: 12 * 60]

    static func usualMinute(for meal: MealType, entries: [FoodEntry], before day: Date, calendar: Calendar = .current) -> Int {
        let end = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .day, value: -UsualMeal.windowDays, to: end) else { return defaults[meal] ?? 720 }
        let byDay = Dictionary(grouping: entries.filter { $0.mealType == meal && $0.timestamp >= start && $0.timestamp < end }) {
            calendar.startOfDay(for: $0.timestamp)
        }
        guard byDay.count >= UsualMeal.minimumDays else { return defaults[meal] ?? 720 }
        let minutes = byDay.values.compactMap { $0.map(\.timestamp).min() }.map { date -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        return minutes.reduce(0, +) / minutes.count
    }

    static func time(for meal: MealType, on day: Date, entries: [FoodEntry], calendar: Calendar = .current) -> Date {
        let minute = usualMinute(for: meal, entries: entries, before: day, calendar: calendar)
        return calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: day)) ?? day
    }
}

/// A change of pick at one planned meal that brings a day back under a limit.
struct PlanSwap: Equatable {
    let mealID: UUID
    let fromName: String
    let to: UUID
    let toName: String
    let nutrient: OptionalNutrient
}

/// A planned day: logged food plus the picks not yet logged, against the calorie goal and
/// every limit in the health profile.
struct PlanDaySummary {
    let day: Date
    let calories: Int
    let overCalories: Bool
    let limits: [(nutrient: OptionalNutrient, amount: Double, goal: Int)]
    let overLimits: [OptionalNutrient]
    let swaps: [PlanSwap]

    static func make(
        day: Date,
        meals: [PlannedMeal],
        logged: [FoodEntry],
        calorieGoal: Int,
        goals: OptionalNutrientGoals,
        profile: HealthProfile,
        tastes: FoodTastes = FoodTastes()
    ) -> PlanDaySummary {
        let pending = meals.filter { !$0.isLogged(in: logged) }
        let entries = logged + pending.compactMap { $0.chosen?.entry }
        let calories = entries.reduce(0) { $0 + $1.calories }
        let limitNutrients = SuggestionRanking.orderedLimits(in: profile)
        let limits = limitNutrients.map { ($0, entries.total(of: $0), goals.goal(for: $0)) }
        let over = limits.filter { $0.2 > 0 && $0.1 > Double($0.2) }.map(\.0)

        var swaps: [PlanSwap] = []
        for nutrient in over {
            let total = entries.total(of: nutrient)
            let goal = Double(goals.goal(for: nutrient))
            var best: (swap: PlanSwap, amount: Double)?
            for meal in pending {
                guard let chosen = meal.chosen else { continue }
                let current = chosen.entry.amount(of: nutrient) ?? 0
                for option in meal.options where option.id != chosen.id {
                    let amount = option.entry.amount(of: nutrient) ?? 0
                    guard total - current + amount <= goal, !PlanDaySummary.isRuledOut(option, profile: profile),
                          !tastes.isDisliked(option.entry, contains: option.contains) else { continue }
                    if best == nil || amount < best!.amount {
                        best = (PlanSwap(mealID: meal.id, fromName: chosen.entry.name, to: option.id,
                                         toName: option.entry.name, nutrient: nutrient), amount)
                    }
                }
            }
            if let best { swaps.append(best.swap) }
        }
        return PlanDaySummary(day: day, calories: calories, overCalories: calorieGoal > 0 && calories > calorieGoal,
                              limits: limits, overLimits: over, swaps: swaps)
    }

    /// An option the avoid list or a medicine rules out is never offered as a swap.
    static func isRuledOut(_ option: PlannedOption, profile: HealthProfile) -> Bool {
        let suggestion = SuggestionOption(entry: option.entry, reason: "", tweak: nil, contains: option.contains)
        return !SuggestionRanking.avoidMatches(for: suggestion, in: profile.avoidList).isEmpty
            || !SuggestionRanking.interactions(for: suggestion, in: profile).isEmpty
    }
}

@Observable
final class MealPlanStore {
    static let storageKey = "fork.mealPlan"
    static let shared = MealPlanStore()
    /// Planned days older than this are dropped on load.
    static let keepDays = 30

    private(set) var meals: [PlannedMeal] = []
    private let blob: PersistedBlobGuard

    init(defaults: UserDefaults = .standard, corruptBackupDirectory: URL? = nil) {
        blob = PersistedBlobGuard(defaults: defaults, key: Self.storageKey, backupDirectory: corruptBackupDirectory)
        reload()
    }

    /// Weekly repeats are filled in this far ahead: the week view shows this week and next.
    static let repeatHorizonDays = 14

    /// Loads the plan, drops old days (never a repeating meal) and fills in the coming copies
    /// of every repeating meal. `entries` is the diary, for each meal's usual time.
    func reload(now: Date = Date(), calendar: Calendar = .current, entries: [FoodEntry] = []) {
        switch blob.loadList(PlannedMeal.self) {
        case .missing: meals = []
        case .decoded(let decoded, _):
            let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: calendar.startOfDay(for: now)) ?? now
            meals = decoded.filter { $0.day >= cutoff || $0.isRepeating }
            let filled = fillRepeats(now: now, calendar: calendar, entries: entries)
            if meals.count != decoded.count || filled { save() }
        case .corrupt: break
        }
    }

    /// Adds the copies of each repeating meal that are missing between today and the horizon,
    /// skipping days the user removed. True when any were added.
    private func fillRepeats(now: Date, calendar: Calendar, entries: [FoodEntry]) -> Bool {
        guard !blob.isWriteBlocked else { return false }
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: Self.repeatHorizonDays, to: today) else { return false }
        var added: [PlannedMeal] = []
        for template in meals where template.isRepeating {
            let skipped = template.skippedDays ?? []
            var day = calendar.startOfDay(for: template.day)
            while let next = calendar.date(byAdding: .day, value: 7, to: day), next < horizon {
                day = next
                guard day >= today, !skipped.contains(where: { calendar.isDate($0, inSameDayAs: day) }),
                      !(meals + added).contains(where: { $0.repeatOf == template.id && calendar.isDate($0.day, inSameDayAs: day) })
                else { continue }
                added.append(template.occurrence(on: day, entries: entries, calendar: calendar))
            }
        }
        meals += added
        return !added.isEmpty
    }

    /// Starts or stops weekly repeats of a meal (or of the meal it was copied from). Stopping
    /// removes the copies after today and leaves the earlier ones as ordinary planned meals.
    func setRepeatsWeekly(_ repeats: Bool, for mealID: UUID, now: Date = Date(), calendar: Calendar = .current,
                          entries: [FoodEntry] = []) {
        guard !blob.isWriteBlocked, let meal = meals.first(where: { $0.id == mealID }) else { return }
        let templateID = meal.repeatOf ?? meal.id
        guard let index = meals.firstIndex(where: { $0.id == templateID }) else { return }
        meals[index].repeatsWeekly = repeats
        if repeats {
            _ = fillRepeats(now: now, calendar: calendar, entries: entries)
        } else {
            let today = calendar.startOfDay(for: now)
            meals.removeAll { $0.repeatOf == templateID && $0.day > today }
            for i in meals.indices where meals[i].repeatOf == templateID { meals[i].repeatOf = nil }
        }
        save()
    }

    func meals(on day: Date, calendar: Calendar = .current) -> [PlannedMeal] {
        meals.filter { calendar.isDate($0.day, inSameDayAs: day) }
            .sorted { (MealSlotTime.defaults[$0.mealType] ?? 0) < (MealSlotTime.defaults[$1.mealType] ?? 0) }
    }

    func add(_ new: [PlannedMeal], now: Date = Date(), calendar: Calendar = .current, entries: [FoodEntry] = []) {
        guard !blob.isWriteBlocked, !new.isEmpty else { return }
        meals += new
        if new.contains(where: \.isRepeating) { _ = fillRepeats(now: now, calendar: calendar, entries: entries) }
        save()
    }

    /// Removes one planned meal. A copy of a repeating meal stays removed on that day; removing
    /// the repeating meal itself hands the repeat to its next copy, so the others keep coming.
    func remove(_ id: UUID, calendar: Calendar = .current) {
        guard !blob.isWriteBlocked, let meal = meals.first(where: { $0.id == id }) else { return }
        if let templateID = meal.repeatOf, let index = meals.firstIndex(where: { $0.id == templateID }) {
            meals[index].skippedDays = (meals[index].skippedDays ?? []) + [calendar.startOfDay(for: meal.day)]
        } else if meal.isRepeating {
            let copies = meals.filter { $0.repeatOf == id }
            if let next = copies.min(by: { $0.day < $1.day }), let index = meals.firstIndex(where: { $0.id == next.id }) {
                meals[index].repeatsWeekly = true
                meals[index].repeatOf = nil
                meals[index].skippedDays = meal.skippedDays
                for copy in copies where copy.id != next.id {
                    if let i = meals.firstIndex(where: { $0.id == copy.id }) { meals[i].repeatOf = next.id }
                }
            }
        }
        meals.removeAll { $0.id == id }
        save()
    }

    func choose(_ optionID: UUID, in mealID: UUID) {
        guard !blob.isWriteBlocked, let index = meals.firstIndex(where: { $0.id == mealID }) else { return }
        meals[index].chosenID = optionID
        save()
    }

    private func save() {
        blob.save(meals)
    }
}

extension AddMenuConfig {
    /// The + menu for anyone who has not customized it: upstream's layout with Collections,
    /// Suggestions (meal plans live there) and From Coach added to Reuse Meal.
    static var forkDefault: AddMenuConfig {
        var config = iOSDefault
        if !config.groups.isEmpty {
            config.groups[0].methods += [.collections, .suggestions, .fromCoach]
        }
        return config
    }
}
