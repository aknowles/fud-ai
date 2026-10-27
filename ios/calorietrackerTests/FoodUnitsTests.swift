import Foundation
import Testing
@testable import calorietracker

/// Food amounts read the way a person would say them, in the configured system with overrides,
/// and portion pickers offer the configured units.
@MainActor
struct FoodUnitsTests {
    private let us = UnitConfig(system: .us)
    private let metric = UnitConfig(system: .metric)

    @Test func usWeightsAreOuncesThenPoundsAndOunces() {
        #expect(FoodUnits.weightText(grams: 5, config: us) == "0.2 oz")
        #expect(FoodUnits.weightText(grams: 113, config: us) == "4 oz")
        #expect(FoodUnits.weightText(grams: 128, config: us) == "4.5 oz")
        #expect(FoodUnits.weightText(grams: 453.6, config: us) == "1 lb")
        #expect(FoodUnits.weightText(grams: 567, config: us) == "1 lb 4 oz")
        #expect(FoodUnits.weightText(grams: 5_000, config: us) == "11 lb")
    }

    @Test func metricWeightsAreGramsThenKilograms() {
        #expect(FoodUnits.weightText(grams: 4.5, config: metric) == "4.5 g")
        #expect(FoodUnits.weightText(grams: 250.4, config: metric) == "250 g")
        #expect(FoodUnits.weightText(grams: 1_260, config: metric) == "1.3 kg")
        #expect(FoodUnits.weightText(grams: 2_000, config: metric) == "2 kg")
    }

    @Test func overridesBeatTheSystem() {
        let usWithGrams = UnitConfig(system: .us, foodWeight: .metric)
        #expect(FoodUnits.weightText(grams: 113, config: usWithGrams) == "113 g")
        #expect(usWithGrams.volumeIsUS)
        let metricWithCups = UnitConfig(system: .metric, foodVolume: .us)
        #expect(!metricWithCups.weightIsUS && metricWithCups.volumeIsUS)
    }

    @Test func usPickersOfferOuncesAndConvertMilliliters() throws {
        let milk = [ServingUnitOption(unit: "ml", gramsPerUnit: 1.03, quantity: 240)]

        let options = FoodUnits.pickerOptions(milk, config: us)

        #expect(options.map(\.id) == ["oz", "fl oz", "cup"])
        let floz = try #require(options.first { $0.id == "fl oz" })
        #expect(abs(floz.gramsPerUnit - 1.03 * 29.5735295625) < 0.001)
        #expect(abs((floz.quantity ?? 0) - 240 / 29.5735295625) < 0.001)
        #expect(FoodUnits.pickerOptions(milk, config: metric).map(\.id) == ["g", "ml"])
    }

    @Test func storedAndSuggestedUnitsMapToTheConfiguredOnes() {
        #expect(FoodUnits.mappedID("g", config: us) == "oz")
        #expect(FoodUnits.mappedID("ml", config: us) == "fl oz")
        #expect(FoodUnits.mappedID("kg", config: us) == "lb")
        #expect(FoodUnits.mappedID("oz", config: metric) == "g")
        #expect(FoodUnits.mappedID("slice", config: us) == "slice")
    }

    @Test func textFieldsRoundTripOuncesAndGrams() {
        #expect(FoodUnits.fieldText(grams: 113.4, config: us) == "4")
        #expect(abs(FoodUnits.grams(fromField: 4, config: us) - 113.398) < 0.01)
        #expect(FoodUnits.fieldText(grams: 150, config: metric) == "150")
        #expect(FoodUnits.grams(fromField: 150, config: metric) == 150)
        #expect(FoodUnits.fieldUnitLabel(us) == "oz")
    }

    @Test func applyingASystemMovesBodyWaterAndHeightUnits() {
        let suite = "FoodUnitsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(UnitOverride.metric.rawValue, forKey: UnitConfig.foodWeightKey)

        UnitConfig.apply(.us, to: defaults)

        #expect(defaults.string(forKey: WeightUnit.storageKey) == "lbs")
        #expect(defaults.string(forKey: HeightUnit.storageKey) == "ftin")
        #expect(defaults.string(forKey: WaterSettings.unitKey) == "floz")
        let config = UnitConfig.load(from: defaults)
        #expect(config.system == .us)
        #expect(config.foodWeight == .metric)
    }
}
