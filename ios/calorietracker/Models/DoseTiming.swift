import Foundation

/// Kinds of food a dose window keeps away from a medicine.
enum DoseFoodClass: String, CaseIterable, Identifiable {
    /// Anything with calories (levothyroxine wants an empty stomach).
    case anyFood
    /// Dairy, calcium, iron, magnesium and zinc, including antacids and supplements.
    case minerals
    case coffee
    case soy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anyFood: String(localized: "food")
        case .minerals: String(localized: "dairy, calcium, iron, magnesium and zinc")
        case .coffee: String(localized: "coffee")
        case .soy: String(localized: "soy")
        }
    }

    var promptName: String {
        switch self {
        case .anyFood: "any food"
        case .minerals: "dairy, calcium, iron, magnesium and zinc (antacids and supplements too)"
        case .coffee: "coffee"
        case .soy: "soy"
        }
    }

    static let keywords: [DoseFoodClass: [String]] = [
        .minerals: [
            // No "latte": an oat-milk latte is not dairy, and a dairy one counts through its calcium.
            "milk", "cheese", "yogurt", "yoghurt", "kefir", "ice cream", "milkshake",
            "antacid", "tums", "rolaids", "maalox", "mylanta", "calcium carbonate", "calcium supplement",
            "iron supplement", "ferrous", "multivitamin", "zinc supplement", "magnesium supplement",
        ],
        .coffee: ["coffee", "espresso", "latte", "cappuccino", "americano", "cold brew", "macchiato", "mocha", "flat white"],
        .soy: ["soy", "tofu", "edamame", "tempeh", "miso", "soybean", "soybeans"],
    ]

    /// Plant milks are not dairy; a calcium-fortified one still counts through its calcium.
    static let mineralLookAlikes = ["oat milk", "almond milk", "soy milk", "coconut milk", "rice milk", "cashew milk"]

    /// Amounts in one portion that count as a mineral load.
    static let mineralAmounts: [OptionalNutrient: Double] = [.calcium: 150, .iron: 4, .magnesium: 100, .zinc: 5]

    static func classes(for entry: FoodEntry) -> Set<DoseFoodClass> {
        let texts = [entry.name] + entry.ingredients.map(\.name)
        func matches(_ terms: [String], in candidates: [String]) -> Bool {
            let table = [PurineReference.Food("dose", terms, 0)]
            return candidates.contains { PurineReference.match($0, in: table) != nil }
        }
        var found = Set<DoseFoodClass>()
        if entry.calories > 5 { found.insert(.anyFood) }
        let mineralTexts = texts.map { text in
            mineralLookAlikes.reduce(text) { $0.replacingOccurrences(of: $1, with: " ", options: .caseInsensitive) }
        }
        if matches(keywords[.minerals] ?? [], in: mineralTexts)
            || mineralAmounts.contains(where: { (entry.amount(of: $0.key) ?? 0) >= $0.value }) {
            found.insert(.minerals)
        }
        if matches(keywords[.coffee] ?? [], in: texts) { found.insert(.coffee) }
        if matches(keywords[.soy] ?? [], in: texts) { found.insert(.soy) }
        return found
    }
}

/// Keep `foods` out from `minutesBefore` a dose until `minutesAfter` it.
struct DoseWindowRule: Equatable {
    let foods: DoseFoodClass
    let minutesBefore: Int
    let minutesAfter: Int
}

/// The user's dose times for an entry, as minutes after midnight, and their own mineral window.
struct DoseSchedule: Codable, Equatable {
    var times: [Int] = []
    /// Overrides for the minerals window, in minutes; nil keeps the entry's default.
    var mineralsBefore: Int?
    var mineralsAfter: Int?

    init(times: [Int] = [], mineralsBefore: Int? = nil, mineralsAfter: Int? = nil) {
        self.times = times.sorted()
        self.mineralsBefore = mineralsBefore
        self.mineralsAfter = mineralsAfter
    }
}

/// A logged or proposed food that falls inside a dose window.
struct DoseConflict: Equatable {
    let kind: HealthEntryKind
    let dose: Date
    let foods: DoseFoodClass
    /// Minutes from the dose to the food; negative when the food comes first.
    let minutesFromDose: Int
    /// When the window for this food ends.
    let windowEnd: Date
}

extension HealthEntryKind {
    var supportsDoseTimes: Bool { self == .quinoloneTetracycline || self == .levothyroxine }

    /// Short name for warnings, where the full entry name would crowd the line.
    var doseName: String {
        switch self {
        case .quinoloneTetracycline: String(localized: "antibiotic")
        case .levothyroxine: String(localized: "levothyroxine")
        default: displayName
        }
    }

