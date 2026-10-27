import Foundation
import Testing
@testable import calorietracker

@MainActor
struct TrackedProgressTests {
    @Test func limitsAreCalmThenAmberNearTheCapThenRedOver() {
        #expect(TrackStyle.make(direction: .limit, current: 1_000, goal: 2_300, unit: "mg").tone == .calm)
        #expect(TrackStyle.make(direction: .limit, current: 1_000, goal: 2_300, unit: "mg").status == "1300mg left")
        #expect(TrackStyle.make(direction: .limit, current: 2_000, goal: 2_300, unit: "mg").tone == .caution)
        let over = TrackStyle.make(direction: .limit, current: 2_500, goal: 2_300, unit: "mg")
        #expect(over.tone == .bad)
        #expect(over.status == "200mg over")
        #expect(over.symbol == "exclamationmark.triangle.fill")
    }

    @Test func targetsFillTowardAGoalAndOverIsFine() {
        let short = TrackStyle.make(direction: .target, current: 1.3, goal: 2.5, unit: " L")
        #expect(short.tone == .toGo)
        #expect(short.status == "1.2 L to go")
        #expect(short.symbol == "flag.fill")
        let met = TrackStyle.make(direction: .target, current: 3.1, goal: 2.5, unit: " L")
        #expect(met.tone == .good)
        #expect(met.status == "Goal met")
        #expect(met.symbol == "checkmark.circle.fill")
    }

    @Test func rangesAreGoodNearTheGoalAndWarnOver() {
        #expect(TrackStyle.make(direction: .range, current: 100, goal: 250, unit: "g").tone == .calm)
        #expect(TrackStyle.make(direction: .range, current: 240, goal: 250, unit: "g").status == "On target")
        #expect(TrackStyle.make(direction: .range, current: 290, goal: 250, unit: "g").tone == .caution)
        #expect(TrackStyle.make(direction: .range, current: 330, goal: 250, unit: "g").tone == .bad)
    }

    @Test func paceFlagsATargetBehindAndALimitAhead() {
        // Usually halfway by now.
        let water = TrackStyle.make(direction: .target, current: 0.6, goal: 2.5, unit: " L", expectedFraction: 0.5)
        #expect(water.tone == .caution)
        #expect(water.paceNote == "Behind your usual pace")
        #expect(water.paceFraction == 0.5)
        #expect(TrackStyle.make(direction: .target, current: 1.2, goal: 2.5, unit: " L", expectedFraction: 0.5).tone == .toGo)

        let sodium = TrackStyle.make(direction: .limit, current: 1_400, goal: 2_300, unit: "mg", expectedFraction: 0.3)
        #expect(sodium.tone == .caution)
        #expect(sodium.paceNote == "Ahead of your usual pace")
        // Under a limit and on pace is calm, never "behind".
        let calm = TrackStyle.make(direction: .limit, current: 300, goal: 2_300, unit: "mg", expectedFraction: 0.5)
        #expect(calm.tone == .calm)
        #expect(calm.paceNote == nil)
    }

    @Test func steadyStaysInsideTheUsualBand() {
        let band = 60.0...140.0
        #expect(TrackStyle.make(direction: .steady(band), current: 90, goal: 120, unit: "µg").tone == .good)
        #expect(TrackStyle.make(direction: .steady(band), current: 200, goal: 120, unit: "µg").status == "Above your usual")
        #expect(TrackStyle.make(direction: .steady(band), current: 20, goal: 120, unit: "µg").tone == .toGo)
    }

    @Test func usualPaceAveragesRecentDaysAndFallsBackToAnEvenDay() {
        let day: TrackPace.Day = [(minute: 8 * 60, amount: 500), (minute: 13 * 60, amount: 500), (minute: 19 * 60, amount: 1_000)]
        #expect(TrackPace.usualFraction(at: 14 * 60, days: Array(repeating: day, count: 5)) == 0.5)
        #expect(TrackPace.usualFraction(at: 14 * 60, days: Array(repeating: day, count: 4)) == nil)
        #expect(TrackPace.expectedFraction(at: 14 * 60, days: []) == 0.5)
        #expect(TrackPace.evenFraction(at: 6 * 60) == 0)
        #expect(TrackPace.evenFraction(at: 22 * 60) == 1)
        #expect(TrackPace.fraction(for: .target, at: 14 * 60, days: []) == 0.5)
        #expect(TrackPace.fraction(for: .limit, at: 14 * 60, days: []) == nil)
        #expect(TrackStyle.make(direction: .target, current: 0, goal: 30, unit: "g", expectedFraction: 0.5).shortPaceNote == "Behind pace")
    }

    @Test func directionsFollowTheHealthProfile() {
        #expect(TrackDirection.of(OptionalNutrient.sodium, profile: HealthProfile()) == .limit)
        #expect(TrackDirection.of(OptionalNutrient.potassium, profile: HealthProfile()) == .target)
        // Kidney disease turns potassium into a limit.
        #expect(TrackDirection.of(OptionalNutrient.potassium, profile: HealthProfile(entries: [.kidneyDisease])) == .limit)
        #expect(TrackDirection.of(HomeTopNutrient.protein, profile: HealthProfile()) == .target)
        #expect(TrackDirection.of(HomeTopNutrient.carbs, profile: HealthProfile()) == .range)
        #expect(TrackDirection.of(OptionalNutrient.vitaminK, profile: HealthProfile(entries: [.warfarin]), steadyBand: 50...150) == .steady(50...150))
    }

    @Test func homePaceUsesOnlyTodayAndPastDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 14))!
        let water = (1...6).flatMap { daysAgo -> [WaterEntry] in
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            return [WaterEntry(date: calendar.date(byAdding: .hour, value: 9, to: day)!, milliliters: 1_000),
                    WaterEntry(date: calendar.date(byAdding: .hour, value: 18, to: day)!, milliliters: 1_000)]
        }
        let today = HomeTrack.waterStyle(current: 400, goal: 2_500, unit: " ml", date: now, water: water, now: now, calendar: calendar)
        #expect(today.paceFraction == 0.5)
        #expect(today.paceNote == "Behind your usual pace")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(HomeTrack.waterStyle(current: 400, goal: 2_500, unit: " ml", date: yesterday, water: water, now: now, calendar: calendar).paceFraction == nil)
    }
}
