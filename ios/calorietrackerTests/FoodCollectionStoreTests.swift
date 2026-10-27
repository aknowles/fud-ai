import Foundation
import Testing
@testable import calorietracker

/// Named food collections ("Work snacks") live in their own defaults key and keep
/// photo-free copies of foods, so the diary and its photo cleanup never see them.
@MainActor
struct FoodCollectionStoreTests {
    private final class Harness {
        let suite = "FoodCollectionStoreTests.\(UUID().uuidString)"
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let defaults: UserDefaults

        init() { defaults = UserDefaults(suiteName: suite)! }

        @MainActor func makeStore() -> FoodCollectionStore {
            FoodCollectionStore(defaults: defaults, corruptBackupDirectory: backups)
        }

        deinit {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: backups)
        }
    }

    private func food(_ name: String, calories: Int = 200) -> FoodEntry {
        FoodEntry(name: name, calories: calories, protein: 5, carbs: 25, fat: 8,
                  imageFilename: "fudai-image-\(UUID().uuidString).jpg", emoji: "🥨", source: .manual,
                  supplementalNutrients: ["purines": 12],
                  ingredients: [MealIngredient(name: "Part", grams: 30, calories: 100, protein: 2, carbs: 10, fat: 4,
                                               imageFilename: "ingredient.jpg", additionalImageFilenames: ["more.jpg"])])
    }

    @Test func startsEmptyAndRejectsBlankNames() {
        let store = Harness().makeStore()

        #expect(store.collections.isEmpty)
        #expect(store.create(named: "   ") == nil)
        #expect(store.collections.isEmpty)
    }

    @Test func createRenameAndDeleteSurviveANewStore() throws {
        let harness = Harness()
        let store = harness.makeStore()
        let snacks = try #require(store.create(named: "  Work snacks "))
        let lunch = try #require(store.create(named: "Work cafeteria"))
        store.rename(snacks.id, to: "Desk snacks")
        store.delete(lunch.id)

        let reloaded = harness.makeStore()

        #expect(reloaded.collections.map(\.name) == ["Desk snacks"])
        #expect(reloaded.collections.first?.id == snacks.id)
    }

    @Test func addedFoodsAreCopiedWithoutPhotosAndKeepTheirNutrition() throws {
        let harness = Harness()
        let store = harness.makeStore()
        let snacks = try #require(store.create(named: "Work snacks"))
        let pretzels = food("Pretzels")

        store.toggle(pretzels, in: snacks.id)

        let item = try #require(harness.makeStore().collection(id: snacks.id)?.items.first)
        #expect(item.name == "Pretzels")
        #expect(item.calories == 200)
        #expect(item.emoji == "🥨")
        #expect(item.supplementalNutrients["purines"] == 12)
        #expect(item.imageFilename == nil)
        #expect(item.additionalImageFilenames.isEmpty)
        #expect(item.ingredients.first?.imageFilename == nil)
        #expect(item.ingredients.first?.additionalImageFilenames == nil)
        #expect(item.allImageFilenames.isEmpty)
    }

    @Test func togglingTheSameFoodTwiceRemovesIt() throws {
        let store = Harness().makeStore()
        let snacks = try #require(store.create(named: "Work snacks"))
        let apple = food("Apple", calories: 95)

        store.toggle(apple, in: snacks.id)
        #expect(store.contains(apple, in: snacks.id))
        // Another log of the same food (new id, same name and calories) counts as the same item.
        store.toggle(food("apple", calories: 95), in: snacks.id)

        #expect(!store.contains(apple, in: snacks.id))
        #expect(store.collection(id: snacks.id)?.items.isEmpty == true)
    }

    @Test func itemsCanBeRemovedAndReordered() throws {
        let store = Harness().makeStore()
        let snacks = try #require(store.create(named: "Work snacks"))
        for name in ["Apple", "Pretzels", "Yogurt"] { store.toggle(food(name), in: snacks.id) }

        store.moveItems(from: IndexSet(integer: 2), to: 0, in: snacks.id)
        store.removeItems(at: IndexSet(integer: 1), from: snacks.id)

        #expect(store.collection(id: snacks.id)?.items.map(\.name) == ["Yogurt", "Pretzels"])
    }

    @Test func reloadPicksUpAWipedDomain() throws {
        let harness = Harness()
        let store = harness.makeStore()
        _ = try #require(store.create(named: "Work snacks"))

        harness.defaults.removeObject(forKey: FoodCollectionStore.storageKey)
        store.reload()

        #expect(store.collections.isEmpty)
    }

    @Test func unreadableCollectionsAreBackedUpBeforeBeingReplaced() throws {
        let harness = Harness()
        let garbage = Data("not json".utf8)
        harness.defaults.set(garbage, forKey: FoodCollectionStore.storageKey)

        let store = harness.makeStore()
        _ = store.create(named: "Work snacks")

        let backups = try FileManager.default.contentsOfDirectory(at: harness.backups, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == garbage)
    }

    @Test func collectionsAreALogMethodAndASavedMealsMode() {
        #expect(FoodLogMethod.addMenuCases.contains(.collections))
        #expect(FoodLogMethod.collections.quickAction == nil)
        #expect(SavedMealsMode.collections.title == "Collections")
    }
}
