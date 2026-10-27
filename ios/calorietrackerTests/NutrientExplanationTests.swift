import Testing
@testable import calorietracker

struct NutrientExplanationTests {
    @Test func everyNutrientAHealthRuleWatchesIsExplained() {
        let watched = Set(HealthEntryKind.allCases.flatMap { $0.rules.map(\.nutrient) })
        for nutrient in watched {
            #expect(nutrient.plainExplanation != nil, "No explanation for \(nutrient)")
        }
    }

    @Test func sugarAndAddedSugarSayHowTheyDiffer() throws {
        #expect(try #require(OptionalNutrient.sugar.plainExplanation).contains("Added sugar is part of this total"))
        #expect(try #require(OptionalNutrient.addedSugar.plainExplanation).contains("Guidelines limit this part"))
    }
}
