import Foundation
import Testing
@testable import calorietracker

/// Food memory rules and the default + menu now offering Suggestions and Collections.
@MainActor
struct FoodMemoryAndPlanCardTests {
    private func defaults() -> (UserDefaults, String) {
        let suite = "FoodMemoryTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func rulesBecomeAPromptSection() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FoodMemory.promptText(from: defaults).isEmpty)

        let store = FoodMemoryStore(defaults: defaults)
        store.add(FoodMemoryRule(match: "  Omelet ", instruction: FoodMemory.swapInstruction(from: "Eggs", to: "Egg whites")))
        store.add(FoodMemoryRule(match: "", instruction: "My coffee is black, no sugar."))

        let text = FoodMemory.promptText(from: defaults)
        #expect(text.hasPrefix("Food memory (the user's standing corrections"))
        #expect(text.contains("- For omelet: Use egg whites instead of eggs."))
        #expect(text.contains("- Always: My coffee is black, no sugar."))
    }

    @Test func duplicatesAreReplacedAndRulesCanBeRemoved() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodMemoryStore(defaults: defaults)

        store.add(FoodMemoryRule(match: "omelet", instruction: "Use egg whites instead of eggs."))
        store.add(FoodMemoryRule(match: "omelet", instruction: "use egg whites instead of eggs."))
        #expect(FoodMemoryStore(defaults: defaults).rules.count == 1)

        store.add(FoodMemoryRule(match: "", instruction: "   "))
        #expect(store.rules.count == 1)

        store.remove(at: IndexSet(integer: 0))
        #expect(FoodMemoryStore(defaults: defaults).rules.isEmpty)
    }

    @Test func anUncustomizedPlusMenuOffersCollectionsAndSuggestions() {
        let methods = AddMenuSettings.decode(nil).visibleMethods

        #expect(methods.contains(.suggestions))
        #expect(methods.contains(.collections))
        #expect(AddMenuConfig.forkDefault.sanitized() == AddMenuConfig.forkDefault.sanitized().sanitized())
        #expect(!AddMenuConfig.iOSDefault.visibleMethods.contains(.suggestions))
    }

    @Test func mondayOfWeekIgnoresTheLocalesFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 10))!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!

        #expect(calendar.component(.day, from: calendar.mondayOfWeek(containing: sunday)) == 2)
        #expect(calendar.component(.day, from: calendar.mondayOfWeek(containing: wednesday)) == 2)
    }
}
