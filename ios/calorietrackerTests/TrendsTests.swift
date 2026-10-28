import Foundation
import Testing
@testable import calorietracker

@MainActor
struct TrendsTests {
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private func day(_ offset: Int, hour: Int = 12) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: -offset, to: today)!)!
    }

    private func food(_ name: String, daysAgo: Int, calories: Int = 500, sodium: Double = 0, purines: Double = 0, ml: Double? = nil) -> FoodEntry {
        var entry = FoodEntry(name: name, calories: calories, protein: 20, carbs: 50, fat: 15, timestamp: day(daysAgo),
                              source: .manual, supplementalNutrients: [OptionalNutrient.purines.rawValue: purines], sodium: sodium)
        entry.servingSizeGrams = ml
        return entry
    }

    @Test func daysRunOldestFirstAndIncludeBothEnds() {
        let days = TrendData.days(from: day(6), through: day(0))
        #expect(days.count == 7)
        #expect(days.first == calendar.startOfDay(for: day(6)))
        #expect(days.last == today)
    }

    @Test func diaryDaysSumAndUnloggedDaysAreBlank() {
        let foods = [food("Toast", daysAgo: 2, sodium: 300, purines: 50), food("Soup", daysAgo: 2, sodium: 900, purines: 80),
                     food("Salad", daysAgo: 0, sodium: 200)]
        let sources = TrendData.Sources(foodsByDay: TrendData.Sources.grouping(foods))
        let days = TrendData.days(from: day(2), through: day(0))
        #expect(TrendData.series(.nutrient(.sodium), days: days, sources: sources).map(\.value) == [1_200, nil, 200])
        #expect(TrendData.series(.nutrient(.purines), days: days, sources: sources).map(\.value) == [130, nil, 0])
        #expect(TrendData.series(.calories, days: days, sources: sources).map(\.value) == [1_000, nil, 500])
        #expect(TrendData.series(.dashScore, days: days, sources: sources)[1].value == nil)
    }

    @Test func waterAddsDrinksAndWeightAveragesInTheUsersUnit() {
        let days = TrendData.days(from: day(1), through: day(0))
        var sources = TrendData.Sources(
            foodsByDay: TrendData.Sources.grouping([food("Iced tea", daysAgo: 0, ml: 500)]),
            water: [WaterEntry(date: day(0), milliliters: 750)],
            weights: [WeightEntry(date: day(1, hour: 7), weightKg: 80), WeightEntry(date: day(1, hour: 20), weightKg: 82)],
            steps: [today: 9_000]
        )
        #expect(TrendData.series(.water, days: days, sources: sources).map(\.value) == [nil, 1_250])
        sources.countDrinks = false
        #expect(TrendData.series(.water, days: days, sources: sources).last?.value == 750)
        #expect(TrendData.series(.weight, days: days, sources: sources).first?.value == 81)
        sources.weightInKg = false
        #expect(abs((TrendData.series(.weight, days: days, sources: sources).first?.value ?? 0) - 178.574) < 0.01)
        #expect(TrendData.series(.steps, days: days, sources: sources).map(\.value) == [nil, 9_000])
    }

    @Test func rollingAverageSkipsBlankDays() {
        let series = [1.0, nil, 3.0, 5.0].enumerated().map { TrendDay(day: day(3 - $0.offset), value: $0.element) }
        #expect(TrendData.rollingAverage(series, window: 3).map(\.value) == [1, 1, 2, 4])
    }

    @Test func goalsComeFromTheRightPlace() {
        var goals = OptionalNutrientGoals.defaults
        goals.setGoal(1_500, for: .sodium)
        #expect(TrendData.goal(.nutrient(.sodium), profile: nil, goals: goals, waterGoalMl: 2_000, waterUnit: .milliliters, weightInKg: true) == 1_500)
        #expect(TrendData.goal(.water, profile: nil, goals: goals, waterGoalMl: 2_500, waterUnit: .milliliters, weightInKg: true) == 2_500)
        #expect(TrendData.goal(.dashScore, profile: nil, goals: goals, waterGoalMl: 0, waterUnit: .milliliters, weightInKg: true) == 4)
        #expect(TrendData.goal(.steps, profile: nil, goals: goals, waterGoalMl: 0, waterUnit: .milliliters, weightInKg: true) == nil)
    }

    @Test func markersKeepTheChosenSymptomsAndTheWorstEachDay() {
        let days = TrendData.days(from: day(5), through: day(0))
        let symptoms = [
            Symptom(date: day(3, hour: 7), kind: .goutFlare, severity: 1),
            Symptom(date: day(3, hour: 18), kind: .goutFlare, severity: 3),
            Symptom(date: day(1), kind: .heartburn, severity: 2),
            Symptom(date: day(9), kind: .goutFlare, severity: 2),
        ]
        let marks = TrendData.markers(symptoms, kinds: [.goutFlare], days: days)
        #expect(marks.count == 1)
        #expect(marks.first?.day == calendar.startOfDay(for: day(3)))
        #expect(marks.first?.severity == 3)
        #expect(TrendData.markers(symptoms, kinds: [], days: days).isEmpty)
    }

    @Test func theSecondAxisScalesOntoTheFirst() {
        #expect(TrendData.scaleFactor(primaryMax: 600, secondaryMax: 30) == 20)
        #expect(TrendData.scaleFactor(primaryMax: 600, secondaryMax: 0) == 1)
        let series = [TrendDay(day: today, value: 100)]
        #expect(abs(TrendData.axisTop(series, goal: 400) - 460) < 0.001)
    }

    @Test func presetsPutTheProfilesConditionsFirst() {
        #expect(TrendPreset.ordered(for: HealthProfile(entries: [.gout])).first == .gout)
        #expect(TrendPreset.ordered(for: HealthProfile(entries: [.dash])).first == .bloodPressure)
        #expect(TrendPreset.ordered(for: HealthProfile()).count == TrendPreset.all.count)
        #expect(TrendPreset.gout.markers == [.goutFlare])
        #expect(TrendPreset.bloodPressure.secondary == .nutrient(.potassium))
    }

    @Test func directionsColorTheBars() {
        #expect(TrendMetric.nutrient(.sodium).direction(profile: HealthProfile()) == .limit)
        #expect(TrendMetric.water.direction(profile: HealthProfile()) == .target)
        #expect(TrendMetric.nutrient(.vitaminK).direction(profile: HealthProfile(entries: [.warfarin])) == .target)
        #expect(TrendMetric.weight.direction(profile: HealthProfile()) == nil)
    }
}
