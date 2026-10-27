import Foundation
import Testing
@testable import calorietracker

/// The food diary lives in a file instead of the 4 MiB-capped defaults plist, while
/// `FoodStore`, the blob guard and iCloud backup keep talking to a `UserDefaults`.
@MainActor
struct DiaryFileDefaultsTests {
    /// A private defaults suite and diary directory, both removed afterwards.
    private final class Harness {
        let suite = "DiaryFileDefaultsTests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backups = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plain: UserDefaults

        init() { plain = UserDefaults(suiteName: suite)! }

        @MainActor func makeDefaults() -> DiaryFileDefaults {
            DiaryFileDefaults(suiteName: suite, directory: directory)!
        }

        @MainActor func makeStore() -> FoodStore {
            FoodStore(observesExternalChanges: false, defaults: makeDefaults(), corruptBackupDirectory: backups)
        }

        var fileURL: URL { directory.appendingPathComponent("foodEntries.json") }

        func archived() -> [URL] {
            let archive = directory.appendingPathComponent("Archive", isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil)) ?? []
        }

        deinit {
            plain.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: backups)
        }
    }

    private func meal(_ name: String) -> FoodEntry {
        FoodEntry(name: name, calories: 400, protein: 20, carbs: 40, fat: 15, source: .manual,
                  supplementalNutrients: ["purines": 120], sodium: 600)
    }

    @Test func diaryKeyMatchesFoodStore() {
        #expect(DiaryFileDefaults.diaryKey == FoodStore.storageKey)
    }

    @Test func emptyFirstLaunchHasNoDiaryAndWritesNoFile() {
        let harness = Harness()
        let store = harness.makeStore()

        #expect(store.entries.isEmpty)
        #expect(!store.isPersistenceBlocked)
        #expect(!FileManager.default.fileExists(atPath: harness.fileURL.path))
    }

    @Test func existingDefaultsDiaryMovesIntoTheFile() throws {
        let harness = Harness()
        let entries = [meal("Chili"), meal("Salad")]
        let blob = try JSONEncoder().encode(entries)
        harness.plain.set(blob, forKey: FoodStore.storageKey)

        let store = harness.makeStore()

        #expect(store.entries.map(\.id) == entries.map(\.id))
        #expect(try Data(contentsOf: harness.fileURL) == blob)
        #expect(harness.plain.object(forKey: FoodStore.storageKey) == nil)
        #expect(harness.plain.bool(forKey: DiaryFileDefaults.markerKey))
    }

    @Test func savedEntriesSurviveANewStore() {
        let harness = Harness()
        let first = harness.makeStore()
        let entry = meal("Turkey sandwich")
        #expect(first.addEntry(entry))

        let second = harness.makeStore()

        #expect(second.entries.map(\.id) == [entry.id])
        #expect(harness.plain.object(forKey: FoodStore.storageKey) == nil)
    }

    @Test func corruptFileIsBackedUpBeforeAnythingOverwritesIt() throws {
        let harness = Harness()
        let garbage = Data("not json".utf8)
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        try garbage.write(to: harness.fileURL)
        harness.plain.set(true, forKey: DiaryFileDefaults.markerKey)

        let store = harness.makeStore()

        #expect(store.entries.isEmpty)
        let backup = try #require(store.corruptBlobBackups.first)
        #expect(try Data(contentsOf: backup.url) == garbage)
    }

    @Test func fileLeftAfterTheDefaultsDomainWasWipedIsArchivedNotLoaded() throws {
        let harness = Harness()
        let old = harness.makeStore()
        #expect(old.addEntry(meal("Old")))
        harness.plain.removePersistentDomain(forName: harness.suite)

        let store = harness.makeStore()

        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.fileURL.path))
        #expect(harness.archived().count == 1)
    }

    @Test func blobRestoredIntoDefaultsReplacesTheFileAndKeepsTheOldOne() throws {
        let harness = Harness()
        let local = harness.makeStore()
        #expect(local.addEntry(meal("Local")))
        let restored = [meal("Restored")]
        harness.plain.set(try JSONEncoder().encode(restored), forKey: FoodStore.storageKey)

        let store = harness.makeStore()

        #expect(store.entries.map(\.id) == restored.map(\.id))
        #expect(harness.plain.object(forKey: FoodStore.storageKey) == nil)
        #expect(harness.archived().count == 1)
    }

    @Test func cloudBackupSeesTheDiaryAndRestoresIntoTheFile() throws {
        let harness = Harness()
        let defaults = harness.makeDefaults()
        let entry = meal("Backed up")
        let blob = try JSONEncoder().encode([entry])
        defaults.set(blob, forKey: FoodStore.storageKey)

        let snapshot = defaults.dictionaryRepresentation()
        #expect(snapshot[FoodStore.storageKey] as? Data == blob)
        #expect(snapshot[DiaryFileDefaults.markerKey] == nil)

        defaults.removeObject(forKey: FoodStore.storageKey)
        #expect(!FileManager.default.fileExists(atPath: harness.fileURL.path))
        defaults.set(snapshot[FoodStore.storageKey], forKey: FoodStore.storageKey)

        #expect(try Data(contentsOf: harness.fileURL) == blob)
        #expect(harness.makeStore().entries.map(\.id) == [entry.id])
    }

    @Test func otherKeysStayInDefaults() {
        let harness = Harness()
        let defaults = harness.makeDefaults()
        defaults.set(42, forKey: "someSetting")

        #expect(harness.plain.integer(forKey: "someSetting") == 42)
        #expect(!FileManager.default.fileExists(atPath: harness.fileURL.path))
    }
}
