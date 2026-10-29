import Foundation
import UIKit

/// Turns a multi-day menu (a workplace cafe's weekly menu, as a photo or text) into planned
/// meals with estimated, ranked options, in one AI call.
enum MealPlanService {
    enum Input {
        case photo(UIImage)
        case text(String)
    }

    /// Cafe menus rarely offer more per meal, and each option adds a full nutrition block.
    static let maxOptionsPerMeal = 4

    static func importMenu(
        _ input: Input,
        weekStart: Date,
        day: Date? = nil,
        defaultMeal: MealType,
        source: String,
        healthLines: [String],
        entries: [FoodEntry],
        calendar: Calendar = .current
    ) async throws -> [PlannedMeal] {
        let image: UIImage? = if case .photo(let photo) = input { photo } else { nil }
        let text = try await AIResponseBudget.withMinimum(AIResponseBudget.menuImport) {
            try await GeminiService.callAI(
                prompt: prompt(for: input, weekStart: weekStart, day: day, defaultMeal: defaultMeal, healthLines: healthLines),
                image: image
            )
        }
        return try parse(text, weekStart: weekStart, day: day, defaultMeal: defaultMeal, source: source,
                         entries: entries, calendar: calendar)
    }

    /// With `day`, the menu is for that one day; otherwise it covers the week from `weekStart`.
    static func prompt(for input: Input, weekStart: Date, day: Date? = nil, defaultMeal: MealType, healthLines: [String]) -> String {
        var lines: [String]
        if let day {
            lines = [
                "This is a menu for one day, for example a workplace cafe's menu of the day. Plan the user's meals from it.",
                "It is for \(isoDay(day)); use that date for every item. Unless the menu says otherwise, every item is for \(defaultMeal.rawValue).",
            ]
        } else {
            lines = [
                "This is a menu covering several days, for example a workplace cafe's weekly menu. Plan the user's meals from it.",
                "The week starts on Monday \(isoDay(weekStart)). Match each day the menu names to its date in that week; if days are not named, assume they run Monday onward. Unless the menu says otherwise, every item is for \(defaultMeal.rawValue).",
            ]
        }
        if case .text(let text) = input { lines += ["", "## Menu", text] }
        lines += healthLines
        lines += [
            "",
            "## Answer",
            "Respond ONLY with JSON:",
            #"{"days":[{"date":"YYYY-MM-DD","meal":"lunch","options":[{"food":{...},"includes":["..."],"reason":"..."}],"pick":0}]}"#,
            "- One object per day and meal that has items. date is that day in the menu's week; meal is breakfast, lunch, dinner or snack.",
            "- options: up to \(maxOptionsPerMeal), best first for the user's goals above; estimate one typical portion of each. food uses this shape:",
            FoodSuggestionService.foodShape,
            GeminiService.foodNutrientInstruction(includingAminoAcids: false),
            "- contains: the main allergens and notable ingredients, lowercase (for example wheat, milk, egg, peanut, tree nut, soy, fish, shellfish, sesame, grapefruit); [] when none.",
            "- Each option is one dish as served: a main with the sides that come with it, a soup, or a station item. food.name is the dish's menu name; includes lists the sides and components served with it (for example [\"rice pilaf\", \"green beans\"]), [] when none; the food's nutrition covers the dish and everything in includes.",
            "- reason: one short sentence on why it ranks where it does, naming purines, sodium or calories when they matter.",
            "- pick: the 0-based index of the option you suggest for that meal.",
        ]
        return lines.joined(separator: "\n")
    }

    enum ParseError: Error { case invalidResponse, noMeals }

    static func parse(
        _ text: String,
        weekStart: Date,
        day: Date? = nil,
        defaultMeal: MealType,
        source: String,
        entries: [FoodEntry],
        calendar: Calendar = .current
    ) throws -> [PlannedMeal] {
        guard let data = GeminiService.extractJSON(from: text).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = json["days"] as? [[String: Any]]
        else { throw ParseError.invalidResponse }

        let weekStartDay = calendar.startOfDay(for: weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStartDay) ?? weekStartDay
        var meals: [PlannedMeal] = []
        for raw in days {
            let rawDay = day.map { calendar.startOfDay(for: $0) } ?? (raw["date"] as? String).flatMap { parseDay($0, calendar: calendar) }
            guard let parsedDay = rawDay, day != nil || (parsedDay >= weekStartDay && parsedDay < weekEnd),
                  let rawOptions = raw["options"] as? [[String: Any]]
            else { continue }
            let meal = (raw["meal"] as? String).flatMap { MealType(rawValue: $0.lowercased()) } ?? defaultMeal
            let time = MealSlotTime.time(for: meal, on: parsedDay, entries: entries, calendar: calendar)
            let options: [PlannedOption] = rawOptions.prefix(maxOptionsPerMeal).compactMap { option in
                guard let food = option["food"] as? [String: Any],
                      let analysis = FoodSuggestionService.foodAnalysis(from: food) else { return nil }
                let entry = VoiceAssistantFoodBuilder.entry(from: analysis, images: [], source: .textInput, servings: 1,
                                                            timestamp: time, mealType: meal)
                let includes = (option["includes"] as? [String] ?? food["includes"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return PlannedOption(entry: entry, contains: food["contains"] as? [String] ?? [],
                                     reason: option["reason"] as? String, includes: includes.isEmpty ? nil : includes)
            }
            guard !options.isEmpty else { continue }
            let pick = (raw["pick"] as? NSNumber)?.intValue
            let suggested = pick.flatMap { options.indices.contains($0) ? options[$0].id : nil } ?? options.first?.id
            meals.append(PlannedMeal(day: parsedDay, mealType: meal, source: source, options: options, suggestedID: suggested))
        }
        guard !meals.isEmpty else { throw ParseError.noMeals }
        return merged(meals, calendar: calendar)
    }

    /// One meal per day and meal type: repeats (e.g. two lunch stations on a one-day menu)
    /// become options of the first.
    static func merged(_ meals: [PlannedMeal], calendar: Calendar = .current) -> [PlannedMeal] {
        var result: [PlannedMeal] = []
        for meal in meals {
            if let index = result.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: meal.day) && $0.mealType == meal.mealType }) {
                result[index].options += meal.options
            } else {
                result.append(meal)
            }
        }
        return result
    }

    /// A planned meal from a saved food or recipe, on `day` at the usual time for `meal`.
    static func plannedMeal(from saved: FoodEntry, day: Date, meal: MealType, entries: [FoodEntry],
                            calendar: Calendar = .current) -> PlannedMeal {
        let time = MealSlotTime.time(for: meal, on: day, entries: entries, calendar: calendar)
        let entry = saved.duplicatedForLogging(at: time, mealType: meal)
        return PlannedMeal(day: calendar.startOfDay(for: day), mealType: meal, source: String(localized: "Saved food"),
                           options: [PlannedOption(entry: entry)])
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parseDay(_ text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text).map { calendar.startOfDay(for: $0) }
    }
}
