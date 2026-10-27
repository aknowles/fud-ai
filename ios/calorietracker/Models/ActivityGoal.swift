import Foundation
import Observation

/// How Apple Health's active energy changes the day's calorie goal.
enum ActivityGoalMode: String, CaseIterable, Identifiable {
    /// The goal stays fixed; the activity level already allows for usual exercise.
    case fixed
    /// Add exercise beyond what the activity level already assumes, e.g. a hard workout.
    case addExtra
    /// Net calories: start from a sedentary base and add Health's active energy as it comes in.
    case followHealth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixed: String(localized: "Fixed goal")
        case .addExtra: String(localized: "Add extra exercise")
        case .followHealth: String(localized: "Follow Apple Health")
        }
    }

    var explanation: String {
        switch self {
        case .fixed:
            String(localized: "Your goal stays the same every day. Your activity level already allows for your usual exercise.")
        case .addExtra:
            String(localized: "Adds calories you burn beyond what your activity level already assumes, like a hard workout. A normal day changes nothing, so activity is never counted twice.")
        case .followHealth:
            String(localized: "Net calories: your goal starts from a sedentary base and grows with every active calorie Apple Health records, so it's low in the morning and rises as you move.")
        }
    }
}

enum ActivityGoal {
    static let modeKey = "fork.activityGoal.mode"
    static let shareKey = "fork.activityGoal.share"
    /// Shares of the burn to add back; watches tend to overestimate active energy.
    static let shareChoices = [0.5, 0.75, 1.0]
    static let defaultShare = 0.5
    /// The thermic effect of food: part of maintenance that Apple Health does not count as active.
    static let foodEffect = 0.1
    static let sedentaryMultiplier = 1.2

    static var mode: ActivityGoalMode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(ActivityGoalMode.init) ?? .fixed
    }

    static var share: Double {
        let stored = UserDefaults.standard.double(forKey: shareKey)
        return shareChoices.contains(stored) ? stored : defaultShare
    }

    /// The active energy a whole day at this activity level already assumes.
    static func assumedActive(profile: UserProfile) -> Int {
        max(0, Int(profile.tdee - profile.bmr * (1 + foodEffect)))
    }

    /// Calories added to (or, following Health early in the day, taken from) the goal.
    static func bonus(mode: ActivityGoalMode, share: Double, activeCalories: Int?, profile: UserProfile) -> Int {
        guard let active = activeCalories, active >= 0 else { return 0 }
        switch mode {
        case .fixed:
            return 0
        case .addExtra:
            let extra = max(0, active - assumedActive(profile: profile))
            return Int((Double(extra) * share).rounded())
        case .followHealth:
            let sedentary = profile.bmr * sedentaryMultiplier
            return Int((sedentary - profile.tdee + Double(active) * share).rounded())
        }
    }
}

/// Apple Health's active energy by day, as Home reads it, so the goal can use it anywhere.
@Observable
final class ActivityGoalStore {
    static let shared = ActivityGoalStore()

    private(set) var activeByDay: [Date: Int] = [:]
    /// Bumped when the mode or share changes, so views using the bonus refresh.
    private(set) var settingsVersion = 0

    func record(activeCalories: Int, on date: Date, calendar: Calendar = .current) {
        activeByDay[calendar.startOfDay(for: date)] = activeCalories
    }

    func active(on date: Date, calendar: Calendar = .current) -> Int? {
        activeByDay[calendar.startOfDay(for: date)]
    }

    func settingsChanged() { settingsVersion += 1 }

    func bonus(on date: Date, profile: UserProfile?, calendar: Calendar = .current) -> Int {
        _ = settingsVersion
        guard let profile else { return 0 }
        return ActivityGoal.bonus(mode: ActivityGoal.mode, share: ActivityGoal.share,
                                  activeCalories: active(on: date, calendar: calendar), profile: profile)
    }

    /// The profile's goal plus the activity bonus for `date`.
    func goal(on date: Date, profile: UserProfile?) -> Int {
        (profile?.effectiveCalories ?? 0) + bonus(on: date, profile: profile)
    }
}
