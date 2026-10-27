import Foundation

/// How the calorie numbers on Home relate: maintenance → goal → eaten → left, and, with Apple
/// Health, burned so far → deficit or surplus. Shown on the Calories screen.
struct CalorieBreakdown: Equatable {
    let restingCalories: Int
    let activityName: String
    let activityMultiplier: Double
    let maintenance: Int
    /// Goal minus maintenance: negative to lose, positive to gain.
    let adjustment: Int
    let goal: Int
    let isCustomGoal: Bool
    let eaten: Int
    let burned: Int?
    /// Apple Health active energy so far, when known.
    var active: Int? = nil
    /// Added to the goal for activity (`ActivityGoal`); 0 with a fixed goal.
    var activityBonus = 0

    /// The goal after the activity bonus.
    var goalToday: Int { goal + activityBonus }
    /// Positive while under today's goal.
    var left: Int { goalToday - eaten }
    /// Burned minus eaten: positive is a deficit, negative a surplus.
    var balance: Int? { burned.map { $0 - eaten } }

    static func make(profile: UserProfile, eaten: Int, burned: Int?, active: Int? = nil, activityBonus: Int = 0) -> CalorieBreakdown {
        let maintenance = Int(profile.tdee)
        let goal = profile.effectiveCalories
        return CalorieBreakdown(
            restingCalories: Int(profile.bmr.rounded()),
            activityName: profile.activityLevel.displayName,
            activityMultiplier: profile.activityLevel.multiplier,
            maintenance: maintenance,
            adjustment: goal - maintenance,
            goal: goal,
            isCustomGoal: profile.customCalories != nil,
            eaten: eaten,
            burned: burned,
            active: active,
            activityBonus: activityBonus
        )
    }
}
