import Foundation
import UIKit

/// Turns a multi-day menu (a workplace cafe's weekly menu, as a photo or text) into planned
/// meals with estimated, ranked options, in one AI call.
enum MealPlanService {
    enum Input {
        case photo(UIImage)
        case text(String)
    }

    static let maxOptionsPerMeal = 8

    static func importMenu(
        _ input: Input,
        weekStart: Date,
        defaultMeal: MealType,
        source: String,
        healthLines: [String],
        entries: [FoodEntry],
        calendar: Calendar = .current
    ) async throws -> [PlannedMeal] {
        let image: UIImage? = if case .photo(let photo) = input { photo } else { nil }
        let text = try await GeminiService.callAI(
            prompt: prompt(for: input, weekStart: weekStart, defaultMeal: defaultMeal, healthLines: healthLines),
            image: image
        )
        return try parse(text, weekStart: weekStart, defaultMeal: defaultMeal, source: source,
                         entries: entries, calendar: calendar)
    }

    static func prompt(for input: Input, weekStart: Date, defaultMeal: MealType, healthLines: [String]) -> String {
        var lines = [
            "This is a menu covering several days, for example a workplace cafe's weekly menu. Plan the user's meals from it.",
            "The week starts on Monday \(isoDay(weekStart)). Unless the menu says otherwise, every item is for \(defaultMeal.rawValue).",
        ]
        if case .text(let text) = input { lines += ["", "## Menu", text] }
        lines += healthLines
        lines += [
            "",
            "## Answer",
            "Respond ONLY with JSON:",
            #"{"days":[{"date":"YYYY-MM-DD","meal":"lunch","options":[{"food":{...},"reason":"..."}],"pick":0}]}"#,
            "- One object per day and meal that has items. date is that day in the menu's week; meal is breakfast, lunch, dinner or snack.",
            "- options: up to \(maxOptionsPerMeal), best first for the user's goals above; estimate one typical portion of each. food uses this shape:",
            FoodSuggestionService.foodShape,
            GeminiService.foodNutrientInstruction(includingAminoAcids: false),
            "- contains: the main allergens and notable ingredients, lowercase (for example wheat, milk, egg, peanut, tree nut, soy, fish, shellfish, sesame, grapefruit); [] when none.",
            "- reason: one short sentence on why it ranks where it does, naming purines, sodium or calories when they matter.",
            "- pick: the 0-based index of the best option for that meal.",
        ]
        return lines.joined(separator: "\n")
    }

    enum ParseError: Error { case invalidResponse, noMeals }

    static func parse(
        _ text: String,
        weekStart: Date,
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
            guard let dateText = raw["date"] as? String, let parsedDay = parseDay(dateText, calendar: calendar),
                  parsedDay >= weekStartDay, parsedDay < weekEnd,
                  let rawOptions = raw["options"] as? [[String: Any]]
            else { continue }
            let meal = (raw["meal"] as? String).flatMap { MealType(rawValue: $0.lowercased()) } ?? defaultMeal
            let time = MealSlotTime.time(for: meal, on: parsedDay, entries: entries, calendar: calendar)
            let options: [PlannedOption] = rawOptions.prefix(maxOptionsPerMeal).compactMap { option in
                guard let food = option["food"] as? [String: Any],
                      let analysis = FoodSuggestionService.foodAnalysis(from: food) else { return nil }
                let entry = VoiceAssistantFoodBuilder.entry(from: analysis, images: [], source: .textInput, servings: 1,
                                                            timestamp: time, mealType: meal)
                return PlannedOption(entry: entry, contains: food["contains"] as? [String] ?? [],
                                     reason: option["reason"] as? String)
            }
            guard !options.isEmpty else { continue }
            let pick = (raw["pick"] as? NSNumber)?.intValue
            let chosen = pick.flatMap { options.indices.contains($0) ? options[$0].id : nil } ?? options.first?.id
            meals.append(PlannedMeal(day: parsedDay, mealType: meal, source: source, options: options, chosenID: chosen))
        }
        guard !meals.isEmpty else { throw ParseError.noMeals }
        return meals
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
