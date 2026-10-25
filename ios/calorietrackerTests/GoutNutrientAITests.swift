import Foundation
import Testing
@testable import calorietracker

/// The AI JSON schema and parsers carry purines (mg) and alcohol (g) alongside the
/// other supplemental nutrients, for both whole-food and per-100 g label analyses.
@MainActor
struct GoutNutrientAITests {
    @Test func foodAnalysisKeepsPurinesAndAlcohol() throws {
        let analysis = try GeminiService.parseFoodAnalysis(from: """
        {"name":"Sardines","calories":208,"protein":25,"carbs":0,"fat":11,"serving_size_grams":100,
         "sodium":307,"purines":345,"alcohol":0,"unit_options":[]}
        """)

        #expect(analysis.supplementalNutrients["purines"] == 345)
        #expect(analysis.supplementalNutrients["alcohol"] == 0)
        #expect(analysis.sodium == 307)
    }

    @Test func foodAnalysisWithoutPurinesLeavesTheBagEmpty() throws {
        let analysis = try GeminiService.parseFoodAnalysis(
            from: #"{"name":"Apple","calories":95,"protein":0.5,"carbs":25,"fat":0.3,"serving_size_grams":180,"unit_options":[]}"#
        )

        #expect(analysis.supplementalNutrients["purines"] == nil)
        #expect(analysis.supplementalNutrients["alcohol"] == nil)
    }

    @Test func labelAnalysisScalesPurinesPerHundredGrams() throws {
        let label = try GeminiService.parseNutritionLabel(from: """
        {"name":"Anchovy paste","calories_per_100g":180,"protein_per_100g":20,"carbs_per_100g":2,"fat_per_100g":10,
         "serving_size_grams":15,"purines_per_100g":400,"alcohol_per_100g":0,"unit_options":[]}
        """)

        #expect(label.supplementalNutrientsPer100g["purines"] == 400)
        let serving = label.scaled(to: 50)
        #expect(serving.supplementalNutrients["purines"] == 200)
    }

    @Test func foodPromptAsksForPurinesInMilligramsAndAlcoholInGrams() {
        let instruction = GeminiService.foodNutrientInstruction(includingAminoAcids: false)

        #expect(instruction.contains("purines is milligrams"))
        #expect(instruction.contains("alcohol is grams of ethanol"))
        #expect(instruction.contains("organ meats"))
        #expect(instruction.contains("always estimate both for every food"))
    }
}
