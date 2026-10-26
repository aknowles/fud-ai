import Foundation
import Testing
@testable import calorietracker

/// Phosphorus, oxalate and tyramine ride in `FoodEntry.supplementalNutrients` like purines,
/// for kidney disease, kidney stones and MAOI diets. All three are milligram limits.
@MainActor
struct KidneyNutrientTests {
    private let added: [OptionalNutrient] = [.phosphorus, .oxalate, .tyramine]

    @Test func eachIsASupplementalMilligramLimitWithAGoalInRange() {
        for nutrient in added {
            #expect(SupplementalNutrient(rawValue: nutrient.rawValue)?.optionalNutrient == nutrient)
            #expect(OptionalNutrient(jsonKey: nutrient.jsonKey) == nutrient)
            #expect(nutrient.unit == "mg", "\(nutrient)")
            #expect(nutrient.goalStyle == "limit", "\(nutrient)")
            #expect(nutrient.range.contains(nutrient.defaultGoal), "\(nutrient)")
            #expect(nutrient.defaultGoal % nutrient.step == 0, "\(nutrient)")
        }
        #expect(OptionalNutrient.phosphorus.defaultGoal == 1_000)
        #expect(OptionalNutrient.oxalate.defaultGoal == 100)
        #expect(OptionalNutrient.tyramine.defaultGoal == 10)
    }

    @Test func goalsSavedBeforeTheseExistedPickUpTheDefaults() throws {
        let old = try JSONEncoder().encode(["values": ["sodium": 1_500]])

        let goals = OptionalNutrientGoals.decoded(from: old)

        #expect(goals.goal(for: .sodium) == 1_500)
        #expect(goals.goal(for: .phosphorus) == 1_000)
        #expect(goals.goal(for: .oxalate) == 100)
        #expect(goals.goal(for: .tyramine) == 10)
    }

    @Test func valuesSurviveAnEntryRoundTrip() throws {
        let entry = FoodEntry(name: "Spinach salad", calories: 120, protein: 5, carbs: 10, fat: 7, source: .manual,
                              supplementalNutrients: ["phosphorus": 85, "oxalate": 650, "tyramine": 0])

        let decoded = try JSONDecoder().decode(FoodEntry.self, from: JSONEncoder().encode(entry))

        #expect(decoded.supplementalNutrients["phosphorus"] == 85)
        #expect(decoded.supplementalNutrients["oxalate"] == 650)
        #expect(decoded.supplementalNutrients["tyramine"] == 0)
    }
}
