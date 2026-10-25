import Foundation
import Testing
@testable import calorietracker

/// The built-in purine table only fills in when nothing else supplied a value, and it
/// matches food names the way a person skims a purine table: longest specific term wins.
@MainActor
struct PurineReferenceTests {
    @Test func tableHasAtLeastAHundredFoodsWithPlausibleValues() {
        #expect(PurineReference.foods.count >= 100)
        for food in PurineReference.foods {
            #expect(food.milligramsPer100g >= 0 && food.milligramsPer100g <= 2_000, "\(food.name)")
            #expect(!food.keywords.isEmpty, "\(food.name)")
        }
    }

    @Test func organMeatsAndOilyFishRankAboveDairyAndPlants() throws {
        let liver = try #require(PurineReference.match("Grilled beef liver with onions"))
        let sardines = try #require(PurineReference.match("Canned sardines"))
        let chicken = try #require(PurineReference.match("Chicken breast, roasted"))
        let yogurt = try #require(PurineReference.match("Greek yogurt with honey"))
        let apple = try #require(PurineReference.match("Apple"))

        #expect(liver.milligramsPer100g > chicken.milligramsPer100g)
        #expect(sardines.milligramsPer100g > chicken.milligramsPer100g)
        #expect(chicken.milligramsPer100g > yogurt.milligramsPer100g)
        #expect(yogurt.milligramsPer100g <= 10)
        #expect(apple.milligramsPer100g <= 10)
    }

    @Test func longestKeywordWinsOverAGenericOne() throws {
        #expect(try #require(PurineReference.match("chicken liver pâté")).name == "Chicken liver")
        #expect(try #require(PurineReference.match("peanut butter sandwich")).name == "Peanut butter")
        #expect(try #require(PurineReference.match("Non-alcoholic beer")).name == "Non-alcoholic beer")
        #expect(try #require(PurineReference.match("sweet potato fries")).name == "Sweet potato")
    }

    @Test func matchingIsWholeWordAndHandlesPlurals() {
        #expect(PurineReference.match("Two scrambled eggs")?.name == "Eggs")
        #expect(PurineReference.match("Cherries")?.name == "Blueberries")
        // "cheeseburger" is its own entry, not a hit on "cheese".
        #expect(PurineReference.match("Cheeseburger")?.name == "Hamburger")
        #expect(PurineReference.match("Mystery casserole") == nil)
        #expect(PurineReference.match("") == nil)
    }

    @Test func estimateScalesByServingSizeAndAssumesAHundredGramsWhenUnknown() throws {
        let sardines = try #require(PurineReference.match("sardines"))
        let known = PurineReference.estimateMilligrams(name: "Sardines", grams: 50, ingredients: [])
        let unknown = PurineReference.estimateMilligrams(name: "Sardines", grams: nil, ingredients: [])

        #expect(known == sardines.milligramsPer100g / 2)
        #expect(unknown == sardines.milligramsPer100g)
    }

    @Test func ingredientBreakdownsAreSummedByGramsAndBeatTheMealName() throws {
        let ingredients = [
            MealIngredient(name: "Chicken breast", grams: 150, calories: 250, protein: 46, carbs: 0, fat: 5),
            MealIngredient(name: "White rice", grams: 200, calories: 260, protein: 5, carbs: 56, fat: 0),
            MealIngredient(name: "Unknown garnish", grams: 20, calories: 10, protein: 0, carbs: 2, fat: 0),
        ]
        let chicken = try #require(PurineReference.match("chicken breast")).milligramsPer100g
        let rice = try #require(PurineReference.match("white rice")).milligramsPer100g

        let estimate = PurineReference.estimateMilligrams(name: "Mystery bowl", grams: 370, ingredients: ingredients)

        #expect(estimate == ((chicken * 1.5 + rice * 2) * 10).rounded() / 10)
    }

    @Test func fallbackFillsOnlyMissingValues() {
        var fromTable = FoodEntry(name: "Sardines", calories: 200, protein: 25, carbs: 0, fat: 11, source: .manual, servingSizeGrams: 100)
        PurineReference.applyFallbackIfNeeded(&fromTable)
        #expect(fromTable.supplementalNutrients["purines"] == 345)

        var fromAI = FoodEntry(name: "Sardines", calories: 200, protein: 25, carbs: 0, fat: 11, source: .snapFood,
                               supplementalNutrients: ["purines": 120], servingSizeGrams: 100)
        PurineReference.applyFallbackIfNeeded(&fromAI)
        #expect(fromAI.supplementalNutrients["purines"] == 120)

        var unknown = FoodEntry(name: "Mystery casserole", calories: 200, protein: 10, carbs: 20, fat: 8, source: .manual)
        PurineReference.applyFallbackIfNeeded(&unknown)
        #expect(unknown.supplementalNutrients["purines"] == nil)
    }

    @Test func foodStoreAppliesTheFallbackWhenAnEntryIsAdded() {
        let suite = "PurineReferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)
        let day = Date(timeIntervalSince1970: 1_752_840_000)

        #expect(store.addEntry(FoodEntry(name: "Beef liver", calories: 150, protein: 20, carbs: 4, fat: 5, timestamp: day, source: .manual, servingSizeGrams: 100)))
        #expect(store.addEntry(FoodEntry(name: "Lentils", calories: 230, protein: 18, carbs: 40, fat: 1, timestamp: day, source: .barcode,
                                         supplementalNutrients: ["purines": 10], servingSizeGrams: 200)))

        #expect(store.supplementalNutrient(.purines, for: day) == 220 + 10)
    }
}
