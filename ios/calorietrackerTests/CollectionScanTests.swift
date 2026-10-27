import Foundation
import Testing
@testable import calorietracker

struct CollectionScanTests {
    @Test func parsesEachFoodOnceWithItsNutrition() throws {
        let reply = """
        ```json
        {"foods":[
          {"name":"KIND Dark Chocolate Nuts & Sea Salt","emoji":"🍫","serving_size_grams":40,"calories":200,"protein":6,"carbs":16,"fat":15,"sodium":125,"contains":["tree nut"]},
          {"name":"Banana","emoji":"🍌","serving_size_grams":118,"calories":105,"protein":1.3,"carbs":27,"fat":0.4,"potassium":422},
          {"name":"banana","emoji":"🍌","serving_size_grams":118,"calories":105,"protein":1.3,"carbs":27,"fat":0.4}
        ]}
        ```
        """
        let foods = try CollectionScanService.parse(reply)
        #expect(foods.map(\.name) == ["KIND Dark Chocolate Nuts & Sea Salt", "Banana"])
        #expect(foods[0].calories == 200)
        #expect(foods[0].sodium == 125)
        #expect(foods[1].servingSizeGrams == 118)
        #expect(foods.allSatisfy { $0.source == .snapFood })
    }

    @Test func rejectsRepliesWithoutFoods() {
        #expect(throws: CollectionScanService.ScanError.self) { try CollectionScanService.parse(#"{"foods":[]}"#) }
        #expect(throws: CollectionScanService.ScanError.self) { try CollectionScanService.parse("I can't see any food.") }
    }

    @Test func promptAsksForOneServingPerProduct() {
        #expect(CollectionScanService.prompt.contains("once per product"))
        #expect(CollectionScanService.prompt.contains(#""foods""#))
    }

    @Test func addingScannedFoodsSkipsOnesAlreadyInTheCollection() throws {
        let defaults = try #require(UserDefaults(suiteName: "CollectionScanTests-\(UUID())"))
        let store = FoodCollectionStore(defaults: defaults)
        let office = try #require(store.create(named: "Office snacks"))
        let banana = FoodEntry(name: "Banana", calories: 105, protein: 1, carbs: 27, fat: 0, source: .snapFood)
        let bar = FoodEntry(name: "Granola bar", calories: 190, protein: 4, carbs: 29, fat: 7, source: .snapFood)
        store.addItems([banana], to: office.id)
        store.addItems([banana, bar], to: office.id)
        #expect(FoodCollectionStore(defaults: defaults).collection(id: office.id)?.items.map(\.name) == ["Banana", "Granola bar"])
    }
}
