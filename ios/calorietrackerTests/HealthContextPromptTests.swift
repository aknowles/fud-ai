import Foundation
import Testing
@testable import calorietracker

/// The Coach and voice prompts carry each health-profile entry's guidance and goals with
/// today's totals, so advice weighs them without the user asking.
@MainActor
struct HealthContextPromptTests {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)! }

    private func entry(
        _ name: String,
        at date: Date,
        purines: Double = 0,
        alcohol: Double = 0,
        addedSugar: Double? = nil,
        sodium: Double? = nil,
        potassium: Double? = nil
    ) -> FoodEntry {
        FoodEntry(name: name, calories: 300, protein: 10, carbs: 30, fat: 10, timestamp: date, source: .manual,
                  addedSugar: addedSugar, supplementalNutrients: ["purines": purines, "alcohol": alcohol],
                  sodium: sodium, potassium: potassium)
    }

    @Test func todaysGoutTotalsAreShownAgainstTheirLimits() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let foods = [
            entry("Burger", at: now, purines: 180, alcohol: 0, addedSugar: 5, sodium: 900),
            entry("Beer", at: now, purines: 40, alcohol: 20, addedSugar: 0, sodium: 20),
            entry("Liver", at: yesterday, purines: 900, sodium: 3_000),
        ]

        let lines = HealthContextPrompt.lines(foods: foods, goals: .defaults, profile: HealthProfile(entries: [.gout]),
                                              plan: [], now: now, calendar: calendar)

        #expect(lines.contains("## Health goals"))
        #expect(lines.contains("- Today so far (purines and alcohol are estimates):"))
        #expect(lines.contains("  - Purines: 220 of 400 mg limit"))
        #expect(lines.contains("  - Alcohol: 20 of 14 g limit (over)"))
        #expect(lines.contains("  - Added sugar: 5 of 25 g limit"))
        #expect(!lines.contains { $0.contains("Sodium") || $0.contains("DASH") })
    }

    @Test func eachEntryAddsItsGuidanceAndTheMedicineRule() {
        let lines = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: .migratedDefault, plan: [], now: now, calendar: calendar)

        #expect(lines.contains { $0.hasPrefix("- Gout:") && $0.contains("low-purine") })
        #expect(lines.contains { $0.hasPrefix("- High blood pressure, following the DASH eating plan") })
        #expect(lines.contains { $0.contains("Never suggest starting, stopping or changing a medicine") })
        #expect(lines.contains("- Nothing logged yet today. Today's goals (purines and alcohol are estimates):"))
        #expect(lines.contains("  - Purines: 0 of 400 mg limit"))
        #expect(!lines.contains { $0.contains("Conflict") })
    }

    @Test func anEmptyProfileAddsNothing() {
        #expect(HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(), plan: [], now: now, calendar: calendar).isEmpty)
    }

    @Test func dashShowsItsGoalsAndScore() {
        let goals = DASHPreset.applying(.lower, to: .defaults)
        let foods = [entry("Soup", at: now, sodium: 1_200, potassium: 4_800)]

        let lines = HealthContextPrompt.lines(foods: foods, goals: goals, profile: HealthProfile(entries: [.dash]),
                                              plan: [], now: now, calendar: calendar)

        #expect(lines.contains("- Today so far:"))
        #expect(lines.contains("  - Sodium: 1200 of 1500 mg limit"))
        #expect(lines.contains("  - Potassium: 4800 of 4700 mg target (met)"))
        #expect(lines.contains("  - Calcium: 0 of 1250 mg target"))
        #expect(lines.contains("  - Magnesium: 0 of 500 mg target"))
        #expect(lines.contains("- DASH score (1500 mg sodium plan): today 2 of 4 goals met; 7-day average 2 of 4 over 1 logged days."))
    }

    @Test func entryListScorecardMatchesTheStoreScorecard() {
        let suite = "HealthContextPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let foods = [
            entry("Soup", at: now, sodium: 2_500, potassium: 4_700),
            entry("Salad", at: twoDaysAgo, sodium: 500, potassium: 1_000),
        ]
        for food in foods { #expect(store.addEntry(food)) }
        let goals = DASHPreset.applying(.standard, to: .defaults)

        let fromStore = DASHScorecard(foodStore: store, date: now, goals: goals, calendar: calendar)
        let fromEntries = DASHScorecard(entries: foods, date: now, goals: goals, calendar: calendar)

        #expect(fromEntries == fromStore)
    }
}
