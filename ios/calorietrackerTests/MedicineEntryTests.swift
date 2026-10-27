import Foundation
import Testing
@testable import calorietracker

/// Medicines in the health profile: their nutrient rules, the foods they rule out, and how
/// Coach and Suggestions see them.
@MainActor
struct MedicineEntryTests {
    private let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!

    private func food(_ name: String) -> FoodEntry {
        FoodEntry(name: name, calories: 100, protein: 1, carbs: 20, fat: 0, timestamp: now, source: .manual)
    }

    @Test func conditionsAndMedicinesAreSeparateGroups() {
        #expect(HealthEntryKind.allCases.filter { !$0.isMedicine }.count == 6)
        #expect(HealthEntryKind.allCases.filter(\.isMedicine)
            == [.prednisone, .colchicine, .allopurinol, .grapefruitStatin, .otherStatin, .potassiumRaising, .metformin, .glp1, .maoi,
                .warfarin, .metronidazole, .quinoloneTetracycline, .levothyroxine])
    }

    @Test func anACEInhibitorOrARBConflictsWithDASHOnPotassium() {
        let profile = HealthProfile(entries: [.dash, .potassiumRaising])

        #expect(profile.conflicts == [HealthConflict(nutrient: .potassium,
                                                     raisedBy: [HealthEntryKind.dash.displayName],
                                                     limitedBy: [HealthEntryKind.potassiumRaising.displayName])])
    }

    @Test func eachMedicineAddsItsRulesAndInteractions() {
        func directions(_ kind: HealthEntryKind) -> [OptionalNutrient: HealthRule.Direction] {
            Dictionary(uniqueKeysWithValues: kind.rules.map { ($0.nutrient, $0.direction) })
        }
        #expect(directions(.prednisone) == [.sodium: .limit, .addedSugar: .limit, .calcium: .target, .vitaminD: .target])
        #expect(directions(.metformin) == [.alcohol: .limit, .vitaminB12: .target])
        #expect(directions(.maoi) == [.tyramine: .limit])
        #expect(directions(.potassiumRaising) == [.potassium: .limit])

        #expect(HealthEntryKind.colchicine.avoidedFoodFlags == [.grapefruit])
        #expect(HealthEntryKind.grapefruitStatin.avoidedFoodFlags == [.grapefruit])
        #expect(HealthEntryKind.otherStatin.avoidedFoodFlags.isEmpty)
        #expect(HealthEntryKind.potassiumRaising.avoidedFoodFlags == [.saltSubstitute])
        #expect(HealthEntryKind.maoi.avoidedFoodFlags == [.highTyramine])
        for kind in [HealthEntryKind.allopurinol, .glp1, .otherStatin, .colchicine, .grapefruitStatin] {
            #expect(kind.rules.isEmpty, "\(kind)")
        }
    }

    @Test func theProfileListsEachRuledOutFoodWithItsMedicines() {
        let profile = HealthProfile(entries: [.colchicine, .grapefruitStatin, .maoi])

        let flags = profile.avoidedFoodFlags

        #expect(flags.map(\.flag) == [.grapefruit, .highTyramine])
        #expect(flags.first?.sources == [.colchicine, .grapefruitStatin])
    }

    @Test func saltSubstitutesAreFlaggedButNoSaltAddedFoodsAreNot() {
        #expect(food("NoSalt sodium-free salt alternative").foodFlags == [.saltSubstitute])
        #expect(food("Morton Lite Salt").foodFlags == [.saltSubstitute])
        #expect(food("No salt added black beans").foodFlags.isEmpty)
        #expect(FoodFlag.saltSubstitute.exportKey == "salt_substitute")
    }

    @Test func coachHearsTheMedicineAndAnyClashLoggedToday() {
        let lines = HealthContextPrompt.lines(foods: [food("Grapefruit juice"), food("Toast")], goals: .defaults,
                                              profile: HealthProfile(entries: [.colchicine]), plan: [], symptoms: [], onHand: [], tastes: FoodTastes(), now: now)

        #expect(lines.contains { $0.hasPrefix("- Takes colchicine:") && $0.contains("never suggest them") })
        #expect(lines.contains("- Logged today despite a medicine interaction: Grapefruit juice (grapefruit). Mention it if relevant."))
        #expect(!lines.contains { $0.contains("Today so far") })
    }

    @Test func suggestionsFlagInteractionsAndNeverPickThem() {
        let profile = HealthProfile(entries: [.grapefruitStatin])
        let options = [
            SuggestionOption(entry: food("Citrus salad"), reason: "", tweak: nil, contains: ["grapefruit", "orange"]),
            SuggestionOption(entry: food("Grapefruit half"), reason: "", tweak: nil),
            SuggestionOption(entry: food("Apple"), reason: "", tweak: nil),
        ]

        let ranked = SuggestionRanking.ranked(SuggestionRanking.evaluate(options, today: [], calorieGoal: 2_000,
                                                                         goals: .defaults, profile: profile))

        #expect(ranked.map(\.entry.name) == ["Apple", "Citrus salad", "Grapefruit half"])
        #expect(ranked[1].flags == [.interaction(.grapefruit)])
        #expect(SuggestionRanking.safePick(ranked[2].id, in: ranked) == ranked[0].id)
    }
}
