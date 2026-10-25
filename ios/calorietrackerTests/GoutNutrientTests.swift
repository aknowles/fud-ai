import Foundation
import Testing
@testable import calorietracker

/// Purines and alcohol ride in `FoodEntry.supplementalNutrients`, the same local-only
/// path as creatine and the other sports compounds (no HealthKit type exists for them).
@MainActor
struct GoutNutrientTests {
    @Test func everyOptionalNutrientRoundTripsThroughItsJSONKey() {
        for nutrient in OptionalNutrient.allCases {
            #expect(OptionalNutrient(jsonKey: nutrient.jsonKey) == nutrient, "\(nutrient) did not round-trip")
        }
    }

    @Test func everySupplementalNutrientMapsToAnOptionalNutrientWithTheSameKey() {
        for nutrient in SupplementalNutrient.allCases {
            #expect(nutrient.optionalNutrient.rawValue == nutrient.rawValue)
            #expect(nutrient.optionalNutrient.jsonKey == nutrient.jsonKey)
        }
    }

    @Test func purinesAreAMilligramLimit() {
        #expect(SupplementalNutrient.allCases.contains(.purines))
        #expect(OptionalNutrient.purines.jsonKey == "purines")
        #expect(OptionalNutrient.purines.unit == "mg")
        #expect(OptionalNutrient.purines.goalStyle == "limit")
        #expect(OptionalNutrient.purines.defaultGoal == 400)
        #expect(OptionalNutrient.purines.range.contains(OptionalNutrient.purines.defaultGoal))
        #expect(OptionalNutrient.purines.step == 25)
    }

    @Test func alcoholIsAGramLimit() {
        #expect(SupplementalNutrient.allCases.contains(.alcohol))
        #expect(OptionalNutrient.alcohol.jsonKey == "alcohol")
        #expect(OptionalNutrient.alcohol.unit == "g")
        #expect(OptionalNutrient.alcohol.goalStyle == "limit")
        #expect(OptionalNutrient.alcohol.range.contains(OptionalNutrient.alcohol.defaultGoal))
    }

    @Test func goalsSavedBeforePurinesExistedPickUpTheDefault() throws {
        // A goals blob written by an older build has no purines or alcohol key.
        let legacy = OptionalNutrientGoals(values: ["sodium": 1_500])
        let data = try JSONEncoder().encode(legacy)

        let decoded = OptionalNutrientGoals.decoded(from: data)

        #expect(decoded.goal(for: .sodium) == 1_500)
        #expect(decoded.goal(for: .purines) == OptionalNutrient.purines.defaultGoal)
        #expect(decoded.goal(for: .alcohol) == OptionalNutrient.alcohol.defaultGoal)
    }

    @Test func foodEntryPersistsPurinesAndAlcoholInTheSupplementalBag() throws {
        let entry = FoodEntry(
            name: "Sardines on toast",
            calories: 320,
            protein: 24,
            carbs: 20,
            fat: 14,
            timestamp: Date(timeIntervalSince1970: 1_752_840_000),
            source: .manual,
            supplementalNutrients: [
                SupplementalNutrient.purines.rawValue: 345,
                SupplementalNutrient.alcohol.rawValue: 0,
            ]
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(FoodEntry.self, from: data)

        #expect(decoded.supplementalNutrients["purines"] == 345)
        #expect(decoded.supplementalNutrients["alcohol"] == 0)
        // Older builds decode the same blob and simply ignore the unknown bag keys.
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let bag = try #require(json["supplementalNutrients"] as? [String: Double])
        #expect(bag["purines"] == 345)
    }

    @Test func foodStoreSumsPurinesAndAlcoholForADay() {
        let suite = "GoutNutrientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)
        let day = Date(timeIntervalSince1970: 1_752_840_000)

        #expect(store.addEntry(FoodEntry(
            name: "Liver", calories: 150, protein: 20, carbs: 4, fat: 5, timestamp: day, source: .manual,
            supplementalNutrients: ["purines": 300]
        )))
        #expect(store.addEntry(FoodEntry(
            name: "Beer", calories: 150, protein: 1, carbs: 12, fat: 0, timestamp: day.addingTimeInterval(3_600), source: .manual,
            supplementalNutrients: ["purines": 40, "alcohol": 14]
        )))
        #expect(store.addEntry(FoodEntry(
            name: "Yesterday", calories: 100, protein: 1, carbs: 1, fat: 1, timestamp: day.addingTimeInterval(-86_400), source: .manual,
            supplementalNutrients: ["purines": 999]
        )))

        #expect(store.supplementalNutrient(.purines, for: day) == 340)
        #expect(store.supplementalNutrient(.alcohol, for: day) == 14)
    }
}
