import Foundation
import Testing
@testable import calorietracker

@MainActor
struct FoodUnitsLiquidTests {
    private let us = UnitConfig(system: .us)
    private let metric = UnitConfig(system: .metric)

    @Test func drinksReadInVolumeNotWeight() {
        // A 20 fl oz bottle of Vitaminwater.
        #expect(FoodUnits.amountText(grams: 591, name: "Vitaminwater", config: us) == "20 fl oz")
        #expect(FoodUnits.amountText(grams: 591, name: "Vitaminwater", config: metric) == "591 ml")
        #expect(FoodUnits.amountText(grams: 355, name: "Diet Coke", config: us) == "12 fl oz")
        #expect(FoodUnits.amountText(grams: 1_500, name: "Sparkling water", config: metric) == "1.5 L")
        #expect(FoodUnits.amountText(grams: 120, name: "Espresso", config: us) == "4 fl oz")
        // Solids stay weights.
        #expect(FoodUnits.amountText(grams: 591, name: "Chicken breast", config: us) == "1 lb 5 oz")
        #expect(FoodUnits.amountText(grams: 80, name: "Coffee cake", config: us) == "3 oz")
        // A volume unit makes anything a liquid.
        #expect(FoodUnits.amountText(grams: 240, name: "Tomato soup", unit: "ml", config: us) == "8 fl oz")
    }

    @Test func volumeTextScalesSensibly() {
        #expect(FoodUnits.volumeText(milliliters: 15, config: us) == "0.5 fl oz")
        #expect(FoodUnits.volumeText(milliliters: 4_000, config: us) == "1.1 gal")
        #expect(FoodUnits.volumeText(milliliters: 250, config: metric) == "250 ml")
        #expect(FoodUnits.volumeText(milliliters: 1_000, config: metric) == "1 L")
    }

    @Test func aLiquidsPickerLeadsWithVolume() {
        let options = [ServingUnitOption(unit: "bottle", gramsPerUnit: 591), ServingUnitOption(unit: "ml", gramsPerUnit: 1)]
        let liquid = FoodUnits.pickerOptions(options, liquid: true, config: us).map(\.id)
        #expect(liquid.first == "fl oz")
        #expect(liquid.contains("oz"))
        #expect(liquid.firstIndex(of: "fl oz")! < liquid.firstIndex(of: "oz")!)
        // Solids keep the usual order: weight first.
        #expect(FoodUnits.pickerOptions(options, liquid: false, config: us).first?.id == "oz")
    }

    @Test func entriesAreLiquidByUnitPackageOrCategory() {
        var bottle = FoodEntry(name: "Kombu dashi", calories: 10, protein: 0, carbs: 0, fat: 0, source: .barcode)
        #expect(!FoodUnits.isLiquid(bottle))
        bottle.productMetadata = FoodProductMetadata(barcode: "1", packageQuantity: "500 ml", ingredientsText: nil, allergens: [],
                                                     traces: [], nutriScore: nil, novaGroup: nil, ecoScore: nil, labels: [],
                                                     categories: [], imageURL: nil)
        #expect(FoodUnits.isLiquid(bottle))
        var tagged = FoodEntry(name: "Brand X Original", calories: 120, protein: 0, carbs: 30, fat: 0, source: .barcode)
        tagged.productMetadata = FoodProductMetadata(barcode: "2", packageQuantity: "20 oz", ingredientsText: nil, allergens: [],
                                                     traces: [], nutriScore: nil, novaGroup: nil, ecoScore: nil, labels: [],
                                                     categories: ["en:beverages", "en:sweetened-beverages"], imageURL: nil)
        #expect(FoodUnits.isLiquid(tagged))
        #expect(Hydration.classify(tagged) != .notADrink)
        let rootBeer = FoodEntry(name: "Root beer", calories: 160, protein: 0, carbs: 42, fat: 0, source: .manual, servingSizeGrams: 355)
        #expect(Hydration.classify(rootBeer) == .counts(355))
    }

    @Test func drinkNamesAreRecognizedButLookAlikesAreNot() {
        for name in ["Vitaminwater", "smartwater", "Diet Coke", "Gatorade", "Oat latte", "Beer", "Coconut water", "Chocolate milk", "Orange juice", "LaCroix"] {
            #expect(FoodUnits.isLiquid(name: name), "\(name)")
        }
        for name in ["Coffee cake", "Soda bread", "Watermelon", "Water crackers", "Milk chocolate", "Pop Tart", "Steak"] {
            #expect(!FoodUnits.isLiquid(name: name), "\(name)")
        }
    }
}
