import Foundation
import Testing
@testable import calorietracker

/// The symptom log and the trigger finder: features of food, findings with evidence, the
/// store, and what Coach hears.
@MainActor
struct SymptomTriggerTests {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func food(_ name: String, at date: Date, purines: Double? = nil, meal: MealType = .lunch) -> FoodEntry {
        FoodEntry(name: name, calories: 400, protein: 20, carbs: 40, fat: 15, timestamp: date, source: .manual, mealType: meal,
                  supplementalNutrients: purines.map { ["purines": $0] } ?? [:])
    }

    /// 14 days of oats and salad; on 5 of them a late spicy curry followed by heartburn.
    private func heartburnFortnight() -> (entries: [FoodEntry], symptoms: [Symptom]) {
        var entries: [FoodEntry] = []
        var symptoms: [Symptom] = []
        for day in 1...14 {
            entries.append(food("Oatmeal", at: at(8, daysAgo: day), meal: .breakfast))
            entries.append(food("Garden salad", at: at(12, 30, daysAgo: day)))
            if day <= 5 {
                entries.append(food("Spicy chicken curry", at: at(20, 30, daysAgo: day), meal: .dinner))
                symptoms.append(Symptom(date: at(22, daysAgo: day), kind: .heartburn))
            } else {
                entries.append(food("Roast chicken", at: at(18, 30, daysAgo: day), meal: .dinner))
            }
        }
        return (entries, symptoms)
    }

    @Test func foodFeaturesIncludeSensitivityTagsLateMealsAlcoholAndPurines() {
        let late = food("Spicy chicken curry", at: at(21, daysAgo: 1))
        #expect(TriggerFeature.features(of: late).isSuperset(of: [.sensitivity(.reflux), .lateMeal, .food("spicy chicken curry")]))
        #expect(TriggerFeature.features(of: food("Beer", at: at(18, daysAgo: 1))).contains(.alcohol))
        #expect(TriggerFeature.features(of: food("Sardines", at: at(12, daysAgo: 1), purines: 300)).contains(.highPurines))
        #expect(!TriggerFeature.features(of: food("Oatmeal", at: at(8, daysAgo: 1))).contains(.lateMeal))
    }

    @Test func lateSpicyMealsStandOutBeforeHeartburn() throws {
        let (entries, symptoms) = heartburnFortnight()

        let findings = TriggerAnalysis.findings(symptoms: symptoms, entries: entries, calendar: calendar)
        let features = findings.map(\.feature)

        #expect(features.contains(.sensitivity(.reflux)))
        #expect(features.contains(.lateMeal))
        #expect(features.contains(.food("spicy chicken curry")))
        #expect(!features.contains(.food("garden salad")))
        let reflux = try #require(findings.first { $0.feature == .sensitivity(.reflux) })
        #expect(reflux.hits == 5 && reflux.episodes == 5)
        #expect(reflux.baseRate < 0.2)
        #expect(reflux.evidence.hasPrefix("Before 5 of 5 heartburn or reflux episodes"))
    }

    @Test func fewerThanThreeEpisodesOrCommonFoodsSuggestNothing() {
        let (entries, symptoms) = heartburnFortnight()
        #expect(TriggerAnalysis.findings(symptoms: Array(symptoms.prefix(2)), entries: entries, calendar: calendar).isEmpty)

        let everyday = (1...10).map { food("Coffee", at: at(9, daysAgo: $0)) }
        let headaches = (1...4).map { Symptom(date: at(11, daysAgo: $0), kind: .headache) }
        #expect(!TriggerAnalysis.findings(symptoms: headaches, entries: everyday, calendar: calendar)
            .contains { $0.feature == .food("coffee") })
    }

    @Test func goutFlaresLookBackTwoDaysForPurines() {
        var entries = (1...20).map { food("Rice bowl", at: at(12, daysAgo: $0)) }
        var flares: [Symptom] = []
        for day in [3, 9, 15] {
            entries.append(food("Liver and onions", at: at(19, daysAgo: day + 1), purines: 400, meal: .dinner))
            flares.append(Symptom(date: at(6, daysAgo: day), kind: .goutFlare))
        }

        let features = TriggerAnalysis.findings(symptoms: flares, entries: entries, calendar: calendar).map(\.feature)

        #expect(features.contains(.highPurines))
    }

    @Test func theStoreKeepsSymptomsNewestFirst() {
        let suite = "SymptomTriggerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SymptomStore(defaults: defaults)

        store.add(Symptom(date: at(9, daysAgo: 2), kind: .bloating))
        store.add(Symptom(date: at(9, daysAgo: 1), kind: .other, customName: "Brain fog", severity: 1))

        let reloaded = SymptomStore(defaults: defaults)
        #expect(reloaded.symptoms.map(\.name) == ["Brain fog", "Bloating"])
        reloaded.remove(reloaded.symptoms[0].id)
        #expect(SymptomStore(defaults: defaults).symptoms.count == 1)
    }

    @Test func coachHearsRecentSymptomsAndPossibleTriggers() {
        let (entries, symptoms) = heartburnFortnight()

        let lines = HealthContextPrompt.lines(foods: entries, goals: .defaults, profile: HealthProfile(), plan: [],
                                              symptoms: symptoms, now: at(12, daysAgo: 0), calendar: calendar)

        #expect(lines.contains("## Symptoms"))
        #expect(lines.contains { $0.hasPrefix("- Logged in the last 3 days: heartburn (moderate) yesterday 22:00") })
        #expect(lines.contains { $0.hasPrefix("- Possible trigger (a pattern, not proven):") && $0.contains("before 5 of 5 heartburn") })
    }
}
