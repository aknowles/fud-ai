import Foundation
import Testing
@testable import calorietracker

/// Grapefruit, cranberry and high-tyramine flags come from the food's name, ingredients,
/// product ingredient list and tyramine estimate.
@MainActor
struct FoodFlagTests {
    private func entry(_ name: String, ingredients: [String] = [], productIngredients: String? = nil,
                       tyramine: Double? = nil) -> FoodEntry {
        var entry = FoodEntry(
            name: name, calories: 100, protein: 1, carbs: 10, fat: 1, source: .manual,
            supplementalNutrients: tyramine.map { ["tyramine": $0] } ?? [:],
            ingredients: ingredients.map { MealIngredient(name: $0, grams: 50, calories: 50, protein: 0, carbs: 5, fat: 0) }
        )
        if let productIngredients {
            entry.productMetadata = FoodProductMetadata(barcode: "0", ingredientsText: productIngredients, allergens: [], traces: [],
                                                       labels: [], categories: [])
        }
        return entry
    }

    @Test func namesFlagGrapefruitCranberryAndTyramineFoods() {
        #expect(entry("Ruby red grapefruit juice").foodFlags == [.grapefruit])
        #expect(entry("Pomelo salad").foodFlags == [.grapefruit])
        #expect(entry("Cranberry sauce").foodFlags == [.cranberry])
        #expect(entry("Aged cheddar on crackers").foodFlags == [.highTyramine])
        #expect(entry("Pepperoni pizza").foodFlags == [.highTyramine])
        #expect(entry("Orange juice").foodFlags.isEmpty)
        #expect(entry("Fresh mozzarella").foodFlags.isEmpty)
    }

    @Test func ingredientsAndProductIngredientListsCount() {
        #expect(entry("Breakfast bowl", ingredients: ["Yogurt", "Dried cranberries"]).foodFlags == [.cranberry])
        #expect(entry("Citrus soda", productIngredients: "Water, sugar, grapefruit juice concentrate").foodFlags == [.grapefruit])
        #expect(entry("Stir fry", ingredients: ["Chicken", "Soy sauce"]).foodFlags == [.highTyramine])
    }

    @Test func aTyramineEstimateOfSixMilligramsOrMoreIsHigh() {
        #expect(entry("Mystery dish", tyramine: 6).foodFlags == [.highTyramine])
        #expect(entry("Mystery dish", tyramine: 5.9).foodFlags.isEmpty)
        #expect(entry("Mystery dish").foodFlags.isEmpty)
    }
}
