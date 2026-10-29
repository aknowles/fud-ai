import Foundation
import UIKit

/// What the user gave the suggestion screen to choose from.
enum FoodSuggestionInput {
    /// A menu, shelf, fridge or buffet.
    case photo(UIImage)
    /// Options typed or dictated, e.g. "turkey sandwich, chili, salad bar".
    case text(String)
    /// Saved foods: a collection, Favorites, or everything saved when the user is just hungry.
    case saved(title: String, entries: [FoodEntry])

    var savedEntries: [FoodEntry] {
        if case .saved(_, let entries) = self { return entries }
        return []
    }
}

/// The ranked answer: options best first, and either one of them or waiting as the pick.
struct FoodSuggestions {
    var options: [SuggestionOption]
    /// The recommended option, or nil when waiting for the next meal is the pick.
    var pick: SuggestionOption.ID?
    var pickReason: String
    var waitReason: String
    var bridgeText: String?
    var bridgeSnack: FoodEntry?
}

enum FoodSuggestionService {
    /// Options accepted from the AI, at most.
    static let maxOptions = 8
    /// Saved foods sent to the AI to choose from, at most.
    static let maxSaved = 15

    static func suggest(
        _ input: FoodSuggestionInput,
        context: SuggestionContext,
        healthLines: [String],
        now: Date = Date()
    ) async throws -> (FoodSuggestions, aiPickedWait: Bool) {
        let saved = Array(input.savedEntries.prefix(maxSaved))
        let image: UIImage? = if case .photo(let photo) = input { photo } else { nil }
        let text = try await AIResponseBudget.withMinimum(AIResponseBudget.suggestions) {
            try await GeminiService.callAI(
                prompt: prompt(for: input, saved: saved, context: context, healthLines: healthLines, now: now),
                image: image
            )
        }
        return try parse(text, saved: saved, source: image == nil ? .textInput : .snapFood, now: now)
    }

    // MARK: - Prompt

    static func prompt(
        for input: FoodSuggestionInput,
        saved: [FoodEntry],
        context: SuggestionContext,
        healthLines: [String],
        now: Date
    ) -> String {
        var lines = [
            "The user is hungry and wants to know what to eat now, or whether to wait for their next meal. Rank their options best first for their goals today.",
            "",
            "## Their day",
            "- Time now: \(clock(now))",
            "- Calories left today: \(context.caloriesLeft) kcal",
        ]
        if let next = context.nextMeal {
            lines.append("- Next usual meal: \(next.mealType.rawValue) in about \(next.minutesAway) minutes, usually about \(next.typicalCalories) kcal")
        } else {
            lines.append("- Next usual meal: unknown")
        }
        if context.isFasting { lines.append("- They are in an active fast.") }
        lines += healthLines

        lines += ["", "## Options"]
        switch input {
        case .photo:
            lines.append("The photo shows what is available (a menu, shelf, fridge or buffet). List each distinct option, up to \(maxOptions), and estimate one typical portion of each.")
        case .text(let description):
            lines.append("The user typed or said: \(description)")
            lines.append("Treat each item as one option, up to \(maxOptions), and estimate one typical portion of each.")
        case .saved(let title, _):
            lines.append("Saved foods (\(title)). Use their saved_id; do not estimate them again:")
            for (index, entry) in saved.enumerated() {
                lines.append("- S\(index + 1): \(summary(of: entry))")
            }
        }

        lines += [
            "",
            "## Answer",
            "Respond ONLY with JSON:",
            #"{"options":[{"saved_id":"S1","food":null,"servings":1.0,"tweak":null,"reason":"..."}],"pick":0,"pick_reason":"...","wait_reason":"...","bridge":null}"#,
            "- options: best first. For a saved food set saved_id and food null; otherwise saved_id null and food is the estimate, in this shape:",
            foodShape,
            GeminiService.foodNutrientInstruction(includingAminoAcids: false),
            "- contains: the main allergens and notable ingredients in the food, lowercase (for example wheat, milk, egg, peanut, tree nut, soy, fish, shellfish, sesame, grapefruit); [] when none.",
            "- servings: how much of the option to eat (1.0 = as listed). Use 0.5 for a half portion.",
            "- tweak: a short change that makes the option fit better (half portion, swap the side, add protein, skip the beer), or null. When the tweak changes the amount, set servings to match; describe swaps in the tweak and estimate food as tweaked.",
            "- reason: one short sentence on why it ranks where it does, naming purines, sodium or calories when they matter.",
            "- pick: the 0-based index of the option to eat now, or \"wait\" when waiting for the next meal is better (close to the next meal with little left for it, an active fast, or nothing fits).",
            "- pick_reason: one sentence for the pick. wait_reason: one sentence on what waiting would mean, even when it is not the pick.",
            "- bridge: when pick is \"wait\", a small thing to tide them over (water, or a small protein or fiber snack); otherwise null.",
        ]
        return lines.joined(separator: "\n")
    }

