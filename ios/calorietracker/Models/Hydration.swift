import Foundation

/// Drinks logged as food that count toward the water goal: every non-alcoholic drink, as
/// health guidance counts fluids (water, coffee, tea, milk, juice, sports drinks, soda).
/// Their sugar and caffeine still count toward those limits; alcohol does not count as
/// fluid. Volume comes from the serving size (1 g ≈ 1 ml).
enum Hydration {
    static let countDrinksKey = "fork.water.countDrinks"

    /// On unless the user turns it off.
    static var countsDrinks: Bool {
        UserDefaults.standard.object(forKey: countDrinksKey) as? Bool ?? true
    }

    static let drinkTerms = [
        "water", "seltzer", "sparkling", "club soda", "tea", "coffee", "espresso", "americano", "latte",
        "cappuccino", "flat white", "cold brew", "macchiato", "cortado", "mocha", "matcha", "chai", "milk",
        "kombucha", "broth", "juice", "lemonade", "soda", "cola", "pop", "gatorade", "powerade", "bodyarmor",
        "sports drink", "electrolyte", "smoothie", "shake", "milkshake", "frappuccino", "frappe", "energy drink",
        "hot chocolate", "cocoa", "bubble tea", "boba", "iced tea", "drink",
    ]
    static let alcoholTerms = [
        "beer", "wine", "cocktail", "liquor", "whiskey", "vodka", "gin", "rum", "tequila", "cider", "sake",
        "margarita", "mimosa", "sangria", "seltzer hard", "hard seltzer", "ale", "lager", "ipa", "stout",
    ]
    /// Foods that share a drink word but are not drinks.
    static let notDrinkTerms = [
        "ice cream", "cake", "cookie", "chocolate bar", "milk chocolate", "candy", "bread", "pancake", "tea cake",
        "pop tart", "water chestnut", "water chestnuts", "cereal", "pudding", "coffee cake", "soda bread",
        "milk bread", "water crackers", "water cracker", "tea sandwich", "tea sandwiches", "jelly", "gummies",
    ]

    /// Drink brands whose names carry no drink word.
    static let brandTerms = [
        "coke", "coca-cola", "coca cola", "pepsi", "sprite", "fanta", "dr pepper", "mountain dew", "7up", "7-up",
        "ginger ale", "root beer", "ginger beer", "red bull", "monster energy", "celsius", "la croix", "lacroix",
        "bubly", "perrier", "san pellegrino", "pellegrino", "topo chico", "liquid iv", "liquid i.v.", "propel",
        "snapple", "arizona", "nesquik", "yakult", "kefir", "lassi", "horchata", "agua fresca",
    ]
    /// Phrases that make a drink non-alcoholic despite a word like "beer".
    static let nonAlcoholicTerms = ["non-alcoholic", "non alcoholic", "alcohol-free", "alcohol free", "root beer", "ginger beer", "0.0"]

    /// A drink by name: a drink word, a brand, or a compound like "vitaminwater" or "smartwater".
    static func nameLooksLikeDrink(_ name: String) -> Bool {
        if matches(name, drinkTerms + brandTerms) { return true }
        let words = name.lowercased().split { !$0.isLetter }
        return words.contains { $0.count > 5 && $0.hasSuffix("water") && !$0.hasPrefix("water") }
    }

    /// Open Food Facts and USDA tag drinks as beverages.
    static func isBeverageProduct(_ entry: FoodEntry) -> Bool {
        (entry.productMetadata?.categories ?? []).contains { category in
            let text = category.lowercased()
            return text.contains("beverage") || text.contains("drink") || text.contains("water")
        }
    }

    static func isAlcoholic(_ entry: FoodEntry) -> Bool {
        if (entry.supplementalNutrients[OptionalNutrient.alcohol.rawValue] ?? 0) > 0 { return true }
        return matches(entry.name, alcoholTerms) && !matches(entry.name, nonAlcoholicTerms)
    }

    enum Result: Equatable {
        case counts(Int)
        case alcohol
        case noServingSize
        case notADrink
    }

    static func classify(_ entry: FoodEntry) -> Result {
        guard !matches(entry.name, notDrinkTerms) else { return .notADrink }
        let alcohol = isAlcoholic(entry)
        let isDrink = alcohol || entry.selectedServingUnit == "drink" || nameLooksLikeDrink(entry.name) || isBeverageProduct(entry)
        guard isDrink else { return .notADrink }
        if alcohol { return .alcohol }
        guard let grams = entry.servingSizeGrams, grams > 0 else { return .noServingSize }
        return .counts(Int(grams.rounded()))
    }

    /// Milliliters this entry adds toward water, or 0.
    static func milliliters(for entry: FoodEntry) -> Int {
        if case .counts(let milliliters) = classify(entry) { return milliliters }
        return 0
    }

    static func milliliters(from entries: [FoodEntry]) -> Int {
        entries.reduce(0) { $0 + milliliters(for: $1) }
    }

    static func matches(_ name: String, _ terms: [String]) -> Bool {
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
