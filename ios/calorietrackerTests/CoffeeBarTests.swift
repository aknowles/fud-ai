import Foundation
import Testing
@testable import calorietracker

/// Coffee-bar drinks from the reference table, the usual order, and coffee bars on collections.
@MainActor
struct CoffeeBarTests {
    @Test func aMediumLatteAddsMilkAndTwoShots() {
        let entry = CoffeeOrder().entry()
        #expect(entry.name == "Latte (medium)")
        // 12 oz whole milk at 18.6 kcal plus two 3 kcal shots.
        #expect(entry.calories == 229)
        #expect(entry.sugar == 18)
        #expect(entry.addedSugar == 0)
        #expect(entry.caffeine == 150)
        #expect(entry.calcium == 408)
        #expect(entry.supplementalNutrients[OptionalNutrient.purines.rawValue] == 0)
        #expect(entry.emoji == "☕️")
    }

    @Test func namesDescribeTheOrder() {
        #expect(CoffeeOrder(drink: .matchaLatte, size: .small, milk: .oat, iced: true).entry().name == "Iced oat matcha latte (small)")
        #expect(CoffeeOrder(drink: .americano, size: .large, milk: .almond).entry().name
                == "Americano with a splash of almond milk (large)")
        #expect(CoffeeOrder(drink: .latte, milk: .twoPercent, syrupPumps: 2).entry().name == "2% latte, 2 pumps syrup (medium)")
    }

    @Test func sizeIceAndSyrupChangeTheNumbers() {
        let hot = CoffeeOrder(drink: .latte, size: .large).nutrition
        let iced = CoffeeOrder(drink: .latte, size: .large, iced: true).nutrition
        #expect(iced.calories < hot.calories)
        #expect(iced.caffeine == 225)
        #expect(hot.caffeine == 150)

        let plain = CoffeeOrder(drink: .latte, milk: .skim).nutrition
        let sweet = CoffeeOrder(drink: .latte, milk: .skim, syrupPumps: 3).nutrition
        #expect(sweet.calories - plain.calories == 60)
        #expect(sweet.addedSugar == 15)

        #expect(CoffeeOrder(drink: .brewedCoffee, milk: .none).entry().calories == 5)
        #expect(CoffeeOrder(drink: .chaiLatte, milk: .twoPercent).entry().addedSugar == 25)
    }

    @Test func startersLeadWithTheUsualAndShareItsMilk() {
        let usual = CoffeeOrder(drink: .matchaLatte, size: .small, milk: .oat)
        let starters = FoodCollection.coffeeStarters(usual: usual)
        #expect(starters.first?.name == "Oat matcha latte (small)")
        #expect(starters.contains { $0.name == "Oat latte (small)" })
        #expect(starters.contains { $0.name == "Americano (small)" })
        #expect(starters.filter { $0.name.contains("matcha") }.count == 1)
    }

    @Test func aCoffeeBarCollectionIsOnHandWithoutItemsAndCoachHearsIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "CoffeeBarTests-\(UUID())"))
        let store = FoodCollectionStore(defaults: defaults)
        let cafe = try #require(store.create(named: "Office cafe"))
        store.setSchedule(CollectionSchedule(weekdays: Set(1...7), startMinute: 0, endMinute: 24 * 60 - 1), for: cafe.id)
        #expect(store.activeCollections(at: nil).isEmpty)

        store.setCoffeeBar(true, for: cafe.id)
        store.setAlsoHere("  fruit basket  ", for: cafe.id)
        let reloaded = FoodCollectionStore(defaults: defaults)
        let active = reloaded.activeCollections(at: nil)
        #expect(active.map(\.name) == ["Office cafe"])
        #expect(active.first?.alsoHere == "fruit basket")

        let lines = HealthContextPrompt.onHandLines(active)
        #expect(lines.contains { $0.hasPrefix("- Office cafe: There is a coffee bar") && $0.hasSuffix("Also here: fruit basket.") })

        reloaded.setCoffeeBar(false, for: cafe.id)
        reloaded.setAlsoHere(" ", for: cafe.id)
        let cleared = try #require(FoodCollectionStore(defaults: defaults).collection(id: cafe.id))
        #expect(cleared.coffeeBar == nil)
        #expect(cleared.alsoHere == nil)
    }

    @Test func theUsualOrderIsRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "CoffeeUsual-\(UUID())"))
        #expect(CoffeeUsual.load(defaults) == nil)
        let order = CoffeeOrder(drink: .flatWhite, size: .small, milk: .oat)
        CoffeeUsual.save(order, defaults)
        #expect(CoffeeUsual.load(defaults) == order)
    }
}
