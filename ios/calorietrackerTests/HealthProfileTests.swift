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

        func makeStore() -> HealthProfileStore {
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
