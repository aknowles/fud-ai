import Foundation
import Testing
@testable import calorietracker

/// Celiac, lactose and the user's own terms, matched by whole word on names, ingredients
/// and product allergen lists, with "gluten-free" and plant milks left alone.
@MainActor
struct AvoidListTests {
    @Test func celiacMatchesGlutenFoodsButNotGlutenFreeOnes() {
        let list = AvoidList(celiac: true)

        #expect(list.matches(texts: ["Turkey sandwich on wheat bread"]) == ["gluten (celiac disease)"])
        #expect(list.matches(texts: ["Spaghetti with meatballs", "Pasta"]) == ["gluten (celiac disease)"])
        #expect(list.matches(texts: ["Gluten-free bread"]).isEmpty)
        #expect(list.matches(texts: ["Buckwheat soba"]).isEmpty)
        #expect(list.matches(texts: ["Rice bowl with chicken"]).isEmpty)
    }

    @Test func lactoseMatchesMilkButNotPlantMilks() {
        let list = AvoidList(lactose: true)

        #expect(list.matches(texts: ["Ice cream sundae"]) == ["lactose"])
        #expect(list.matches(texts: ["Cereal with milk"]) == ["lactose"])
        #expect(list.matches(texts: ["Oat milk latte"]).isEmpty)
        #expect(list.matches(texts: ["Lactose-free milk"]).isEmpty)
    }

    @Test func customTermsMatchNamesIngredientsAndAllergensWithPlurals() {
        let list = AvoidList(custom: ["peanut", "shellfish"])
        var bar = FoodEntry(name: "Granola bar", calories: 190, protein: 4, carbs: 25, fat: 7, source: .barcode)
        bar.productMetadata = FoodProductMetadata(barcode: "1", ingredientsText: "oats, honey", allergens: ["en:peanuts"],
                                                  traces: [], labels: [], categories: [])

        #expect(list.matches(for: bar) == ["peanut"])
        #expect(list.matches(texts: ["Pad thai with peanuts"]) == ["peanut"])
        #expect(list.matches(texts: ["Shrimp", "Shellfish platter"]) == ["shellfish"])
        #expect(list.matches(texts: ["Chicken salad"]).isEmpty)
    }

    @Test func profilesSavedBeforeTheListExistedStillDecode() throws {
        let old = Data(#"{"entries":["gout","dash"]}"#.utf8)

        let profile = try JSONDecoder().decode(HealthProfile.self, from: old)

        #expect(profile.entries == [.gout, .dash])
        #expect(profile.avoidList.isEmpty)
    }

    @Test func theListPersistsAndAnEmptyListIsDropped() {
        let suite = "AvoidListTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HealthProfileStore(defaults: defaults)

        store.setAvoidList(AvoidList(celiac: true, custom: ["sesame"]))
        #expect(HealthProfileStore(defaults: defaults).profile.avoidList == AvoidList(celiac: true, custom: ["sesame"]))

        store.setAvoidList(AvoidList())
        #expect(HealthProfileStore(defaults: defaults).profile.avoid == nil)
    }

    @Test func coachIsToldWhatToAvoidEvenWithNoConditions() {
        let profile = HealthProfile(entries: [], avoid: AvoidList(celiac: true, lactose: true, custom: ["peanut"]))

        let lines = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: profile, plan: [])

        #expect(lines.contains("- Foods to avoid: gluten (celiac disease), lactose and peanut. Never suggest a food that contains them, and say so when an option might."))
        #expect(!lines.contains { $0.contains("Today") })
    }
}
