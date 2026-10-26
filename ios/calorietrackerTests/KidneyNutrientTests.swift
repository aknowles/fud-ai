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

/// The AI schema, label parser and prompt carry phosphorus, oxalate and tyramine.
@MainActor
struct KidneyNutrientAITests {
    @Test func foodAnalysisKeepsTheNewNutrients() throws {
        let analysis = try GeminiService.parseFoodAnalysis(from: """
        {"name":"Spinach salad with almonds","calories":220,"protein":8,"carbs":12,"fat":16,"serving_size_grams":150,
         "phosphorus":160,"oxalate":720,"tyramine":0,"purines":40,"unit_options":[]}
        """)

        #expect(analysis.supplementalNutrients["phosphorus"] == 160)
        #expect(analysis.supplementalNutrients["oxalate"] == 720)
        #expect(analysis.supplementalNutrients["tyramine"] == 0)
    }

    @Test func labelAnalysisScalesThemPerHundredGrams() throws {
        let label = try GeminiService.parseNutritionLabel(from: """
        {"name":"Aged cheddar","calories_per_100g":400,"protein_per_100g":25,"carbs_per_100g":1,"fat_per_100g":33,
         "serving_size_grams":30,"phosphorus_per_100g":500,"oxalate_per_100g":0,"tyramine_per_100g":20,"unit_options":[]}
        """)

        let serving = label.scaled(to: 30)
        #expect(serving.supplementalNutrients["phosphorus"] == 150)
        #expect(serving.supplementalNutrients["tyramine"] == 6)
    }

    @Test func foodPromptAsksForAllThreeInMilligrams() {
        let instruction = GeminiService.foodNutrientInstruction(includingAminoAcids: false)

        #expect(instruction.contains("phosphorus, oxalate and tyramine are milligrams"))
        #expect(instruction.contains("always estimate all three for every food"))
        #expect(instruction.contains("spinach"))
        #expect(instruction.contains("aged cheeses"))
    }
}
