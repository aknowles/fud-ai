import Foundation
import Testing
@testable import calorietracker

/// Short courses: an entry applies from its start day through its end day plus tail days,
/// and metronidazole rules out alcohol for 3 days after the last dose.
@MainActor
struct HealthCourseTests {
    private let calendar = Calendar.current
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!)!
    }

    private func drink(_ name: String, alcohol: Double? = nil, on date: Date) -> FoodEntry {
        FoodEntry(name: name, calories: 150, protein: 1, carbs: 10, fat: 0, timestamp: date, source: .manual,
                  supplementalNutrients: alcohol.map { ["alcohol": $0] } ?? [:])
    }

    @Test func aCourseAppliesThroughItsTailDays() {
        let profile = HealthProfile(entries: [.metronidazole, .gout],
                                    courses: ["metronidazole": HealthCourse(start: day(0), end: day(6))])

        #expect(!profile.isActive(.metronidazole, on: day(-1), calendar: calendar))
        #expect(profile.isActive(.metronidazole, on: day(0), calendar: calendar))
        #expect(profile.isActive(.metronidazole, on: day(9), calendar: calendar))
        #expect(!profile.isActive(.metronidazole, on: day(10), calendar: calendar))
        #expect(profile.effective(on: day(10), calendar: calendar).entries == [.gout])
        #expect(profile.isActive(.gout, on: day(100), calendar: calendar))
    }

    @Test func prednisoneCoursesHaveNoTail() {
        let profile = HealthProfile(entries: [.prednisone], courses: ["prednisone": HealthCourse(start: day(0), end: day(4))])

        #expect(profile.isActive(.prednisone, on: day(4), calendar: calendar))
        #expect(!profile.isActive(.prednisone, on: day(5), calendar: calendar))
        #expect(HealthEntryKind.prednisone.supportsCourse && HealthEntryKind.metronidazole.supportsCourse)
        #expect(!HealthEntryKind.warfarin.supportsCourse)
    }

    @Test func alcoholIsFlaggedByNameOrAmountButNotLookAlikes() {
        #expect(drink("Glass of red wine", on: day(0)).foodFlags == [.alcohol])
        #expect(drink("IPA", on: day(0)).foodFlags == [.alcohol])
        #expect(drink("Mystery punch", alcohol: 12, on: day(0)).foodFlags == [.alcohol])
        #expect(drink("Non-alcoholic beer", on: day(0)).foodFlags.isEmpty)
        #expect(drink("Root beer float", on: day(0)).foodFlags.isEmpty)
        #expect(drink("Ginger ale", on: day(0)).foodFlags.isEmpty)
        #expect(drink("Red wine vinegar dressing", on: day(0)).foodFlags.isEmpty)
        #expect(drink("Kale salad", on: day(0)).foodFlags.isEmpty)
        #expect(HealthEntryKind.metronidazole.avoidedFoodFlags == [.alcohol])
    }

    @Test func coachSeesTheCourseAndItsTailThenNothingAfterward() {
        let profile = HealthProfile(entries: [.metronidazole],
                                    courses: ["metronidazole": HealthCourse(start: day(-7), end: day(-1))])

        let during = HealthContextPrompt.lines(foods: [drink("Beer", on: day(0))], goals: .defaults, profile: profile,
                                               plan: [], symptoms: [], now: day(0), calendar: calendar)
        #expect(during.contains { $0.hasPrefix("- Metronidazole or tinidazole course:") && $0.contains("its food rules last through") })
        #expect(during.contains("- Logged today despite a medicine interaction: Beer (alcohol). Mention it if relevant."))

        let after = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: profile, plan: [], symptoms: [], now: day(3), calendar: calendar)
        #expect(after.isEmpty)
    }

    @Test func coursesPersistAndAreClearedWhenTheEntryIsTurnedOff() {
        let suite = "HealthCourseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HealthProfileStore(defaults: defaults)
        let course = HealthCourse(start: day(0), end: day(6))

        store.set(.metronidazole, active: true)
        store.setCourse(course, for: .metronidazole)
        #expect(HealthProfileStore(defaults: defaults).profile.course(for: .metronidazole) == course)

        store.set(.metronidazole, active: false)
        #expect(HealthProfileStore(defaults: defaults).profile.courses == nil)
    }

    @Test func profilesSavedBeforeCoursesExistedStillDecode() throws {
        let profile = try JSONDecoder().decode(HealthProfile.self, from: Data(#"{"entries":["gout"],"avoid":{"celiac":true}}"#.utf8))

        #expect(profile.courses == nil)
        #expect(profile.isActive(.gout, on: .now))
    }
}
