import Foundation
import Testing
@testable import calorietracker

/// Serving amounts stay exact through unit switches and ingredient saves, and diary rows
/// show each logged amount once in a unit that fits it.
@MainActor
struct FoodUnitsServingTests {
    private let us = UnitConfig(system: .us)
    private let metric = UnitConfig(system: .metric)

    private func entry(_ name: String, grams: Double, options: [ServingUnitOption], unit: String?, quantity: Double?) -> FoodEntry {
        var entry = FoodEntry(name: name, calories: 480, protein: 32, carbs: 40, fat: 20, source: .manual)
        entry.servingSizeGrams = grams
        entry.servingUnitOptions = options
        entry.selectedServingUnit = unit
        entry.selectedServingQuantity = quantity
        return entry
    }

    private let bowl = ServingUnitOption(unit: "bowl", gramsPerUnit: 340, quantity: 1)

    @Test func diaryShowsAnOunceAmountOnce() {
        let chili = entry("Beef chili", grams: 340, options: [bowl], unit: "oz", quantity: 12)
        #expect(FoodUnits.loggedServingText(grams: 340, entry: chili, config: us) == "12 oz")
    }

    @Test func diaryShowsACountWithItsWeight() {
        let chili = entry("Beef chili", grams: 170, options: [bowl], unit: "bowl", quantity: 0.5)
        #expect(FoodUnits.loggedServingText(grams: 170, entry: chili, config: us) == "0.5 bowls (~6 oz)")
        #expect(FoodUnits.loggedServingText(grams: 170, entry: chili, config: metric) == "0.5 bowls (~170 g)")
    }

    /// 355 saved with ml is 12 fl oz under US units, never 355 fl oz; and the reverse in metric.
    @Test func diaryWorksOutACountThatNoLongerFitsTheMappedUnit() {
        let ml = ServingUnitOption(unit: "ml", gramsPerUnit: 1, quantity: 355)
        let coldBrew = entry("Nitro cold brew", grams: 355, options: [ml], unit: "ml", quantity: 355)
        #expect(FoodUnits.loggedServingText(grams: 355, entry: coldBrew, config: us) == "12 fl oz")
        let flOz = ServingUnitOption(unit: "fl oz", gramsPerUnit: 29.5735, quantity: 12)
        let soda = entry("Cola", grams: 355, options: [flOz], unit: "fl oz", quantity: 12)
        #expect(FoodUnits.loggedServingText(grams: 355, entry: soda, config: metric) == "355 ml")
    }

    @Test func diaryWithoutAUnitShowsTheAmount() {
        let steak = entry("Steak", grams: 340, options: [], unit: nil, quantity: nil)
        #expect(FoodUnits.loggedServingText(grams: 340, entry: steak, config: us) == "12 oz")
    }

    /// Switching from 1 bowl to oz shows "12"; that text must keep 340 g, not become 340.2 g.
    @Test func unchangedQuantityTextKeepsTheExactGrams() {
        let ounce = FoodUnits.ounce
        #expect(FoodUnits.grams(forQuantityText: "12", option: ounce, currentGrams: 340) == 340)
        #expect(FoodUnits.grams(forQuantityText: "1", option: bowl, currentGrams: 340) == 340)
        // Two bowls in ounces read "24"; switching back keeps 680 g exactly.
        #expect(FoodUnits.grams(forQuantityText: "24", option: ounce, currentGrams: 680) == 680)
    }

    @Test func typedQuantitiesStillChangeTheGrams() {
        #expect(FoodUnits.grams(forQuantityText: "0.5", option: bowl, currentGrams: 340) == 170)
        #expect(FoodUnits.grams(forQuantityText: "6", option: FoodUnits.ounce, currentGrams: 340) == 6 * FoodUnits.gramsPerOunce)
        #expect(FoodUnits.grams(forQuantityText: "1/2", option: bowl, currentGrams: 340) == 170)
        #expect(FoodUnits.grams(forQuantityText: "", option: bowl, currentGrams: 340) == nil)
        #expect(FoodUnits.grams(forQuantityText: "0", option: bowl, currentGrams: 340) == nil)
    }

    /// A 200 g ingredient opens at "7.1" oz; saving that text unchanged keeps 200 g.
    @Test func unchangedIngredientWeightKeepsTheExactGrams() {
        #expect(FoodUnits.fieldText(grams: 200, config: us) == "7.1")
        #expect(FoodUnits.grams(fromField: 7.1, text: "7.1", original: 200, config: us) == 200)
        #expect(FoodUnits.grams(fromField: 4, text: "4", original: 200, config: us) == 4 * FoodUnits.gramsPerOunce)
        #expect(FoodUnits.grams(fromField: 150, text: "150", original: 200, config: metric) == 150)
    }

    /// The AI's options are held to 15% or 5 g, so a 7 g "1 tsp" stays one teaspoon.
    @Test func smallServingsKeepTheirCount() {
        let tsp = ServingUnitOption(unit: "tsp", gramsPerUnit: 4.2, quantity: 1)
        #expect(FoodUnits.storedQuantity(1, fits: tsp, totalGrams: 7) == 1)
        #expect(FoodUnits.storedQuantity(3, fits: tsp, totalGrams: 7) == nil)
    }
}
