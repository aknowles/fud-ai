import Foundation

/// Something the Trends chart can plot per day.
enum TrendMetric: Hashable, Identifiable {
    case calories, protein, carbs, fat
    case nutrient(OptionalNutrient)
    case water
    case weight
    case steps
    /// DASH goals met that day, 0–4.
    case dashScore

    var id: String {
        switch self {
        case .calories: "calories"
        case .protein: "protein"
        case .carbs: "carbs"
        case .fat: "fat"
        case .nutrient(let nutrient): nutrient.rawValue
        case .water: "water"
        case .weight: "weight"
        case .steps: "steps"
        case .dashScore: "dashScore"
        }
    }

    var label: String {
        switch self {
        case .calories: String(localized: "Calories")
        case .protein: String(localized: "Protein")
        case .carbs: String(localized: "Carbs")
        case .fat: String(localized: "Fat")
        case .nutrient(let nutrient): nutrient.displayName
        case .water: String(localized: "Water")
        case .weight: String(localized: "Weight")
        case .steps: String(localized: "Steps")
        case .dashScore: String(localized: "DASH score")
        }
    }

    /// Unit as shown; weight and water follow the user's units.
    func unit(weightInKg: Bool, water: WaterUnit) -> String {
        switch self {
        case .calories: "kcal"
        case .protein, .carbs, .fat: "g"
        case .nutrient(let nutrient): nutrient.unit
        case .water: water.symbol
        case .weight: weightInKg ? "kg" : "lb"
        case .steps: String(localized: "steps")
        case .dashScore: "/4"
        }
    }

    /// The food-diary breakdown behind a day's value, where there is one.
    var nutrientMetric: NutrientMetric? {
        switch self {
        case .calories: .calories
        case .protein: .protein
        case .carbs: .carbs
        case .fat: .fat
        case .nutrient(let nutrient): .nutrient(nutrient)
        case .water, .weight, .steps, .dashScore: nil
        }
    }

    /// True for series that come from the food diary, which have no value on unlogged days.
    var isFromDiary: Bool { nutrientMetric != nil || self == .dashScore }

    /// Which way is good, for coloring days and drawing the goal.
    func direction(profile: HealthProfile) -> TrackDirection? {
        switch self {
        case .calories, .carbs, .fat: .range
        case .protein, .water, .steps, .dashScore: .target
        case .nutrient(let nutrient):
            // A steady goal has no fixed line; color it as a target.
            TrackDirection.of(nutrient, profile: profile).isSteady ? .target : TrackDirection.of(nutrient, profile: profile)
        case .weight: nil
        }
    }

    /// Everything the picker offers: macros, every optional nutrient, then body and activity.
    static var all: [TrendMetric] {
        [.calories, .protein, .carbs, .fat] + OptionalNutrient.allCases.map(TrendMetric.nutrient)
            + [.water, .weight, .steps, .dashScore]
    }
}

extension TrackDirection {
    var isSteady: Bool {
        if case .steady = self { return true }
        return false
    }
}

/// One day's value; nil when there is nothing to plot (no food logged, no weigh-in).
struct TrendDay: Identifiable, Equatable {
    let day: Date
    let value: Double?
    var id: Date { day }
}

/// A ready-made view: two series and the symptoms to mark.
struct TrendPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let primary: TrendMetric
    let secondary: TrendMetric?
    let markers: Set<SymptomKind>

    static let gout = TrendPreset(id: "gout", name: String(localized: "Gout"), primary: .nutrient(.purines),
                                  secondary: .nutrient(.alcohol), markers: [.goutFlare])
    static let bloodPressure = TrendPreset(id: "bp", name: String(localized: "Blood pressure"), primary: .nutrient(.sodium),
                                           secondary: .nutrient(.potassium), markers: [])
    static let dash = TrendPreset(id: "dash", name: String(localized: "DASH"), primary: .dashScore,
                                  secondary: .nutrient(.sodium), markers: [])
    static let weight = TrendPreset(id: "weight", name: String(localized: "Weight"), primary: .weight,
                                    secondary: .calories, markers: [])
    static let digestion = TrendPreset(id: "digestion", name: String(localized: "Digestion"), primary: .nutrient(.fiber),
                                       secondary: .nutrient(.addedSugar),
                                       markers: [.bloating, .gas, .heartburn, .stomachPain, .diarrhea, .constipation])

    static let all: [TrendPreset] = [.gout, .bloodPressure, .dash, .weight, .digestion]

    /// Presets that fit the health profile first.
    static func ordered(for profile: HealthProfile) -> [TrendPreset] {
        var first: [TrendPreset] = []
        if profile.contains(.gout) { first.append(.gout) }
        if profile.contains(.dash) { first += [.bloodPressure, .dash] }
        return first + all.filter { preset in !first.contains(preset) }
    }
}

/// Builds the chart's series from the stores' data.
enum TrendData {
    static let rangeChoices = [7, 30, 90]
    static let averageWindow = 7

