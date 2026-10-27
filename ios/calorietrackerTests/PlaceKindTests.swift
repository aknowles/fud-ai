import Foundation
import Testing
@testable import calorietracker

/// Kinds of food place on a collection, typical menus, and what Coach hears.
@MainActor
struct PlaceKindTests {
    private func snack(_ name: String) -> FoodEntry {
        FoodEntry(name: name, calories: 300, protein: 10, carbs: 30, fat: 12, source: .snapFood)
    }

    @Test func theOldCoffeeBarSwitchReadsAsAKindAndMigratesOnChange() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","name":"Office","items":[],"coffeeBar":true}]"#
        let defaults = try #require(UserDefaults(suiteName: "PlaceKindTests-\(UUID())"))
        defaults.set(Data(json.utf8), forKey: FoodCollectionStore.storageKey)
        let store = FoodCollectionStore(defaults: defaults)
        let office = try #require(store.collections.first)
        #expect(office.placeKinds.map(\.raw) == ["coffeeBar"])
        #expect(office.hasCoffeeBar)

        store.toggleKind(PlaceKind.pizza.rawValue, for: office.id)
        let migrated = try #require(FoodCollectionStore(defaults: defaults).collection(id: office.id))
        #expect(migrated.kinds == ["coffeeBar", "pizza"])
        #expect(migrated.coffeeBar == nil)
    }

    @Test func ownKindsToggleIgnoringCaseAndRemovingAKindDropsItsMenu() throws {
        let defaults = try #require(UserDefaults(suiteName: "PlaceKindTests-\(UUID())"))
        let store = FoodCollectionStore(defaults: defaults)
        let office = try #require(store.create(named: "Office"))
        store.toggleKind(" Sushi counter ", for: office.id)
        var sushi = snack("Salmon roll")
        sushi.imageFilename = "roll.jpg"
        store.setTypicalMenu([sushi], for: "Sushi counter", in: office.id)

        let saved = try #require(store.collection(id: office.id))
        #expect(saved.placeKinds.map(\.displayName) == ["Sushi counter"])
        #expect(saved.typicalMenu(for: PlaceKindKey(raw: "Sushi counter")).first?.imageFilename == nil)
        #expect(saved.onHandEntries.map(\.name) == ["Salmon roll"])

        store.toggleKind("sushi COUNTER", for: office.id)
        let cleared = try #require(FoodCollectionStore(defaults: defaults).collection(id: office.id))
        #expect(cleared.kinds == nil)
        #expect(cleared.typicalMenus == nil)
    }

    @Test func onHandEntriesCombineItemsDrinksAndMenusWithoutRepeats() {
        let pretzels = snack("Pretzels")
        let collection = FoodCollection(name: "Office", items: [pretzels], kinds: ["coffeeBar", "vendingMachine"])
        var withMenu = collection
        withMenu.typicalMenus = ["vendingMachine": [snack("Pretzels"), snack("Trail mix")]]
        let names = withMenu.onHandEntries.map(\.name)
        #expect(names.first == "Pretzels")
        #expect(names.filter { $0 == "Pretzels" }.count == 1)
        #expect(names.contains("Trail mix"))
        #expect(names.contains { $0.contains("latte") || $0.contains("Latte") })
    }

    @Test func coachHearsTheKindsAndOwnWords() {
        let collection = FoodCollection(name: "Office", kinds: ["vendingMachine", "taco truck"])
        let lines = HealthContextPrompt.onHandLines([collection])
        #expect(lines.contains { $0.hasPrefix("- Office: Here: a vending machine (") && $0.contains("; taco truck. Assume anything typical") })
    }

    @Test func theTypicalMenuPromptDescribesThePlaceAndAsksForFoods() {
        let prompt = TypicalMenuService.prompt(for: PlaceKindKey(raw: PlaceKind.pizza.rawValue), healthLines: ["- Gout: favor low-purine choices"])
        #expect(prompt.contains("a pizza place (slices"))
        #expect(prompt.contains("- Gout: favor low-purine choices"))
        #expect(prompt.contains(#""foods""#))
        #expect(PlaceKind.vendingMachine.prefersScan)
        #expect(!PlaceKind.pizza.prefersScan)
    }
}
