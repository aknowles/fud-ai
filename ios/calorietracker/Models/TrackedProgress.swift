import Foundation
import SwiftUI

/// Which way is good for a tracked amount.
enum TrackDirection: Equatable {
    /// Stay under the goal: sodium, purines, added sugar.
    case limit
    /// Reach the goal; more is fine: water, protein, fiber.
    case target
    /// Land near the goal, within `TrackStyle.rangeTolerance`: calories, carbs, fat.
    case range
    /// Stay inside the user's usual band (`SteadyBand`): vitamin K on warfarin.
    case steady(ClosedRange<Double>)

    /// The health profile's direction for a nutrient, else what is usual for it.
    static func of(_ nutrient: OptionalNutrient, profile: HealthProfile, steadyBand: ClosedRange<Double>? = nil) -> TrackDirection {
        if let rule = profile.rules.first(where: { $0.nutrient == nutrient }) {
            switch rule.direction {
            case .limit: return .limit
            case .target: return .target
            case .steady: return steadyBand.map(TrackDirection.steady) ?? .target
            }
        }
        return defaultLimits.contains(nutrient) ? .limit : .target
    }

    static func of(_ nutrient: HomeTopNutrient, profile: HealthProfile, steadyBand: ClosedRange<Double>? = nil) -> TrackDirection {
        switch nutrient {
        case .protein: .target
        case .carbs, .fat: .range
        default: nutrient.optionalNutrient.map { of($0, profile: profile, steadyBand: steadyBand) } ?? .target
        }
    }

    /// Nutrients that are limits without any health entry.
    static let defaultLimits: Set<OptionalNutrient> = [
        .sugar, .addedSugar, .saturatedFat, .transFat, .cholesterol, .sodium, .caffeine,
        .purines, .alcohol, .phosphorus, .oxalate, .tyramine,
    ]
}

/// How a tracked amount is doing.
enum TrackTone: Equatable {
    /// A limit or range still filling, comfortably under.
    case calm
    /// A target still filling.
    case toGo
    case good
    case caution
    case bad

    var gradient: [Color] {
        switch self {
        case .calm: AppColors.calorieGradient
        case .toGo: [Color(red: 0.40, green: 0.68, blue: 0.96), Color(red: 0.22, green: 0.47, blue: 0.90)]
        case .good: [Color(red: 0.36, green: 0.78, blue: 0.52), Color(red: 0.18, green: 0.62, blue: 0.36)]
        case .caution: [Color(red: 1.0, green: 0.72, blue: 0.30), Color(red: 0.96, green: 0.55, blue: 0.10)]
        case .bad: [Color.red.opacity(0.75), Color.red]
        }
    }

    var color: Color { gradient.last ?? AppColors.calorie }
}

/// Everything a bar needs to draw a tracked amount: direction, tone, status words, and where
/// the user usually is by now.
struct TrackStyle: Equatable {
    let direction: TrackDirection
    let tone: TrackTone
    /// "650 mg left", "1.2 L to go", "Goal met".
    let status: String
    /// "Behind your usual pace", "Ahead of your usual pace", or nil.
    let paceNote: String?
    /// Where the user usually is by now, as a fraction of the goal (0...1), today only.
    let paceFraction: Double?

    /// A range is met within this fraction of the goal either way.
    static let rangeTolerance = 0.1
    /// A limit turns amber at this fraction of the goal.
    static let nearLimit = 0.85
    /// A target this far behind the usual amount by now is behind pace.
    static let behindPace = 0.75
    /// A limit or range this far ahead of the usual amount by now is ahead of pace.
    static let aheadPace = 1.25

    /// The pace note for narrow bars: "Behind pace", "Ahead of pace".
    var shortPaceNote: String? {
        guard paceNote != nil else { return nil }
        return direction == .target ? String(localized: "Behind pace") : String(localized: "Ahead of pace")
    }

    /// The SF Symbol that says which way is good.
    var symbol: String {
        switch direction {
        case .limit: tone == .bad ? "exclamationmark.triangle.fill" : "arrow.down.to.line"
        case .target: tone == .good ? "checkmark.circle.fill" : "flag.fill"
        case .range: "scope"
        case .steady: "equal.circle"
        }
    }

    /// The bar's fill: 0...1 of the goal.
    static func progress(current: Double, goal: Double) -> Double {
        goal > 0 ? min(max(current / goal, 0), 1) : 0
    }

