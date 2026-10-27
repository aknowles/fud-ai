import Foundation
import Testing
@testable import calorietracker

/// The health profile says which conditions shape the cards and Coach; goal numbers stay
/// in `OptionalNutrientGoals`. Conflicting entries are reported, never resolved.
@MainActor
struct HealthProfileTests {
    private final class Harness {
        let suite = "HealthProfileTests.\(UUID().uuidString)"
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let defaults: UserDefaults

        init() { defaults = UserDefaults(suiteName: suite)! }

        @MainActor func makeStore() -> HealthProfileStore {
            HealthProfileStore(defaults: defaults, corruptBackupDirectory: backups)
        }

        deinit {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: backups)
        }
    }

    @Test func firstLaunchKeepsGoutAndDASHOnAndLeavesGoalsAlone() throws {
        let harness = Harness()
        let goals = DASHPreset.applying(.lower, to: .defaults).settingGoal(300, for: .purines)
        harness.defaults.set(goals.encodedData, forKey: OptionalNutrientGoals.storageKey)

        let store = harness.makeStore()

        #expect(store.profile == .migratedDefault)
        #expect(store.contains(.gout) && store.contains(.dash))
        #expect(harness.defaults.data(forKey: HealthProfileStore.storageKey) != nil)
        let after = OptionalNutrientGoals.decoded(from: try #require(harness.defaults.data(forKey: OptionalNutrientGoals.storageKey)))
        #expect(after == goals.mergedWithDefaults())
        #expect(after.goal(for: .purines) == 300)
        #expect(after.goal(for: .sodium) == 1_500)
    }

    @Test func turningEntriesOffAndOnPersistsInAFixedOrder() {
        let harness = Harness()
        let store = harness.makeStore()

        store.set(.gout, active: false)
        #expect(harness.makeStore().profile.entries == [.dash])

        store.set(.gout, active: true)
        #expect(harness.makeStore().profile.entries == [.gout, .dash])
    }

    @Test func goutAndDASHDoNotConflict() {
        #expect(HealthProfile.migratedDefault.conflicts.isEmpty)
    }

    @Test func aPotassiumLimitConflictsWithDASH() {
        let kidney = HealthRule(nutrient: .potassium, direction: .limit, source: "Kidney disease")

        let conflicts = HealthConflict.find(in: HealthEntryKind.dash.rules + [kidney])

        #expect(conflicts == [HealthConflict(nutrient: .potassium,
                                             raisedBy: [HealthEntryKind.dash.displayName],
                                             limitedBy: ["Kidney disease"])])
    }

    @Test func rulesFollowEachEntrysDirection() {
        let gout = HealthEntryKind.gout.rules
        #expect(gout.map(\.nutrient) == [.purines, .alcohol, .addedSugar])
        #expect(gout.allSatisfy { $0.direction == .limit })

        let dash = Dictionary(uniqueKeysWithValues: HealthEntryKind.dash.rules.map { ($0.nutrient, $0.direction) })
        #expect(dash == [.sodium: .limit, .potassium: .target, .calcium: .target, .magnesium: .target])
    }

    @Test func unreadableProfileIsBackedUpAndFallsBackToTheDefault() throws {
        let harness = Harness()
        let garbage = Data("not json".utf8)
        harness.defaults.set(garbage, forKey: HealthProfileStore.storageKey)

        let store = harness.makeStore()

        #expect(store.profile == .migratedDefault)
        let backups = try FileManager.default.contentsOfDirectory(at: harness.backups, includingPropertiesForKeys: nil)
        #expect(try Data(contentsOf: #require(backups.first)) == garbage)
    }
}

/// Diabetes, heart health, kidney disease and kidney stones as profile entries.
@MainActor
struct HealthConditionEntryTests {
    @Test func eachConditionLimitsAndTargetsTheRightNutrients() {
        func directions(_ kind: HealthEntryKind) -> [OptionalNutrient: HealthRule.Direction] {
            Dictionary(uniqueKeysWithValues: kind.rules.map { ($0.nutrient, $0.direction) })
        }
        #expect(directions(.diabetes) == [.addedSugar: .limit, .fiber: .target])
        #expect(directions(.heartHealth) == [.saturatedFat: .limit, .transFat: .limit, .sodium: .limit, .fiber: .target])
        #expect(directions(.kidneyDisease) == [.sodium: .limit, .potassium: .limit, .phosphorus: .limit])
        #expect(directions(.kidneyStones) == [.oxalate: .limit, .sodium: .limit])
    }

    @Test func kidneyDiseaseConflictsWithDASHOnPotassiumOnly() {
        let profile = HealthProfile(entries: [.dash, .kidneyDisease])

        #expect(profile.conflicts == [HealthConflict(nutrient: .potassium,
                                                     raisedBy: [HealthEntryKind.dash.displayName],
                                                     limitedBy: [HealthEntryKind.kidneyDisease.displayName])])
        #expect(HealthProfile(entries: [.gout, .dash, .diabetes, .heartHealth, .kidneyStones]).conflicts.isEmpty)
    }

    @Test func onlyTheKidneyEntriesAskForTheDoctorsNumbers() {
        #expect(HealthEntryKind.kidneyDisease.setupNote != nil)
        #expect(HealthEntryKind.kidneyStones.setupNote != nil)
        #expect(HealthEntryKind.gout.setupNote == nil)
        #expect(HealthEntryKind.diabetes.setupNote == nil)
    }

    @Test func coachSeesTheNewEntriesTheirGoalsAndTheConflict() {
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let lunch = FoodEntry(name: "Burger", calories: 700, protein: 35, carbs: 50, fat: 40, timestamp: now, source: .manual,
                              saturatedFat: 15, supplementalNutrients: ["phosphorus": 400], sodium: 1_200, potassium: 600)

        let lines = HealthContextPrompt.lines(foods: [lunch], goals: .defaults,
                                              profile: HealthProfile(entries: [.dash, .heartHealth, .kidneyDisease]), plan: [], symptoms: [], now: now)

        #expect(lines.contains { $0.hasPrefix("- High cholesterol or heart disease:") })
        #expect(lines.contains { $0.hasPrefix("- Chronic kidney disease:") && $0.contains("protein goal") })
        #expect(lines.contains("- Today so far (phosphorus is an estimate):"))
        #expect(lines.contains("  - Saturated fat: 15 of 20 g limit"))
        #expect(lines.contains("  - Phosphorus: 400 of 1000 mg limit"))
        #expect(lines.contains("  - Potassium: 600 mg, goal 3500 mg (entries disagree)"))
        #expect(lines.contains { $0.hasPrefix("- Conflict on potassium: High blood pressure (DASH) raises it, Chronic kidney disease limits it.") })
    }

    @Test func everyNutrientReadsItsOwnField() {
        let entry = FoodEntry(name: "Test", calories: 1, protein: 1, carbs: 1, fat: 1, source: .manual,
                              fiber: 4, saturatedFat: 3, supplementalNutrients: ["oxalate": 50], transFat: 0.5, vitaminK: 80)

        #expect(entry.amount(of: .fiber) == 4)
        #expect(entry.amount(of: .saturatedFat) == 3)
        #expect(entry.amount(of: .transFat) == 0.5)
        #expect(entry.amount(of: .vitaminK) == 80)
        #expect(entry.amount(of: .oxalate) == 50)
        #expect(entry.amount(of: .sodium) == nil)
        #expect([entry, entry].total(of: .fiber) == 8)
    }
}