    /// Common label advice. Ciprofloxacin: take it 2 hours before or 6 hours after minerals.
    /// Levothyroxine: empty stomach, coffee an hour later, minerals and soy 4 hours apart.
    var defaultDoseWindows: [DoseWindowRule] {
        switch self {
        case .quinoloneTetracycline:
            [DoseWindowRule(foods: .minerals, minutesBefore: 360, minutesAfter: 120)]
        case .levothyroxine:
            [
                DoseWindowRule(foods: .anyFood, minutesBefore: 180, minutesAfter: 30),
                DoseWindowRule(foods: .coffee, minutesBefore: 0, minutesAfter: 60),
                DoseWindowRule(foods: .minerals, minutesBefore: 240, minutesAfter: 240),
                DoseWindowRule(foods: .soy, minutesBefore: 240, minutesAfter: 240),
            ]
        default:
            []
        }
    }
}

extension HealthProfile {
    func doseSchedule(for kind: HealthEntryKind) -> DoseSchedule? { doseSchedules?[kind.rawValue] }

    /// The entry's windows with the user's mineral window applied.
    func doseWindows(for kind: HealthEntryKind) -> [DoseWindowRule] {
        let schedule = doseSchedule(for: kind)
        return kind.defaultDoseWindows.map { rule in
            guard rule.foods == .minerals, let schedule else { return rule }
            return DoseWindowRule(foods: .minerals,
                                  minutesBefore: schedule.mineralsBefore ?? rule.minutesBefore,
                                  minutesAfter: schedule.mineralsAfter ?? rule.minutesAfter)
        }
    }
}

enum DoseTiming {
    /// Every dose on the day before, of and after `time`, so windows that cross midnight count.
    static func doses(for schedule: DoseSchedule, around time: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: time)
        return (-1...1).flatMap { offset -> [Date] in
            guard let base = calendar.date(byAdding: .day, value: offset, to: day) else { return [] }
            return schedule.times.compactMap { calendar.date(byAdding: .minute, value: $0, to: base) }
        }
    }

    /// The dose windows `entry` falls inside at `time` (its own timestamp by default), for the
    /// entries in `profile` that apply then.
    static func conflicts(
        for entry: FoodEntry,
        at time: Date? = nil,
        profile: HealthProfile,
        calendar: Calendar = .current
    ) -> [DoseConflict] {
        let time = time ?? entry.timestamp
        let effective = profile.effective(on: time, calendar: calendar)
        let classes = DoseFoodClass.classes(for: entry)
        var found: [DoseConflict] = []
        for kind in effective.entries where kind.supportsDoseTimes {
            guard let schedule = effective.doseSchedule(for: kind) else { continue }
            for dose in doses(for: schedule, around: time, calendar: calendar) {
                for rule in effective.doseWindows(for: kind) where classes.contains(rule.foods) {
                    let start = dose.addingTimeInterval(TimeInterval(-rule.minutesBefore * 60))
                    let end = dose.addingTimeInterval(TimeInterval(rule.minutesAfter * 60))
                    guard time > start, time < end else { continue }
                    found.append(DoseConflict(kind: kind, dose: dose, foods: rule.foods,
                                              minutesFromDose: Int(time.timeIntervalSince(dose) / 60), windowEnd: end))
                }
            }
        }
        return found
    }

    /// Windows that have not ended yet on `day`, soonest first, for the home card and Coach.
    static func upcomingWindows(
        on day: Date,
        after now: Date,
        profile: HealthProfile,
        calendar: Calendar = .current
    ) -> [(kind: HealthEntryKind, dose: Date, rule: DoseWindowRule, start: Date, end: Date)] {
        let effective = profile.effective(on: day, calendar: calendar)
        var found: [(kind: HealthEntryKind, dose: Date, rule: DoseWindowRule, start: Date, end: Date)] = []
        for kind in effective.entries where kind.supportsDoseTimes {
            guard let schedule = effective.doseSchedule(for: kind) else { continue }
            for dose in doses(for: schedule, around: day, calendar: calendar) where calendar.isDate(dose, inSameDayAs: day) {
                for rule in effective.doseWindows(for: kind) {
                    let start = dose.addingTimeInterval(TimeInterval(-rule.minutesBefore * 60))
                    let end = dose.addingTimeInterval(TimeInterval(rule.minutesAfter * 60))
                    if end > now { found.append((kind, dose, rule, start, end)) }
                }
            }
        }
        return found.sorted { $0.start < $1.start }
    }
}
