import Foundation
import Testing
@testable import calorietracker

/// Warfarin's "keep vitamin K steady" goal compares a day with the user's own usual amount.
@MainActor
struct WarfarinSteadyTests {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(bySettingHour: 13, minute: 0, second: 0, of: .now)! }

    private func greens(_ vitaminK: Double, daysAgo: Int = 0, name: String = "Side salad") -> FoodEntry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return FoodEntry(name: name, calories: 50, protein: 2, carbs: 5, fat: 2, timestamp: day, source: .manual, vitaminK: vitaminK)
    }

    private var history: [FoodEntry] { (1...5).map { greens(90, daysAgo: $0) } }

    @Test func theUsualAmountIsTheAverageOfLoggedDaysBeforeToday() {
        #expect(SteadyBand.usual(.vitaminK, entries: history + [greens(400)], before: now, calendar: calendar) == 90)
        #expect(SteadyBand.usual(.vitaminK, entries: Array(history.prefix(2)), before: now, calendar: calendar) == nil)
        let old = greens(1_000, daysAgo: 20)
        #expect(SteadyBand.usual(.vitaminK, entries: history + [old], before: now, calendar: calendar) == 90)
    }

    @Test func theRangeIsHalfTheUsualAmountWithAFloor() {
        #expect(SteadyBand.range(around: 100, for: .vitaminK) == 50...150)
        #expect(SteadyBand.range(around: 20, for: .vitaminK) == 0...60)
        #expect(SteadyBand.isAbove(151, usual: 100, for: .vitaminK))
        #expect(!SteadyBand.isAbove(10, usual: 100, for: .vitaminK))
    }

    @Test func warfarinKeepsVitaminKSteadyLimitsAlcoholAndFlagsCranberry() {
        #expect(HealthEntryKind.warfarin.isMedicine)
        #expect(HealthEntryKind.warfarin.rules.map(\.direction) == [.steady, .limit])
        #expect(HealthEntryKind.warfarin.rules.map(\.nutrient) == [.vitaminK, .alcohol])
        #expect(HealthEntryKind.warfarin.avoidedFoodFlags == [.cranberry])
        #expect(HealthProfile(entries: [.warfarin, .dash, .prednisone, .metformin]).conflicts.isEmpty)
    }

    @Test func coachSeesTodayAgainstTheUsualAmount() {
        let profile = HealthProfile(entries: [.warfarin])

        let big = HealthContextPrompt.lines(foods: history + [greens(300, name: "Kale salad")], goals: .defaults,
                                            profile: profile, now: now, calendar: calendar)
        #expect(big.contains("  - Vitamin K: 300 mcg so far, usual 90 mcg a day (keep steady, above their usual range)"))
        #expect(big.contains { $0.hasPrefix("- Takes warfarin:") })

        let normal = HealthContextPrompt.lines(foods: history + [greens(80)], goals: .defaults,
                                               profile: profile, now: now, calendar: calendar)
        #expect(normal.contains("  - Vitamin K: 80 mcg so far, usual 90 mcg a day (keep steady)"))

        let fresh = HealthContextPrompt.lines(foods: [greens(80)], goals: .defaults, profile: profile, now: now, calendar: calendar)
        #expect(fresh.contains { $0.hasPrefix("  - Vitamin K: 80 mcg so far (keep steady; not enough history") })
    }

    @Test func suggestionsFlagAnOptionThatWouldPushVitaminKWellAboveUsual() {
        let options = [
            SuggestionOption(entry: greens(500, name: "Kale salad"), reason: "", tweak: nil),
            SuggestionOption(entry: greens(5, name: "Apple"), reason: "", tweak: nil),
        ]

        let evaluated = SuggestionRanking.evaluate(options, today: [greens(60)], calorieGoal: 2_000, goals: .defaults,
                                                   profile: HealthProfile(entries: [.warfarin]), usual: [.vitaminK: 90])

        #expect(evaluated[0].flags == [.unsteady(.vitaminK)])
        #expect(evaluated[1].flags.isEmpty)
        #expect(!SuggestionFlag.unsteady(.vitaminK).isHardStop)
    }
}