    static func make(
        direction: TrackDirection,
        current: Double,
        goal: Double,
        unit: String,
        expectedFraction: Double? = nil
    ) -> TrackStyle {
        func amount(_ value: Double) -> String { "\(MacroValueFormatter.string(abs(value)))\(unit)" }
        let ratio = goal > 0 ? current / goal : 0
        let expected = expectedFraction.map { $0 * goal }
        var paceNote: String?

        switch direction {
        case .limit:
            let tone: TrackTone
            if goal > 0, current > goal { tone = .bad }
            else if ratio >= nearLimit { tone = .caution }
            else if let expected, expected > 0, current > expected * aheadPace, ratio >= 0.4 {
                tone = .caution
                paceNote = String(localized: "Ahead of your usual pace")
            } else { tone = .calm }
            let status = goal <= 0 ? String(localized: "No limit")
                : current > goal ? String(localized: "\(amount(current - goal)) over")
                : String(localized: "\(amount(goal - current)) left")
            return TrackStyle(direction: direction, tone: tone, status: status, paceNote: paceNote, paceFraction: expectedFraction)

        case .target:
            let tone: TrackTone
            if goal > 0, current >= goal { tone = .good }
            else if let expected, expected > goal * 0.15, current < expected * behindPace {
                tone = .caution
                paceNote = String(localized: "Behind your usual pace")
            } else { tone = .toGo }
            let status = goal <= 0 ? String(localized: "No goal")
                : current >= goal ? String(localized: "Goal met")
                : String(localized: "\(amount(goal - current)) to go")
            return TrackStyle(direction: direction, tone: tone, status: status, paceNote: paceNote, paceFraction: expectedFraction)

        case .range:
            let tone: TrackTone
            if goal > 0, ratio > 1 + rangeTolerance * 2.5 { tone = .bad }
            else if goal > 0, ratio > 1 + rangeTolerance { tone = .caution }
            else if goal > 0, ratio >= 1 - rangeTolerance { tone = .good }
            else if let expected, expected > 0, current > expected * aheadPace, ratio >= 0.4 {
                tone = .caution
                paceNote = String(localized: "Ahead of your usual pace")
            } else { tone = .calm }
            let status = goal <= 0 ? String(localized: "No goal")
                : tone == .good ? String(localized: "On target")
                : current > goal ? String(localized: "\(amount(current - goal)) over")
                : String(localized: "\(amount(goal - current)) left")
            return TrackStyle(direction: direction, tone: tone, status: status, paceNote: paceNote, paceFraction: expectedFraction)

        case .steady(let band):
            let tone: TrackTone = current > band.upperBound ? .caution : current >= band.lowerBound ? .good : .toGo
            let status = current > band.upperBound ? String(localized: "Above your usual")
                : String(localized: "Usual \(MacroValueFormatter.string(band.lowerBound))–\(MacroValueFormatter.string(band.upperBound))\(unit)")
            return TrackStyle(direction: direction, tone: tone, status: status, paceNote: nil, paceFraction: nil)
        }
    }
}

/// How much of a day's total the user has usually had by a time of day, from recent days, or
/// an even pace across waking hours when there is too little history.
enum TrackPace {
    /// A day's amounts with the minute of day each was logged.
    typealias Day = [(minute: Int, amount: Double)]

    static let historyDays = 21
    static let minimumDays = 5
    static let wakeMinute = 7 * 60
    static let sleepMinute = 21 * 60

    static func evenFraction(at minute: Int) -> Double {
        min(max(Double(minute - wakeMinute) / Double(sleepMinute - wakeMinute), 0), 1)
    }

    /// The average share of each day's total logged by `minute`, or nil with too few days.
    static func usualFraction(at minute: Int, days: [Day]) -> Double? {
        let fractions = days.compactMap { day -> Double? in
            let total = day.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return day.filter { $0.minute <= minute }.reduce(0) { $0 + $1.amount } / total
        }
        guard fractions.count >= minimumDays else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    static func expectedFraction(at minute: Int, days: [Day]) -> Double {
        usualFraction(at: minute, days: days) ?? evenFraction(at: minute)
    }

    /// Targets fall back to an even pace; limits and ranges show pace only from real history,
    /// since an even day says little about how much sodium is too much by noon.
    static func fraction(for direction: TrackDirection, at minute: Int, days: [Day]) -> Double? {
        direction == .target ? expectedFraction(at: minute, days: days) : usualFraction(at: minute, days: days)
    }

    /// The previous `historyDays` days of `amount` per entry, grouped by day.
    static func days<Item>(
        _ items: [Item],
        date: (Item) -> Date,
        amount: (Item) -> Double,
        before now: Date,
        calendar: Calendar = .current
    ) -> [Day] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -historyDays, to: today) else { return [] }
        let recent = items.filter { date($0) >= start && date($0) < today }
        return Dictionary(grouping: recent) { calendar.startOfDay(for: date($0)) }.values.map { day in
            day.map { item in
                let parts = calendar.dateComponents([.hour, .minute], from: date(item))
                return (minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), amount: amount(item))
            }
        }
    }

    static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Track styles for the Home bars.
enum HomeTrack {
    /// The style for a Home nutrient bar on `date`; pace only for today.
    static func style(
        for nutrient: HomeTopNutrient,
        current: Double,
        goal: Double,
        date: Date,
        entries: [FoodEntry],
        profile: HealthProfile = HealthProfileStore.shared.profile.effective(on: Date()),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrackStyle {
        var band: ClosedRange<Double>?
        if let optional = nutrient.optionalNutrient,
           profile.rules.contains(where: { $0.nutrient == optional && $0.direction == .steady }),
           let usual = SteadyBand.usual(optional, entries: entries, before: date, calendar: calendar) {
            band = SteadyBand.range(around: usual, for: optional)
        }
        let direction = TrackDirection.of(nutrient, profile: profile, steadyBand: band)
        let expected: Double? = calendar.isDate(date, inSameDayAs: now)
            ? TrackPace.fraction(
                for: direction, at: TrackPace.minute(of: now, calendar: calendar),
                days: TrackPace.days(entries, date: \.timestamp, amount: { nutrient.total(in: [$0]) }, before: now, calendar: calendar))
            : nil
        return TrackStyle.make(direction: direction, current: current, goal: goal, unit: nutrient.unit, expectedFraction: expected)
    }

    /// The style for the Home water bar; amounts in the display unit.
    static func waterStyle(
        current: Double,
        goal: Double,
        unit: String,
        date: Date,
        water: [WaterEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrackStyle {
        let expected: Double? = calendar.isDate(date, inSameDayAs: now)
            ? TrackPace.expectedFraction(
                at: TrackPace.minute(of: now, calendar: calendar),
                days: TrackPace.days(water, date: \.date, amount: { Double($0.milliliters) }, before: now, calendar: calendar))
            : nil
        return TrackStyle.make(direction: .target, current: current, goal: goal, unit: unit, expectedFraction: expected)
    }
}
