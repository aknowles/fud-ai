import Foundation
import Observation

/// One food that could be eaten at a planned meal, with the allergens and notable ingredients
/// the AI listed and why it ranks where it does.
struct PlannedOption: Codable, Identifiable {
    var id = UUID()
    var entry: FoodEntry
    var contains: [String] = []
    var reason: String?
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
    var chosenID: UUID?

    /// The picked option; a single-option meal is always picked.
    var chosen: PlannedOption? {
        options.first { $0.id == chosenID } ?? (options.count == 1 ? options.first : nil)
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
        profile: HealthProfile
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
                    guard total - current + amount <= goal, !PlanDaySummary.isRuledOut(option, profile: profile) else { continue }
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

    func reload(now: Date = Date(), calendar: Calendar = .current) {
        switch blob.loadList(PlannedMeal.self) {
        case .missing: meals = []
        case .decoded(let decoded, _):
            let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: calendar.startOfDay(for: now)) ?? now
            meals = decoded.filter { $0.day >= cutoff }
            if meals.count != decoded.count { save() }
        case .corrupt: break
        }
    }

    func meals(on day: Date, calendar: Calendar = .current) -> [PlannedMeal] {
        meals.filter { calendar.isDate($0.day, inSameDayAs: day) }
            .sorted { (MealSlotTime.defaults[$0.mealType] ?? 0) < (MealSlotTime.defaults[$1.mealType] ?? 0) }
    }

    func add(_ new: [PlannedMeal]) {
        guard !blob.isWriteBlocked, !new.isEmpty else { return }
        meals += new
        save()
    }

    func remove(_ id: UUID) {
        guard !blob.isWriteBlocked else { return }
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
    /// The + menu for anyone who has not customized it: upstream's layout with Collections and
    /// Suggestions (meal plans live there) added to Reuse Meal.
    static var forkDefault: AddMenuConfig {
        var config = iOSDefault
        if !config.groups.isEmpty {
            config.groups[0].methods += [.collections, .suggestions]
        }
        return config
    }
}