    /// Each day from `start` through `end`, oldest first.
    static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last, days.count < 400 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    struct Sources {
        var foodsByDay: [Date: [FoodEntry]] = [:]
        var water: [WaterEntry] = []
        var weights: [WeightEntry] = []
        var steps: [Date: Int] = [:]
        var goals: OptionalNutrientGoals = .defaults
        var weightInKg = true
        var waterUnit: WaterUnit = .milliliters
        var countDrinks = true

        static func grouping(_ foods: [FoodEntry], calendar: Calendar = .current) -> [Date: [FoodEntry]] {
            Dictionary(grouping: foods) { calendar.startOfDay(for: $0.timestamp) }
        }
    }

    static func series(_ metric: TrendMetric, days: [Date], sources: Sources, calendar: Calendar = .current) -> [TrendDay] {
        days.map { day in TrendDay(day: day, value: value(metric, on: day, sources: sources, calendar: calendar)) }
    }

    static func value(_ metric: TrendMetric, on day: Date, sources: Sources, calendar: Calendar = .current) -> Double? {
        let foods = sources.foodsByDay[day] ?? []
        switch metric {
        case .calories, .protein, .carbs, .fat, .nutrient:
            guard !foods.isEmpty, let nutrientMetric = metric.nutrientMetric else { return nil }
            return foods.reduce(0) { $0 + (nutrientMetric.amount(in: $1) ?? 0) }
        case .dashScore:
            guard !foods.isEmpty else { return nil }
            let card = DASHScorecard(entries: foods, date: day, goals: sources.goals, calendar: calendar)
            return Double(card.todayScore)
        case .water:
            let logged = sources.water.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.milliliters }
            let drinks = sources.countDrinks ? Hydration.milliliters(from: foods) : 0
            let total = logged + drinks
            return total > 0 ? sources.waterUnit.displayAmount(forMilliliters: total) : nil
        case .weight:
            let readings = sources.weights.filter { calendar.isDate($0.date, inSameDayAs: day) }
            guard !readings.isEmpty else { return nil }
            let kg = readings.reduce(0) { $0 + $1.weightKg } / Double(readings.count)
            return sources.weightInKg ? kg : kg * 2.20462
        case .steps:
            return sources.steps[day].map(Double.init)
        }
    }

    /// The trailing average over `window` days of the days that have a value.
    static func rollingAverage(_ series: [TrendDay], window: Int = averageWindow) -> [TrendDay] {
        series.indices.map { index in
            let slice = series[max(0, index - window + 1)...index].compactMap(\.value)
            let value: Double? = series[index].value == nil && slice.isEmpty ? nil
                : slice.isEmpty ? nil : slice.reduce(0, +) / Double(slice.count)
            return TrendDay(day: series[index].day, value: value)
        }
    }

    /// The goal line for a metric, in display units, or nil.
    static func goal(_ metric: TrendMetric, profile: UserProfile?, goals: OptionalNutrientGoals,
                     waterGoalMl: Int, waterUnit: WaterUnit, weightInKg: Bool) -> Double? {
        switch metric {
        case .calories: profile.map { Double($0.effectiveCalories) }
        case .protein: profile.map { Double($0.effectiveProtein) }
        case .carbs: profile.map { Double($0.effectiveCarbs) }
        case .fat: profile.map { Double($0.effectiveFat) }
        case .nutrient(let nutrient):
            goals.goal(for: nutrient) > 0 ? Double(goals.goal(for: nutrient)) : nil
        case .water: waterUnit.displayAmount(forMilliliters: waterGoalMl)
        case .weight: profile?.goalWeightKg.map { weightInKg ? $0 : $0 * 2.20462 }
        case .steps: nil
        case .dashScore: Double(DASHPreset.nutrients.count)
        }
    }

    /// Symptom days to mark, by day, with the worst severity that day.
    static func markers(_ symptoms: [Symptom], kinds: Set<SymptomKind>, days: [Date], calendar: Calendar = .current)
        -> [(day: Date, name: String, severity: Int)] {
        guard !kinds.isEmpty, let first = days.first, let last = days.last else { return [] }
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let matching = symptoms.filter { kinds.contains($0.kind) && $0.date >= first && $0.date < end }
        return Dictionary(grouping: matching) { calendar.startOfDay(for: $0.date) }
            .map { day, list in
                let worst = list.max { $0.severity < $1.severity }!
                return (day: day, name: worst.name, severity: worst.severity)
            }
            .sorted { $0.day < $1.day }
    }

    /// Maps the secondary series onto the primary axis: secondary × factor.
    static func scaleFactor(primaryMax: Double, secondaryMax: Double) -> Double {
        guard secondaryMax > 0 else { return 1 }
        return max(primaryMax, 1) / secondaryMax
    }

    /// The top of an axis: the largest value or goal, with headroom.
    static func axisTop(_ series: [TrendDay], goal: Double?) -> Double {
        let top = max(series.compactMap(\.value).max() ?? 0, goal ?? 0)
        return top > 0 ? top * 1.15 : 1
    }
}
