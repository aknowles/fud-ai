import Foundation

/// Built-in oxalate reference used as a fallback when neither the AI nor a label supplied a
/// value (USDA FoodData Central and Open Food Facts have no oxalate field).
///
/// Values are approximate oxalate in mg per 100 g of the food as eaten (per 100 ml for drinks),
/// converted from the per-serving figures in the Harvard T.H. Chan School of Public Health
/// oxalate list and rounded. Oxalate varies widely with variety, growing conditions and
/// cooking, so these are day-level estimates for kidney-stone tracking, not measurements.
/// Matching works like `PurineReference`: whole words, longest keyword wins.
enum OxalateReference {
    nonisolated static let storageKey = SupplementalNutrient.oxalate.rawValue

    nonisolated static let foods: [PurineReference.Food] = [
        // Very high
        PurineReference.Food("Spinach", ["spinach", "palak", "saag"], 750),
        PurineReference.Food("Swiss chard", ["swiss chard", "chard"], 650),
        PurineReference.Food("Beet greens", ["beet greens", "beet leaves"], 610),
        PurineReference.Food("Rhubarb", ["rhubarb"], 450),
        PurineReference.Food("Wheat bran", ["wheat bran", "bran flakes", "bran cereal", "all bran"], 450),
        PurineReference.Food("Almonds", ["almond", "almonds", "almond butter", "almond flour"], 430),
        PurineReference.Food("Cocoa powder", ["cocoa powder", "cacao powder", "cocoa"], 600),
        PurineReference.Food("Rice bran", ["rice bran"], 240),
        PurineReference.Food("Tahini", ["tahini", "sesame paste"], 230),
        PurineReference.Food("Cashews", ["cashew", "cashews", "cashew butter"], 175),

        // Moderate
        PurineReference.Food("Soy flour", ["soy flour", "soybeans", "soybean", "edamame"], 110),
        PurineReference.Food("Dates", ["date", "dates", "medjool"], 100),
        PurineReference.Food("Chocolate", ["dark chocolate", "chocolate", "brownie", "brownies"], 100),
        PurineReference.Food("Peanuts", ["peanut", "peanuts"], 95),
        PurineReference.Food("Beets", ["beet", "beets", "beetroot", "borscht"], 90),
        PurineReference.Food("Navy beans", ["navy beans", "baked beans", "white beans"], 85),
        PurineReference.Food("Buckwheat", ["buckwheat", "kasha", "soba"], 80),
        PurineReference.Food("Potato chips", ["potato chips", "crisps"], 75),
        PurineReference.Food("Okra", ["okra", "gumbo"], 70),
        PurineReference.Food("Baked potato", ["baked potato", "potato", "potatoes", "hash browns", "mashed potatoes"], 55),
        PurineReference.Food("French fries", ["french fries", "fries"], 45),
        PurineReference.Food("Miso soup", ["miso soup", "miso"], 45),
        PurineReference.Food("Raspberries", ["raspberry", "raspberries"], 40),
        PurineReference.Food("Peanut butter", ["peanut butter"], 40),
        PurineReference.Food("Hot chocolate", ["hot chocolate", "hot cocoa", "chocolate milk"], 27),
        PurineReference.Food("Sweet potato", ["sweet potato", "sweet potatoes", "yam", "yams"], 15),
        PurineReference.Food("Almond milk", ["almond milk"], 11),

        // Low anchors for plain staples. Only short, specific words: the longest keyword wins, so a
        // generic dish word ("sandwich", "omelette") would hide the spinach in it.
        PurineReference.Food("Tofu", ["tofu"], 10),
        PurineReference.Food("Bread", ["bread", "toast"], 8),
        PurineReference.Food("Pasta", ["pasta", "spaghetti", "noodles"], 7),
        PurineReference.Food("Black tea", ["black tea", "tea", "iced tea"], 6),
        PurineReference.Food("Banana", ["banana", "bananas"], 3),
        PurineReference.Food("Rice", ["white rice", "rice"], 2),
        PurineReference.Food("Broccoli", ["broccoli", "kale", "cauliflower", "cabbage"], 2),
        PurineReference.Food("Apple", ["apple", "apples"], 1),
        PurineReference.Food("Dairy", ["milk", "cheese", "yogurt", "yoghurt", "butter", "cream"], 0),
        PurineReference.Food("Meat", ["chicken", "beef", "pork", "turkey", "lamb", "steak", "bacon", "ham"], 0),
        PurineReference.Food("Fish and eggs", ["fish", "salmon", "tuna", "shrimp", "egg", "eggs"], 0),
        PurineReference.Food("Water and coffee", ["water", "coffee", "espresso"], 0),
    ]

    nonisolated static func match(_ text: String) -> PurineReference.Food? {
        PurineReference.match(text, in: foods)
    }

    /// Estimated oxalate (mg) for the analyzed amount, or nil when nothing in the entry is recognized.
    nonisolated static func estimateMilligrams(for entry: FoodEntry) -> Double? {
        PurineReference.estimateMilligrams(name: entry.name, grams: entry.servingSizeGrams,
                                           ingredients: entry.ingredients, in: foods)
    }

    /// Adds an oxalate estimate when the entry has none and a reference food matches.
    nonisolated static func applyFallbackIfNeeded(_ entry: inout FoodEntry) {
        guard entry.supplementalNutrients[storageKey] == nil,
              let estimate = estimateMilligrams(for: entry)
        else { return }
        entry.supplementalNutrients[storageKey] = estimate
    }
}
