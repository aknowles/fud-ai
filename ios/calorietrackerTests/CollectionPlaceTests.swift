import CoreLocation
import Foundation
import Testing
@testable import calorietracker

struct CollectionPlaceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// 2026-10-26 is a Monday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let office = CollectionPlace(latitude: 40.7484, longitude: -73.9857, radiusMeters: 150)

    private func snack(_ name: String) -> FoodEntry {
        FoodEntry(name: name, calories: 100, protein: 1, carbs: 20, fat: 1, source: .manual)
    }

    @Test func placeContainsPointsInsideItsRadius() {
        #expect(office.contains(latitude: 40.7484, longitude: -73.9857))
        // About 100 m north.
        #expect(office.contains(latitude: 40.7493, longitude: -73.9857))
        // About 1 km north.
        #expect(!office.contains(latitude: 40.7574, longitude: -73.9857))
    }

    @Test func weekdayScheduleCoversWorkHoursOnly() {
        let schedule = CollectionSchedule()
        #expect(schedule.contains(at(26, 8), calendar: calendar))
        #expect(schedule.contains(at(30, 17, 59), calendar: calendar))
        #expect(!schedule.contains(at(26, 18), calendar: calendar))
        #expect(!schedule.contains(at(26, 7, 59), calendar: calendar))
        // Saturday.
        #expect(!schedule.contains(at(31, 12), calendar: calendar))
    }

    @Test func overnightScheduleWrapsPastMidnight() {
        let night = CollectionSchedule(weekdays: Set(1...7), startMinute: 22 * 60, endMinute: 6 * 60)
        #expect(night.contains(at(26, 23), calendar: calendar))
        #expect(night.contains(at(27, 5), calendar: calendar))
        #expect(!night.contains(at(27, 12), calendar: calendar))
    }

    @Test func collectionIsActiveAtItsPlaceOrDuringItsSchedule() {
        let placeOnly = FoodCollection(name: "Office snacks", items: [snack("Almonds")], place: office)
        let inside = CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857)
        let away = CLLocationCoordinate2D(latitude: 40.8, longitude: -73.9)
        #expect(placeOnly.isActive(at: inside, now: at(31, 12), calendar: calendar))
        #expect(!placeOnly.isActive(at: away, now: at(26, 12), calendar: calendar))
        #expect(!placeOnly.isActive(at: nil, now: at(26, 12), calendar: calendar))

        let both = FoodCollection(name: "Office snacks", items: [snack("Almonds")], place: office, schedule: CollectionSchedule())
        #expect(both.isActive(at: nil, now: at(26, 12), calendar: calendar))
        #expect(both.isActive(at: away, now: at(26, 12), calendar: calendar))
        #expect(!both.isActive(at: away, now: at(31, 12), calendar: calendar))

        #expect(!FoodCollection(name: "Plain", items: [snack("Apple")]).isActive(at: inside, now: at(26, 12), calendar: calendar))
    }

    @Test func storeSavesPlaceAndScheduleAndListsActiveCollections() throws {
        let defaults = try #require(UserDefaults(suiteName: "CollectionPlaceTests-\(UUID())"))
        let store = FoodCollectionStore(defaults: defaults)
        let office = try #require(store.create(named: "Office snacks"))
        let empty = try #require(store.create(named: "Empty"))
        store.toggle(snack("Almonds"), in: office.id)
        store.setSchedule(CollectionSchedule(), for: office.id)
        store.setSchedule(CollectionSchedule(), for: empty.id)
        store.setPlace(self.office, for: office.id)

        let reloaded = FoodCollectionStore(defaults: defaults)
        #expect(reloaded.collection(id: office.id)?.place == self.office)
        #expect(reloaded.collection(id: office.id)?.schedule == CollectionSchedule())
        #expect(reloaded.activeCollections(at: nil, now: at(26, 12), calendar: calendar).map(\.name) == ["Office snacks"])
        #expect(reloaded.activeCollections(at: nil, now: at(31, 12), calendar: calendar).isEmpty)

        reloaded.setPlace(nil, for: office.id)
        #expect(FoodCollectionStore(defaults: defaults).collection(id: office.id)?.place == nil)
    }

    @Test func collectionsSavedBeforePlacesStillDecode() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","name":"Work snacks","items":[]}]"#
        let decoded = try JSONDecoder().decode([FoodCollection].self, from: Data(json.utf8))
        #expect(decoded.first?.name == "Work snacks")
        #expect(decoded.first?.place == nil)
        #expect(decoded.first?.schedule == nil)
    }

    @Test func coachHearsWhatIsOnHand() {
        let office = FoodCollection(name: "Office snacks", items: [snack("Almonds"), snack("Apple")], schedule: CollectionSchedule())
        let lines = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(), plan: [], symptoms: [],
                                              onHand: [office], tastes: FoodTastes(), now: at(26, 12), calendar: calendar)
        #expect(lines.contains("## On hand now"))
        #expect(lines.contains("- Office snacks: Almonds (100 kcal), Apple (100 kcal)."))
        #expect(HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(), plan: [], symptoms: [],
                                          onHand: [], tastes: FoodTastes(), now: at(26, 12), calendar: calendar).isEmpty)
    }

    @Test func scheduleSummaryNamesCommonDaySets() {
        #expect(CollectionSchedule().summary(calendar: calendar).hasPrefix("Weekdays, "))
        #expect(CollectionSchedule(weekdays: Set(1...7)).summary(calendar: calendar).hasPrefix("Every day, "))
        #expect(CollectionSchedule(weekdays: [2, 4]).summary(calendar: calendar).hasPrefix("Mon, Wed, "))
    }
}
