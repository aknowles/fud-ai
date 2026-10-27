import Foundation
import Testing
@testable import calorietracker

/// Dose windows keep minerals away from ciprofloxacin-type antibiotics and food, coffee,
/// minerals and soy away from levothyroxine, including across midnight.
@MainActor
struct DoseTimingTests {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func food(_ name: String, at time: Date, calories: Int = 120, calcium: Double? = nil, iron: Double? = nil) -> FoodEntry {
        FoodEntry(name: name, calories: calories, protein: 5, carbs: 10, fat: 3, timestamp: time, source: .manual,
                  calcium: calcium, iron: iron)
    }

    private func cipro(at times: [Int], before: Int? = nil) -> HealthProfile {
        HealthProfile(entries: [.quinoloneTetracycline],
                      doseSchedules: ["quinoloneTetracycline": DoseSchedule(times: times, mineralsBefore: before)])
    }

    @Test func foodsAreSortedIntoTheClassesDoseWindowsCareAbout() {
        let now = at(12)
        #expect(DoseFoodClass.classes(for: food("Glass of milk", at: now)) == [.anyFood, .minerals])
        #expect(DoseFoodClass.classes(for: food("Orange juice", at: now, calcium: 350)) == [.anyFood, .minerals])
        #expect(DoseFoodClass.classes(for: food("Iron supplement", at: now, calories: 0)) == [.minerals])
        #expect(DoseFoodClass.classes(for: food("Black coffee", at: now, calories: 2)) == [.coffee])
        #expect(DoseFoodClass.classes(for: food("Oat milk latte", at: now)) == [.anyFood, .coffee])
        #expect(DoseFoodClass.classes(for: food("Tofu stir fry", at: now)) == [.anyFood, .soy])
        #expect(DoseFoodClass.classes(for: food("Water", at: now, calories: 0)).isEmpty)
    }

    @Test func milkThirtyMinutesAfterACiprofloxacinDoseIsCaught() throws {
        let profile = cipro(at: [12 * 60])

        let conflict = try #require(DoseTiming.conflicts(for: food("Milk", at: at(12, 30)), profile: profile, calendar: calendar).first)
        #expect(conflict.kind == .quinoloneTetracycline)
        #expect(conflict.minutesFromDose == 30)
        #expect(conflict.windowEnd == at(14))

        #expect(DoseTiming.conflicts(for: food("Milk", at: at(14, 30)), profile: profile, calendar: calendar).isEmpty)
        #expect(DoseTiming.conflicts(for: food("Milk", at: at(7)), profile: profile, calendar: calendar).first?.minutesFromDose == -300)
        #expect(DoseTiming.conflicts(for: food("Apple", at: at(12, 30)), profile: profile, calendar: calendar).isEmpty)
    }

    @Test func windowsCrossMidnightInBothDirections() {
        let late = cipro(at: [23 * 60 + 30])
        #expect(DoseTiming.conflicts(for: food("Milk", at: at(0, 30, dayOffset: 1)), profile: late, calendar: calendar)
            .first?.minutesFromDose == 60)

        let early = cipro(at: [30])
        #expect(DoseTiming.conflicts(for: food("Cheese", at: at(23, 0, dayOffset: -1)), profile: early, calendar: calendar)
            .first?.minutesFromDose == -90)
    }

    @Test func levothyroxineKeepsFoodCoffeeMineralsAndSoyApart() {
        let profile = HealthProfile(entries: [.levothyroxine], doseSchedules: ["levothyroxine": DoseSchedule(times: [7 * 60])])
        func kinds(_ entry: FoodEntry) -> Set<DoseFoodClass> {
            Set(DoseTiming.conflicts(for: entry, profile: profile, calendar: calendar).map(\.foods))
        }

        #expect(kinds(food("Toast", at: at(7, 20))) == [.anyFood])
        #expect(kinds(food("Black coffee", at: at(7, 45), calories: 2)) == [.coffee])
        #expect(kinds(food("Toast", at: at(7, 45))).isEmpty)
        #expect(kinds(food("Iron supplement", at: at(9), calories: 0)) == [.minerals])
        #expect(kinds(food("Edamame", at: at(10))) == [.soy])
        #expect(kinds(food("Edamame", at: at(11, 30))).isEmpty)
    }

    @Test func theUsersOwnMineralWindowAndCourseEndAreRespected() {
        #expect(DoseTiming.conflicts(for: food("Milk", at: at(8)), profile: cipro(at: [12 * 60], before: 120), calendar: calendar).isEmpty)

        var ended = cipro(at: [12 * 60])
        ended.courses = ["quinoloneTetracycline": HealthCourse(start: at(0, dayOffset: -10), end: at(0, dayOffset: -3))]
        #expect(DoseTiming.conflicts(for: food("Milk", at: at(12, 30)), profile: ended, calendar: calendar).isEmpty)
    }

    @Test func upcomingWindowsAreTodaysUnfinishedOnesInOrder() {
        let profile = cipro(at: [8 * 60, 20 * 60])

        let windows = DoseTiming.upcomingWindows(on: at(12), after: at(12), profile: profile, calendar: calendar)

        #expect(windows.count == 1)
        #expect(windows.first?.start == at(14))
        #expect(windows.first?.end == at(22))
    }

    @Test func suggestionsWillNotPickAFoodInsideAWindow() {
        let profile = cipro(at: [12 * 60])
        let options = [SuggestionOption(entry: food("Yogurt", at: at(12, 30)), reason: "", tweak: nil),
                       SuggestionOption(entry: food("Apple", at: at(12, 30)), reason: "", tweak: nil)]

        let evaluated = SuggestionRanking.evaluate(options, today: [], calorieGoal: 2_000, goals: .defaults, profile: profile)

        #expect(evaluated[0].flags == [.doseWindow(.quinoloneTetracycline)])
        #expect(evaluated[1].flags.isEmpty)
        #expect(SuggestionFlag.doseWindow(.quinoloneTetracycline).isHardStop)
    }

    @Test func coachSeesTheDoseTimesTheWindowsAndAnyClash() {
        let profile = cipro(at: [8 * 60, 20 * 60])

        let lines = HealthContextPrompt.lines(foods: [food("Milk", at: at(8, 30))], goals: .defaults, profile: profile,
                                              plan: [], symptoms: [], onHand: [], now: at(12), calendar: calendar)

        #expect(lines.contains { $0.hasPrefix("- Ciprofloxacin, levofloxacin, doxycycline or minocycline doses at 08:00, 20:00. Today: keep dairy") && $0.contains("02:00 to 10:00 and 14:00 to 22:00") })
        #expect(lines.contains("- Logged inside a dose window today: Milk at 08:30, 30 min after the 08:00 dose. Mention it if relevant."))
    }
}
