import Foundation
import Testing
@testable import calorietracker

@MainActor
struct HydrationTests {
    private func drink(_ name: String, ml: Double?, addedSugar: Double? = nil, alcohol: Double? = nil) -> FoodEntry {
        FoodEntry(name: name, calories: 50, protein: 0, carbs: 0, fat: 0, source: .manual, addedSugar: addedSugar,
                  supplementalNutrients: alcohol.map { [OptionalNutrient.alcohol.rawValue: $0] } ?? [:],
                  servingSizeGrams: ml)
    }

    @Test func unsweetenedAlcoholFreeDrinksCountByVolume() {
        #expect(Hydration.milliliters(for: drink("Sparkling water", ml: 355)) == 355)
        #expect(Hydration.milliliters(for: drink("Green tea", ml: 240)) == 240)
        #expect(Hydration.milliliters(for: CoffeeOrder(drink: .latte, size: .small, milk: .oat).entry()) == 355)
        #expect(Hydration.milliliters(for: drink("Iced coffee", ml: 473, addedSugar: 3)) == 473)
    }

    @Test func sweetAlcoholicAndNonDrinkFoodsDoNotCount() {
        #expect(Hydration.milliliters(for: drink("Orange juice", ml: 240)) == 0)
        #expect(Hydration.milliliters(for: drink("Cola", ml: 355)) == 0)
        #expect(Hydration.milliliters(for: drink("Sweet tea", ml: 473, addedSugar: 30)) == 0)
        #expect(Hydration.milliliters(for: drink("Beer", ml: 355, alcohol: 14)) == 0)
        #expect(Hydration.milliliters(for: drink("Bubble tea", ml: 500)) == 0)
        #expect(Hydration.milliliters(for: drink("Chicken sandwich", ml: 220)) == 0)
        #expect(Hydration.milliliters(for: drink("Black coffee", ml: nil)) == 0)
        #expect(Hydration.milliliters(for: CoffeeOrder(drink: .matchaLatte).entry()) == 0)
    }

    @Test func waterIsSuggestedForGoutOrStonesButNeverWithKidneyDisease() throws {
        #expect(WaterSuggestion.applies(to: HealthProfile(entries: [.gout])))
        #expect(WaterSuggestion.applies(to: HealthProfile(entries: [.kidneyStones, .dash])))
        #expect(!WaterSuggestion.applies(to: HealthProfile(entries: [.dash])))
        #expect(!WaterSuggestion.applies(to: HealthProfile(entries: [.gout, .kidneyDisease])))

        let defaults = try #require(UserDefaults(suiteName: "HydrationTests-\(UUID())"))
        #expect(WaterSuggestion.shouldShow(profile: HealthProfile(entries: [.gout]), defaults: defaults))
        WaterSuggestion.accept(defaults: defaults)
        #expect(defaults.bool(forKey: WaterSettings.enabledKey))
        #expect(defaults.integer(forKey: WaterSettings.dailyGoalKey) == 2_500)
        #expect(!WaterSuggestion.shouldShow(profile: HealthProfile(entries: [.gout]), defaults: defaults))

        let higher = try #require(UserDefaults(suiteName: "HydrationTests-\(UUID())"))
        higher.set(3_000, forKey: WaterSettings.dailyGoalKey)
        WaterSuggestion.accept(defaults: higher)
        #expect(higher.integer(forKey: WaterSettings.dailyGoalKey) == 3_000)
    }
}
