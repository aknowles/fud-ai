import Foundation
import Testing
@testable import calorietracker

/// The built-in oxalate table only fills in when nothing else supplied a value, matching
/// food names like the purine table does.
@MainActor
struct OxalateReferenceTests {
    @Test func valuesArePlausible() {
        #expect(OxalateReference.foods.count >= 35)
        for food in OxalateReference.foods {
            #expect(food.milligramsPer100g >= 0 && food.milligramsPer100g <= 1_000, "\(food.name)")
            #expect(!food.keywords.isEmpty, "\(food.name)")
        }
    }

    @Test func leafyGreensAndNutsRankAboveStaples() throws {
        let spinach = try #require(OxalateReference.match("Sauteed spinach"))
        let almonds = try #require(OxalateReference.match("Roasted almonds"))
        let beets = try #require(OxalateReference.match("Pickled beets"))
        let rice = try #require(OxalateReference.match("Steamed white rice"))
        let chicken = try #require(OxalateReference.match("Grilled chicken"))

        #expect(spinach.milligramsPer100g > almonds.milligramsPer100g)
        #expect(almonds.milligramsPer100g > beets.milligramsPer100g)
        #expect(beets.milligramsPer100g > rice.milligramsPer100g)
        #expect(chicken.milligramsPer100g == 0)
    }

    @Test func specificFoodsBeatGenericWords() {
        #expect(OxalateReference.match("Spinach omelette")?.name == "Spinach")
        #expect(OxalateReference.match("Almond milk latte")?.name == "Almond milk")
        #expect(OxalateReference.match("Peanut butter toast")?.name == "Peanut butter")
        #expect(OxalateReference.match("Sweet potato fries")?.name == "Sweet potato")
        #expect(OxalateReference.match("Chocolate milk")?.name == "Hot chocolate")
        #expect(OxalateReference.match("Tortilla chips") == nil)
    }

    @Test func estimatesUseIngredientsFirstThenTheServingSize() throws {
        let salad = FoodEntry(name: "Spinach salad", calories: 300, protein: 30, carbs: 10, fat: 15, source: .manual,
                              servingSizeGrams: 180,
                              ingredients: [
                                  MealIngredient(name: "Baby spinach", grams: 60, calories: 14, protein: 2, carbs: 2, fat: 0),
                                  MealIngredient(name: "Sliced almonds", grams: 20, calories: 116, protein: 4, carbs: 4, fat: 10),
                                  MealIngredient(name: "Chicken breast", grams: 100, calories: 165, protein: 31, carbs: 0, fat: 4),
                              ])
        #expect(OxalateReference.estimateMilligrams(for: salad) == 536)

        let plain = FoodEntry(name: "Cooked spinach", calories: 40, protein: 5, carbs: 6, fat: 0, source: .manual,
                              servingSizeGrams: 150)
        #expect(OxalateReference.estimateMilligrams(for: plain) == 1_125)
    }

    @Test func theFallbackNeverOverwritesAValueAndRunsWhenFoodIsLogged() throws {
        var fromAI = FoodEntry(name: "Spinach", calories: 20, protein: 2, carbs: 3, fat: 0, source: .manual,
                               supplementalNutrients: ["oxalate": 500], servingSizeGrams: 100)
        OxalateReference.applyFallbackIfNeeded(&fromAI)
        #expect(fromAI.supplementalNutrients["oxalate"] == 500)

        let suite = "OxalateReferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)
        #expect(store.addEntry(FoodEntry(name: "Roasted almonds", calories: 160, protein: 6, carbs: 6, fat: 14,
                                         source: .manual, servingSizeGrams: 28)))

        #expect(store.entries.first?.supplementalNutrients["oxalate"] == 120.4)
    }
}
