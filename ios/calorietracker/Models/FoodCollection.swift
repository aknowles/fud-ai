import Foundation
import Observation
import SwiftUI

/// A named list of foods the user picks from often, such as "Work snacks" or
/// "Work cafeteria". Items are copies of logged foods without photos, so the
/// diary's photo cleanup never has to know about collections.
struct FoodCollection: Identifiable, Codable {
    var id: UUID
    var name: String
    var items: [FoodEntry]
    /// Where the collection is on hand, e.g. the office; see `CollectionPlace`.
    var place: CollectionPlace?
    /// When it is on hand without location, e.g. weekdays 8–6.
    var schedule: CollectionSchedule?
    /// There is a barista: any standard coffee-bar drink is on hand (`CoffeeDrink`).
    var coffeeBar: Bool?
    /// Anything else on hand, in the user's words, e.g. "fruit basket, salad bar Tuesdays".
    var alsoHere: String?

    init(id: UUID = UUID(), name: String, items: [FoodEntry] = [], place: CollectionPlace? = nil, schedule: CollectionSchedule? = nil,
         coffeeBar: Bool? = nil, alsoHere: String? = nil) {
        self.id = id
        self.name = name
        self.items = items
        self.place = place
        self.schedule = schedule
        self.coffeeBar = coffeeBar
        self.alsoHere = alsoHere
    }

    var hasCoffeeBar: Bool { coffeeBar == true }

    /// The "also here" note, trimmed, or nil when empty.
    var alsoHereNote: String? {
        let trimmed = alsoHere?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Has something on hand besides its items.
    var hasExtras: Bool { hasCoffeeBar || alsoHereNote != nil }
}

/// Stores food collections in their own defaults key, outside the food diary.
@Observable
final class FoodCollectionStore {
    static let storageKey = "fork.foodCollections"
    static let shared = FoodCollectionStore()

    private(set) var collections: [FoodCollection] = []
    private let blob: PersistedBlobGuard

    /// True while an unreadable collections blob has no backup copy; every change is refused.
    var isPersistenceBlocked: Bool { blob.isWriteBlocked }

    init(defaults: UserDefaults = .standard, corruptBackupDirectory: URL? = nil) {
        blob = PersistedBlobGuard(defaults: defaults, key: Self.storageKey, backupDirectory: corruptBackupDirectory)
        reload()
    }

    /// Re-reads the stored list, picking up an iCloud restore or Delete Everything.
    func reload() {
        switch blob.loadList(FoodCollection.self) {
        case .missing: collections = []
        case .decoded(let decoded, _): collections = decoded
        case .corrupt: break
        }
    }

    func collection(id: UUID) -> FoodCollection? {
        collections.first { $0.id == id }
    }

    // MARK: - Collections

    @discardableResult
    func create(named name: String) -> FoodCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPersistenceBlocked else { return nil }
        let collection = FoodCollection(name: trimmed)
        collections.append(collection)
        save()
        return collection
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.name = trimmed }
    }

    func delete(_ id: UUID) {
        guard !isPersistenceBlocked else { return }
        collections.removeAll { $0.id == id }
        save()
    }

    // MARK: - Items

    func contains(_ entry: FoodEntry, in id: UUID) -> Bool {
        collection(id: id)?.items.contains { $0.favoriteKey == entry.favoriteKey } ?? false
    }

    /// Adds a photo-free copy of `entry`, or removes the matching item if it is already there.
    func toggle(_ entry: FoodEntry, in id: UUID) {
        update(id) { collection in
            if let index = collection.items.firstIndex(where: { $0.favoriteKey == entry.favoriteKey }) {
                collection.items.remove(at: index)
            } else {
                collection.items.append(Self.template(from: entry))
            }
        }
    }

    /// Adds photo-free copies of `entries`, skipping foods already in the collection.
    func addItems(_ entries: [FoodEntry], to id: UUID) {
        update(id) { collection in
            for entry in entries where !collection.items.contains(where: { $0.favoriteKey == entry.favoriteKey }) {
                collection.items.append(Self.template(from: entry))
            }
        }
    }

    func removeItems(at offsets: IndexSet, from id: UUID) {
        update(id) { $0.items.remove(atOffsets: offsets) }
    }

    func moveItems(from source: IndexSet, to destination: Int, in id: UUID) {
        update(id) { $0.items.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Place and schedule

    func setPlace(_ place: CollectionPlace?, for id: UUID) {
        update(id) { $0.place = place }
    }

    func setSchedule(_ schedule: CollectionSchedule?, for id: UUID) {
        update(id) { $0.schedule = schedule }
    }

    func setCoffeeBar(_ isOn: Bool, for id: UUID) {
        update(id) { $0.coffeeBar = isOn ? true : nil }
    }

    func setAlsoHere(_ note: String, for id: UUID) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.alsoHere = trimmed.isEmpty ? nil : trimmed }
    }

    /// The copy a collection keeps: same food and nutrition, no photos.
    static func template(from entry: FoodEntry) -> FoodEntry {
        var item = entry
        item.imageData = nil
        item.imageFilename = nil
        item.additionalImageData = []
        item.additionalImageFilenames = []
        item.ingredients = item.ingredients.map { ingredient in
            var copy = ingredient
            copy.imageFilename = nil
            copy.additionalImageFilenames = nil
            return copy
        }
        return item
    }

    // MARK: - Persistence

    private func update(_ id: UUID, _ change: (inout FoodCollection) -> Void) {
        guard !isPersistenceBlocked, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        change(&collections[index])
        save()
    }

    private func save() {
        blob.save(collections)
    }
}
