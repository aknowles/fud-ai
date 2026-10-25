import Foundation
import Testing
@testable import calorietracker

/// The DASH preset writes four existing goals and the scorecard reads four existing totals;
/// nothing new is persisted.
@MainActor
struct DASHPresetTests {
    @Test func presetSetsTheFourDASHGoalsAndLeavesTheRestAlone() {
        let before = OptionalNutrientGoals.defaults.settingGoal(42, for: .fiber)

        let standard = DASHPreset.applying(.standard, to: before)
        #expect(standard.goal(for: .sodium) == 2_300)
        #expect(standard.goal(for: .potassium) == 4_700)
        #expect(standard.goal(for: .calcium) == 1_250)
        #expect(standard.goal(for: .magnesium) == 500)
        #expect(standard.goal(for: .fiber) == 42)

        let lower = DASHPreset.applying(.lower, to: before)
        #expect(lower.goal(for: .sodium) == 1_500)
        #expect(lower.goal(for: .potassium) == 4_700)
    }

    @Test func presetValuesFitTheGoalPickerRanges() {
        for variant in DASHPreset.SodiumVariant.allCases {
            for nutrient in DASHPreset.nutrients {
                let value = DASHPreset.goal(for: nutrient, sodium: variant)!
                #expect(nutrient.range.contains(value), "\(nutrient) \(value) outside \(nutrient.range)")
            }
        }
    }

    @Test func appliedVariantIsRecognizedOnlyWhenAllFourMatch() {
        #expect(DASHPreset.appliedVariant(in: .defaults) == nil)
        #expect(DASHPreset.appliedVariant(in: DASHPreset.applying(.standard, to: .defaults)) == .standard)
        #expect(DASHPreset.appliedVariant(in: DASHPreset.applying(.lower, to: .defaults)) == .lower)
        let nudged = DASHPreset.applying(.lower, to: .defaults).settingGoal(1_600, for: .sodium)
        #expect(DASHPreset.appliedVariant(in: nudged) == nil)
    }

    @Test func scorecardScoresTodayAndAveragesOverLoggedDaysOnly() {
        let suite = "DASHPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let eightDaysAgo = calendar.date(byAdding: .day, value: -8, to: today)!

        // Today: sodium over the limit, potassium on target.
        #expect(store.addEntry(FoodEntry(name: "Soup", calories: 300, protein: 10, carbs: 30, fat: 8, timestamp: today, source: .manual,
                                         sodium: 1_800, potassium: 2_000, calcium: 400, magnesium: 200)))
        #expect(store.addEntry(FoodEntry(name: "Banana bread", calories: 300, protein: 5, carbs: 50, fat: 10, timestamp: today, source: .manual,
                                         sodium: 700, potassium: 2_700, calcium: 400, magnesium: 100)))
        // Two days ago: within the window, low sodium.
        #expect(store.addEntry(FoodEntry(name: "Salad", calories: 200, protein: 5, carbs: 20, fat: 10, timestamp: twoDaysAgo, source: .manual,
                                         sodium: 500, potassium: 1_000, calcium: 1_200, magnesium: 300)))
        // Eight days ago: outside the 7-day window.
        #expect(store.addEntry(FoodEntry(name: "Ignored", calories: 200, protein: 5, carbs: 20, fat: 10, timestamp: eightDaysAgo, source: .manual,
                                         sodium: 9_000, potassium: 9_000, calcium: 9_000, magnesium: 9_000)))

        let goals = DASHPreset.applying(.standard, to: .defaults)
        let scorecard = DASHScorecard(foodStore: store, date: today, goals: goals)
        let byNutrient = Dictionary(uniqueKeysWithValues: scorecard.lines.map { ($0.nutrient, $0) })

        #expect(scorecard.loggedDaysInWeek == 2)
        #expect(byNutrient[.sodium]?.today == 2_500)
        #expect(byNutrient[.sodium]?.todayMeetsGoal == false)
        #expect(byNutrient[.potassium]?.today == 4_700)
        #expect(byNutrient[.potassium]?.todayMeetsGoal == true)
        #expect(byNutrient[.calcium]?.todayMeetsGoal == false)
        #expect(byNutrient[.magnesium]?.todayMeetsGoal == false)
        #expect(scorecard.todayScore == 1)

        // Averages divide by the two logged days, not seven.
        #expect(byNutrient[.sodium]?.weeklyAverage == 1_500)
        #expect(byNutrient[.sodium]?.weekMeetsGoal == true)
        #expect(byNutrient[.calcium]?.weeklyAverage == 1_000)
        #expect(scorecard.weekScore == 1)
    }

    @Test func scorecardWithNoFoodHasZeroLoggedDays() {
        let suite = "DASHPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)

        let scorecard = DASHScorecard(foodStore: store, date: .now, goals: .defaults)

        #expect(scorecard.loggedDaysInWeek == 0)
        #expect(scorecard.todayScore == 0)
        #expect(scorecard.lines.allSatisfy { $0.today == 0 && $0.weeklyAverage == 0 })
    }
}
