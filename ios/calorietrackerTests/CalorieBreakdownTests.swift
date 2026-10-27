import Foundation
import Testing
@testable import calorietracker

@MainActor
struct CalorieBreakdownTests {
    private func profile(goal: WeightGoal = .lose, customCalories: Int? = nil) -> UserProfile {
        UserProfile(
            name: "Test", gender: .male, birthday: Date(timeIntervalSince1970: 0), heightCm: 180, weightKg: 90,
            activityLevel: .light, goal: goal, bodyFatPercentage: nil, goalBodyFatPercentage: nil, useBodyFatInBMR: nil,
            weeklyChangeKg: 0.5, goalWeightKg: nil, customCalories: customCalories, customProtein: nil, customFat: nil,
            customCarbs: nil, autoBalanceMacro: nil
        )
    }

    @Test func goalIsMaintenancePlusThePlannedDeficit() {
        let user = profile()
        let breakdown = CalorieBreakdown.make(profile: user, eaten: 1_200, burned: nil)
        #expect(breakdown.maintenance == Int(user.tdee))
        #expect(breakdown.goal == user.effectiveCalories)
        #expect(breakdown.adjustment == user.calorieAdjustment)
        #expect(breakdown.adjustment < 0)
        #expect(breakdown.activityMultiplier == 1.375)
        #expect(breakdown.left == breakdown.goal - 1_200)
        #expect(breakdown.balance == nil)
        #expect(!breakdown.isCustomGoal)
    }

    @Test func overTheGoalCanStillBeADeficit() {
        let breakdown = CalorieBreakdown.make(profile: profile(customCalories: 1_800), eaten: 2_048, burned: 2_515)
        #expect(breakdown.isCustomGoal)
        #expect(breakdown.left == -248)
        #expect(breakdown.balance == 467)
        #expect(CalorieBreakdown.make(profile: profile(customCalories: 1_800), eaten: 2_600, burned: 2_515).balance == -85)
    }
}

@MainActor
struct ActivityGoalTests {
    private func profile() -> UserProfile {
        UserProfile(
            name: "Test", gender: .male, birthday: Date(timeIntervalSince1970: 0), heightCm: 180, weightKg: 90,
            activityLevel: .light, goal: .lose, bodyFatPercentage: nil, goalBodyFatPercentage: nil, useBodyFatInBMR: nil,
            weeklyChangeKg: 0.5, goalWeightKg: nil, customCalories: nil, customProtein: nil, customFat: nil,
            customCarbs: nil, autoBalanceMacro: nil
        )
    }

    @Test func aFixedGoalIgnoresHealth() {
        #expect(ActivityGoal.bonus(mode: .fixed, share: 1, activeCalories: 1_500, profile: profile()) == 0)
    }

    @Test func extraExerciseCountsOnlyWhatTheActivityLevelDoesNotAssume() {
        let user = profile()
        let assumed = ActivityGoal.assumedActive(profile: user)
        #expect(assumed == Int(user.tdee - user.bmr * 1.1))
        // A normal day changes nothing.
        #expect(ActivityGoal.bonus(mode: .addExtra, share: 1, activeCalories: assumed, profile: user) == 0)
        #expect(ActivityGoal.bonus(mode: .addExtra, share: 1, activeCalories: 100, profile: user) == 0)
        // A hard workout: 1,000 beyond the usual.
        #expect(ActivityGoal.bonus(mode: .addExtra, share: 1, activeCalories: assumed + 1_000, profile: user) == 1_000)
        #expect(ActivityGoal.bonus(mode: .addExtra, share: 0.5, activeCalories: assumed + 1_000, profile: user) == 500)
        #expect(ActivityGoal.bonus(mode: .addExtra, share: 1, activeCalories: nil, profile: user) == 0)
    }

    @Test func followingHealthStartsSedentaryAndGrowsWithActivity() {
        let user = profile()
        let morning = ActivityGoal.bonus(mode: .followHealth, share: 1, activeCalories: 0, profile: user)
        #expect(morning == Int((user.bmr * 1.2 - user.tdee).rounded()))
        #expect(morning < 0)
        let evening = ActivityGoal.bonus(mode: .followHealth, share: 1, activeCalories: 900, profile: user)
        #expect(evening - morning == 900)
    }

    @Test func theBreakdownUsesTodaysGoal() {
        let breakdown = CalorieBreakdown.make(profile: profile(), eaten: 2_000, burned: 3_000, active: 1_400, activityBonus: 500)
        #expect(breakdown.goalToday == breakdown.goal + 500)
        #expect(breakdown.left == breakdown.goal + 500 - 2_000)
    }

    @Test func coachHearsTheChangedGoal() {
        #expect(HealthContextPrompt.activityLines(bonus: 0, goal: 2_000).isEmpty)
        #expect(HealthContextPrompt.activityLines(bonus: 500, goal: 2_500).last?.hasPrefix("- Today's calorie goal is raised by 500 kcal to 2500 kcal") == true)
    }
}