    static let foodShape = #"{"name":"...","emoji":"🍽️","serving_size_grams":0.0,"calories":0,"protein":0.0,"carbs":0.0,"fat":0.0,"fiber":0.0,"sugar":0.0,"added_sugar":0.0,"saturated_fat":0.0,"trans_fat":0.0,"cholesterol":0.0,"sodium":0.0,"potassium":0.0,"calcium":0.0,"magnesium":0.0,"purines":0.0,"alcohol":0.0,"phosphorus":0.0,"oxalate":0.0,"tyramine":0.0,"contains":["wheat"]}"#

    private static func summary(of entry: FoodEntry) -> String {
        var parts = ["\(entry.name): \(entry.calories) kcal", "protein \(Int(entry.protein.rounded())) g"]
        if let purines = entry.supplementalNutrients[OptionalNutrient.purines.rawValue] { parts.append("purines \(Int(purines.rounded())) mg") }
        if let sodium = entry.sodium { parts.append("sodium \(Int(sodium.rounded())) mg") }
        if let sugar = entry.addedSugar { parts.append("added sugar \(Int(sugar.rounded())) g") }
        if let alcohol = entry.supplementalNutrients[OptionalNutrient.alcohol.rawValue], alcohol > 0 { parts.append("alcohol \(Int(alcohol.rounded())) g") }
        return parts.joined(separator: ", ")
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Parsing

    enum ParseError: Error { case invalidResponse, noOptions }

    /// A food object in `foodShape` through the shared food parser, or nil when it is unusable.
    static func foodAnalysis(from food: [String: Any]) -> GeminiService.FoodAnalysis? {
        guard let data = try? JSONSerialization.data(withJSONObject: food) else { return nil }
        return try? GeminiService.parseFoodAnalysis(from: String(decoding: data, as: UTF8.self))
    }

    /// Turns the AI's JSON into options. Saved foods keep their stored nutrition; new foods
    /// go through the shared food parser and the same entry builder as Review Food, so a
    /// logged suggestion carries exactly the nutrients shown.
    static func parse(
        _ text: String,
        saved: [FoodEntry],
        source: FoodSource,
        now: Date
    ) throws -> (FoodSuggestions, aiPickedWait: Bool) {
        guard let data = GeminiService.extractJSON(from: text).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawOptions = json["options"] as? [[String: Any]]
        else { throw ParseError.invalidResponse }

        var options: [SuggestionOption] = []
        var indexMap: [Int: SuggestionOption.ID] = [:]
        for (index, raw) in rawOptions.prefix(maxOptions).enumerated() {
            let servings = min(max((raw["servings"] as? NSNumber)?.doubleValue ?? 1, 0.25), 3)
            let analysis: GeminiService.FoodAnalysis
            let entrySource: FoodSource
            if let id = raw["saved_id"] as? String, id.hasPrefix("S"),
               let number = Int(id.dropFirst()), saved.indices.contains(number - 1) {
                analysis = saved[number - 1].reviewAnalysis
                entrySource = saved[number - 1].source
            } else if let food = raw["food"] as? [String: Any], let parsed = foodAnalysis(from: food) {
                analysis = parsed
                entrySource = source
            } else {
                continue
            }
            let entry = VoiceAssistantFoodBuilder.entry(
                from: analysis, images: [], source: entrySource, servings: servings,
                timestamp: now, mealType: .currentMeal
            )
            let tweak = (raw["tweak"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let contains = ((raw["food"] as? [String: Any])?["contains"] as? [String]) ?? []
            let option = SuggestionOption(entry: entry, reason: raw["reason"] as? String ?? "", tweak: tweak, contains: contains)
            indexMap[index] = option.id
            options.append(option)
        }
        guard !options.isEmpty else { throw ParseError.noOptions }

        let pickedIndex = (json["pick"] as? NSNumber)?.intValue
        let aiPickedWait = (json["pick"] as? String)?.lowercased() == "wait"
        let suggestions = FoodSuggestions(
            options: options,
            pick: aiPickedWait ? nil : pickedIndex.flatMap { indexMap[$0] } ?? options.first?.id,
            pickReason: json["pick_reason"] as? String ?? "",
            waitReason: json["wait_reason"] as? String ?? "",
            bridgeText: json["bridge"] as? String
        )
        return (suggestions, aiPickedWait)
    }
}
