import Foundation
import Testing
@testable import calorietracker

/// Breaking a day's total down by food, and the health profile starting empty with a setup card.
@MainActor
struct NutrientContributorsTests {
    private func food(_ name: String, calories: Int = 200, purines: Double? = nil, sodium: Double? = nil) -> FoodEntry {
        FoodEntry(name: name, calories: calories, protein: 10, carbs: 20, fat: 5, source: .manual,
                  supplementalNutrients: purines.map { ["purines": $0] } ?? [:], sodium: sodium)
    }

    @Test func contributionsAreLargestFirstWithShares() {
        let entries = [food("Toast", purines: 20), food("Sardines", purines: 300), food("Apple"), food("Beer", purines: 80)]

        let contributions = NutrientContribution.make(.nutrient(.purines), entries: entries)

        #expect(contributions.map(\.entry.name) == ["Sardines", "Beer", "Toast"])
        #expect(abs(contributions[0].share - 0.75) < 0.0001)
        #expect(abs(contributions.reduce(0) { $0 + $1.share } - 1) < 0.0001)
    }

    @Test func caloriesAndMacrosBreakDownToo() {
        let entries = [food("Pizza", calories: 700), food("Salad", calories: 150)]

        #expect(NutrientContribution.make(.calories, entries: entries).map(\.amount) == [700, 150])
        #expect(NutrientContribution.make(.protein, entries: entries).count == 2)
    }

    @Test func tableEstimatesAreLabeled() throws {
        var sardines = food("Canned sardines", purines: nil)
        sardines.servingSizeGrams = 100
        let estimate = try #require(PurineReference.estimateMilligrams(for: sardines))

        #expect(NutrientMetric.nutrient(.purines).estimateNote(for: sardines, amount: estimate) == "built-in table")
        #expect(NutrientMetric.nutrient(.purines).estimateNote(for: sardines, amount: estimate + 50) == nil)
        #expect(NutrientMetric.calories.estimateNote(for: sardines, amount: 200) == nil)
    }
}
