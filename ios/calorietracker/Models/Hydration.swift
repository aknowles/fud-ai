import Foundation

/// Drinks logged as food that count toward the water goal: unsweetened, alcohol-free drinks
/// such as water, sparkling water, tea, coffee and milk. Juice, soda, shakes and smoothies
/// do not count. Volume comes from the serving size (1 g ≈ 1 ml).
enum Hydration {
    static let countDrinksKey = "fork.water.countDrinks"

    /// On unless the user turns it off.
    static var countsDrinks: Bool {
        UserDefaults.standard.object(forKey: countDrinksKey) as? Bool ?? true
    }

    /// At most this much added sugar per drink still counts.
    static let maxAddedSugar = 10.0

    static let drinkTerms = [
        "water", "seltzer", "sparkling", "club soda", "mineral water", "tea", "coffee", "espresso", "americano",
        "latte", "cappuccino", "flat white", "cold brew", "macchiato", "cortado", "matcha", "chai", "milk",
        "kombucha", "broth",
    ]
    static let excludedTerms = [
        "juice", "soda", "cola", "lemonade", "shake", "milkshake", "smoothie", "frappuccino", "frappe", "energy drink",
        "beer", "wine", "cocktail", "liquor", "whiskey", "vodka", "cider", "hot chocolate", "cake", "cookie",
        "ice cream", "chocolate milk", "bubble tea", "boba",
    ]

    /// Milliliters this entry adds toward water, or 0.
    static func milliliters(for entry: FoodEntry) -> Int {
        guard (entry.supplementalNutrients[OptionalNutrient.alcohol.rawValue] ?? 0) <= 0,
              (entry.addedSugar ?? 0) <= maxAddedSugar,
              let grams = entry.servingSizeGrams, grams > 0
        else { return 0 }
        let isDrink = entry.selectedServingUnit == "drink" || matches(entry.name, drinkTerms)
        guard isDrink, !matches(entry.name, excludedTerms) else { return 0 }
        return Int(grams.rounded())
    }

    static func milliliters(from entries: [FoodEntry]) -> Int {
        entries.reduce(0) { $0 + milliliters(for: $1) }
    }

    private static func matches(_ name: String, _ terms: [String]) -> Bool {
        !AvoidList(custom: terms).matches(texts: [name]).isEmpty
    }
}

extension WaterStore {
    /// Logged water plus drinks from the food diary that count toward it, when that is on.
    func totalIncludingDrinks(on date: Date, foods: FoodStore) -> Int {
        total(on: date) + (Hydration.countsDrinks ? Hydration.milliliters(from: foods.entries(for: date)) : 0)
    }
}

/// When water is worth suggesting: gout or kidney stones, where drinking plenty is standard
/// advice. Never with kidney disease, where fluids may be limited.
enum WaterSuggestion {
    static let dismissedKey = "fork.waterSuggestionDismissed"
    static let suggestedGoalMl = 2_500

    static func applies(to profile: HealthProfile) -> Bool {
        let kinds = Set(profile.entries)
        return !kinds.contains(.kidneyDisease) && (kinds.contains(.gout) || kinds.contains(.kidneyStones))
    }

    static func shouldShow(profile: HealthProfile, defaults: UserDefaults = .standard) -> Bool {
        applies(to: profile) && !defaults.bool(forKey: WaterSettings.enabledKey) && !defaults.bool(forKey: dismissedKey)
    }

    /// Turns water tracking on, raising the goal to the suggested amount if it is lower.
    static func accept(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: WaterSettings.enabledKey)
        let goal = defaults.object(forKey: WaterSettings.dailyGoalKey) as? Int ?? WaterSettings.defaultDailyGoalMl
        defaults.set(max(goal, suggestedGoalMl), forKey: WaterSettings.dailyGoalKey)
    }
}
