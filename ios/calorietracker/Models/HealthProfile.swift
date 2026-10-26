import Foundation
import Observation

/// A condition or plan the user manages, which shapes food advice and the home and
/// progress cards. Numbers stay in `OptionalNutrientGoals`, so the user edits them in
/// one place; an entry decides which goals matter and in which direction.
///
/// Later entries (conditions, medicines) add cases here; rule types beyond daily
/// limits and targets (steady bands, food flags, timing windows, dated courses)
/// extend `HealthRule`.
enum HealthEntryKind: String, Codable, CaseIterable, Identifiable {
    case gout
    case dash
    case diabetes
    case heartHealth
    case kidneyDisease
    case kidneyStones
    // Medicines
    case prednisone
    case colchicine
    case allopurinol
    case grapefruitStatin
    case otherStatin
    case potassiumRaising
    case metformin
    case glp1
    case maoi
    case warfarin
    case metronidazole

    var id: String { rawValue }

    var isMedicine: Bool {
        switch self {
        case .gout, .dash, .diabetes, .heartHealth, .kidneyDisease, .kidneyStones: false
        case .prednisone, .colchicine, .allopurinol, .grapefruitStatin, .otherStatin, .potassiumRaising, .metformin, .glp1, .maoi, .warfarin, .metronidazole: true
        }
    }

    var displayName: String {
        switch self {
        case .gout: String(localized: "Gout")
        case .dash: String(localized: "High blood pressure (DASH)")
        case .diabetes: String(localized: "Type 2 diabetes or prediabetes")
        case .heartHealth: String(localized: "High cholesterol or heart disease")
        case .kidneyDisease: String(localized: "Chronic kidney disease")
        case .kidneyStones: String(localized: "Kidney stones")
        case .prednisone: String(localized: "Prednisone or another corticosteroid")
        case .colchicine: String(localized: "Colchicine")
        case .allopurinol: String(localized: "Allopurinol")
        case .grapefruitStatin: String(localized: "Simvastatin or lovastatin")
        case .otherStatin: String(localized: "Another statin (atorvastatin, rosuvastatin, pravastatin…)")
        case .potassiumRaising: String(localized: "ACE inhibitor, ARB or spironolactone")
        case .metformin: String(localized: "Metformin")
        case .glp1: String(localized: "GLP-1 medicine (semaglutide, tirzepatide)")
        case .maoi: String(localized: "MAOI antidepressant or linezolid")
        case .warfarin: String(localized: "Warfarin")
        case .metronidazole: String(localized: "Metronidazole or tinidazole")
        }
    }

    var summary: String {
        switch self {
        case .gout: String(localized: "Limits purines, alcohol and added sugar, the dietary gout triggers.")
        case .dash: String(localized: "DASH eating plan: a sodium limit and potassium, calcium and magnesium targets.")
        case .diabetes: String(localized: "Limits added sugar and aims for fiber; Coach keeps carbs steady from meal to meal.")
        case .heartHealth: String(localized: "Limits saturated fat, trans fat and sodium; aims for fiber.")
        case .kidneyDisease: String(localized: "Limits sodium, potassium and phosphorus; Coach keeps protein at your goal.")
        case .kidneyStones: String(localized: "Limits oxalate and sodium; Coach reminds you about fluids and calcium from food.")
        case .prednisone: String(localized: "Limits sodium and added sugar; aims for calcium and vitamin D. Take it with food.")
        case .colchicine: String(localized: "Flags grapefruit, which can raise colchicine levels.")
        case .allopurinol: String(localized: "Coach reminds you to drink plenty of fluids.")
        case .grapefruitStatin: String(localized: "Flags grapefruit, which can raise the statin level.")
        case .otherStatin: String(localized: "No grapefruit flag; Coach knows you take a statin.")
        case .potassiumRaising: String(localized: "Limits potassium and flags potassium salt substitutes.")
        case .metformin: String(localized: "Limits alcohol and aims for vitamin B12.")
        case .glp1: String(localized: "Coach suggests smaller, lower-fat meals, protein first and enough fluids.")
        case .maoi: String(localized: "Limits tyramine and flags aged cheese, cured meats, soy sauce and other high-tyramine foods.")
        case .warfarin: String(localized: "Keeps vitamin K steady from day to day, limits alcohol and flags cranberry. Not needed for apixaban or rivaroxaban.")
        case .metronidazole: String(localized: "No alcohol during the course and for 3 days after it ends.")
        }
    }

    /// Fixed English wording for AI prompts, so advice does not depend on the app language.
    var promptGuidance: String {
        switch self {
        case .gout:
            "Gout: favor low-purine choices and name the purine load when comparing foods or suggesting meals. Alcohol (beer and spirits most) and added sugar (sweetened drinks) are the other dietary triggers."
        case .dash:
            "High blood pressure, following the DASH eating plan: keep sodium under the limit and favor foods rich in potassium, calcium and magnesium."
        case .diabetes:
            "Type 2 diabetes or prediabetes: keep carbohydrates moderate and steady from meal to meal, pair carbs with protein, fat or fiber, prefer whole grains and non-starchy vegetables, and keep added sugar and sweet drinks low."
        case .heartHealth:
            "High cholesterol or heart disease: keep saturated and trans fat low, prefer unsaturated fats (olive oil, nuts, fish), favor fiber from oats, beans, fruit and vegetables, and keep sodium down."
        case .kidneyDisease:
            "Chronic kidney disease: their doctor sets the sodium, potassium, phosphorus and protein limits; stay within them, never push protein above their protein goal, and watch phosphate additives in processed foods and colas."
        case .kidneyStones:
            "Kidney stones: encourage plenty of fluids, keep oxalate and sodium down, keep calcium at normal amounts from food (do not cut dairy), and go easy on animal protein, which also raises uric acid."
        case .prednisone:
            "Takes prednisone or another corticosteroid: it raises blood sugar, appetite, salt and water retention and blood pressure, and thins bones. Keep sodium and added sugar down, keep calcium and vitamin D up, and take it with food."
        case .colchicine:
            "Takes colchicine: grapefruit and grapefruit juice can raise its level; never suggest them."
        case .allopurinol:
            "Takes allopurinol: encourage plenty of fluids through the day."
        case .grapefruitStatin:
            "Takes simvastatin or lovastatin: grapefruit and grapefruit juice can raise the statin level; never suggest them."
        case .otherStatin:
            "Takes a statin without a grapefruit interaction (such as rosuvastatin or pravastatin); heart-healthy eating still helps."
        case .potassiumRaising:
            "Takes an ACE inhibitor, ARB or spironolactone: these raise blood potassium. Do not push high-potassium foods beyond their goal, and never suggest potassium-chloride salt substitutes (lite salt, NoSalt) or potassium supplements."
        case .metformin:
            "Takes metformin: keep alcohol low, and long-term use can lower vitamin B12, so B12 foods (meat, fish, eggs, dairy, fortified cereal) help."
        case .glp1:
            "Takes a GLP-1 medicine (semaglutide or tirzepatide): suggest smaller meals, lower-fat choices (fat slows the stomach and worsens nausea), protein first to keep muscle, and enough fluids."
        case .maoi:
            "Takes an MAOI or linezolid: high-tyramine foods (aged cheese, cured or fermented meats, soy sauce, miso, sauerkraut, kimchi, tap beer, yeast extract, overripe or spoiled foods) can cause a dangerous rise in blood pressure; never suggest them."
        case .warfarin:
            "Takes warfarin: vitamin K changes how warfarin works, so the goal is a steady amount from day to day, not avoiding greens. Warn about big swings (a large spinach or kale salad on a day they usually eat few greens, or suddenly dropping greens). Keep alcohol low and avoid large amounts of cranberry juice."
        case .metronidazole:
            "Takes metronidazole or tinidazole: no alcohol at all, including foods and sauces cooked with wine or beer and kombucha, during the course and for 3 days after it ends; never suggest them."
        }
    }

    /// Shown when the entry is on: numbers only the user's doctor can give.
    var setupNote: String? {
        switch self {
        case .kidneyDisease:
            String(localized: "Enter the sodium, potassium and phosphorus limits and the protein goal your doctor gave you. The defaults are not kidney-diet numbers.")
        case .kidneyStones:
            String(localized: "Ask your doctor which stone type you have; this entry suits calcium oxalate and uric acid stones.")
        default:
            nil
        }
    }

    var rules: [HealthRule] {
        switch self {
        case .gout:
            [.limit(.purines, by: self), .limit(.alcohol, by: self), .limit(.addedSugar, by: self)]
        case .dash:
            [.limit(.sodium, by: self), .target(.potassium, by: self), .target(.calcium, by: self), .target(.magnesium, by: self)]
        case .diabetes:
            [.limit(.addedSugar, by: self), .target(.fiber, by: self)]
        case .heartHealth:
            [.limit(.saturatedFat, by: self), .limit(.transFat, by: self), .limit(.sodium, by: self), .target(.fiber, by: self)]
        case .kidneyDisease:
            [.limit(.sodium, by: self), .limit(.potassium, by: self), .limit(.phosphorus, by: self)]
        case .kidneyStones:
            [.limit(.oxalate, by: self), .limit(.sodium, by: self)]
        case .prednisone:
            [.limit(.sodium, by: self), .limit(.addedSugar, by: self), .target(.calcium, by: self), .target(.vitaminD, by: self)]
        case .potassiumRaising:
            [.limit(.potassium, by: self)]
        case .metformin:
            [.limit(.alcohol, by: self), .target(.vitaminB12, by: self)]
        case .maoi:
            [.limit(.tyramine, by: self)]
        case .warfarin:
            [.steady(.vitaminK, by: self), .limit(.alcohol, by: self)]
        case .colchicine, .allopurinol, .grapefruitStatin, .otherStatin, .glp1, .metronidazole:
            []
        }
    }

    /// Entries that can be limited to a course with start and end dates.
    var supportsCourse: Bool { self == .prednisone || self == .metronidazole }

    /// Days after a course ends that its rules still apply.
    var courseTailDays: Int { self == .metronidazole ? 3 : 0 }

    /// Foods to keep out because of a medicine, regardless of amount.
    var avoidedFoodFlags: [FoodFlag] {
        switch self {
        case .colchicine, .grapefruitStatin: [.grapefruit]
        case .potassiumRaising: [.saltSubstitute]
        case .maoi: [.highTyramine]
        case .warfarin: [.cranberry]
        case .metronidazole: [.alcohol]
        default: []
        }
    }
}

/// One nutrient an entry cares about, and which way it pushes. The amount is the
/// user's goal for that nutrient.
struct HealthRule: Equatable {
    enum Direction: Equatable {
        /// Stay at or under the goal.
        case limit
        /// Reach at least the goal.
        case target
        /// Stay near the user's own usual daily amount (`SteadyBand`); the goal number is not used.
        case steady
    }

    let nutrient: OptionalNutrient
    let direction: Direction
    /// The entry's display name, for conflict messages.
    let source: String

    static func limit(_ nutrient: OptionalNutrient, by kind: HealthEntryKind) -> HealthRule {
        HealthRule(nutrient: nutrient, direction: .limit, source: kind.displayName)
    }

    static func target(_ nutrient: OptionalNutrient, by kind: HealthEntryKind) -> HealthRule {
        HealthRule(nutrient: nutrient, direction: .target, source: kind.displayName)
    }

    static func steady(_ nutrient: OptionalNutrient, by kind: HealthEntryKind) -> HealthRule {
        HealthRule(nutrient: nutrient, direction: .steady, source: kind.displayName)
    }
}

/// Two entries pulling one nutrient in opposite directions, e.g. DASH raising potassium
/// while kidney disease or an ACE inhibitor limits it. Shown, never resolved silently.
struct HealthConflict: Equatable, Identifiable {
    let nutrient: OptionalNutrient
    let raisedBy: [String]
    let limitedBy: [String]

    var id: String { nutrient.rawValue }

    static func find(in rules: [HealthRule]) -> [HealthConflict] {
        var order: [OptionalNutrient] = []
        var byNutrient: [OptionalNutrient: [HealthRule]] = [:]
        for rule in rules {
            if byNutrient[rule.nutrient] == nil { order.append(rule.nutrient) }
            byNutrient[rule.nutrient, default: []].append(rule)
        }
        return order.compactMap { nutrient in
            let rules = byNutrient[nutrient] ?? []
            let raisedBy = rules.filter { $0.direction == .target }.map(\.source)
            let limitedBy = rules.filter { $0.direction == .limit }.map(\.source)
            guard !raisedBy.isEmpty, !limitedBy.isEmpty else { return nil }
            return HealthConflict(nutrient: nutrient, raisedBy: raisedBy, limitedBy: limitedBy)
        }
    }
}

struct HealthProfile: Codable, Equatable {
    var entries: [HealthEntryKind]
    /// Optional so profiles saved before the list existed still decode.
    var avoid: AvoidList?
    /// Course dates by entry raw value, for entries that only apply for a while.
    var courses: [String: HealthCourse]?

    init(entries: [HealthEntryKind] = [], avoid: AvoidList? = nil, courses: [String: HealthCourse]? = nil) {
        self.entries = entries
        self.avoid = avoid
        self.courses = courses
    }

    func course(for kind: HealthEntryKind) -> HealthCourse? { courses?[kind.rawValue] }

    /// True when `kind` applies on `date`: always without a course, otherwise from the start
    /// day through the end day plus the entry's tail days.
    func isActive(_ kind: HealthEntryKind, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let course = course(for: kind) else { return true }
        return course.applies(on: date, tailDays: kind.courseTailDays, calendar: calendar)
    }

    /// This profile with only the entries that apply on `date`.
    func effective(on date: Date, calendar: Calendar = .current) -> HealthProfile {
        var copy = self
        copy.entries = entries.filter { isActive($0, on: date, calendar: calendar) }
        return copy
    }

    var avoidList: AvoidList { avoid ?? AvoidList() }

    /// True when there is nothing for Coach or Suggestions to weigh.
    var isEmpty: Bool { entries.isEmpty && avoidList.isEmpty }

    func contains(_ kind: HealthEntryKind) -> Bool { entries.contains(kind) }

    var rules: [HealthRule] { entries.flatMap(\.rules) }

    var conflicts: [HealthConflict] { HealthConflict.find(in: rules) }

    /// Each food flag the active medicines rule out, with the entries that rule it out.
    var avoidedFoodFlags: [(flag: FoodFlag, sources: [HealthEntryKind])] {
        FoodFlag.allCases.compactMap { flag in
            let sources = entries.filter { $0.avoidedFoodFlags.contains(flag) }
            return sources.isEmpty ? nil : (flag, sources)
        }
    }

    /// What the fork showed before the profile existed: the Gout card and the DASH
    /// scorecard were always on. Goal numbers are not touched.
    static let migratedDefault = HealthProfile(entries: [.gout, .dash])
}

@Observable
final class HealthProfileStore {
    static let storageKey = "fork.healthProfile"
    static let shared = HealthProfileStore()

    private(set) var profile = HealthProfile()
    private let blob: PersistedBlobGuard

    init(defaults: UserDefaults = .standard, corruptBackupDirectory: URL? = nil) {
        blob = PersistedBlobGuard(defaults: defaults, key: Self.storageKey, backupDirectory: corruptBackupDirectory)
        reload()
    }

    func reload() {
        switch blob.loadValue(HealthProfile.self) {
        case .missing:
            profile = .migratedDefault
            blob.save(profile)
        case .decoded(let decoded, _):
            profile = decoded
        case .corrupt:
            // Keep showing what the fork always showed; the bad blob was backed up.
            profile = .migratedDefault
        }
    }

    func contains(_ kind: HealthEntryKind) -> Bool { profile.contains(kind) }

    func setCourse(_ course: HealthCourse?, for kind: HealthEntryKind) {
        guard !blob.isWriteBlocked else { return }
        var courses = profile.courses ?? [:]
        courses[kind.rawValue] = course
        profile.courses = courses.isEmpty ? nil : courses
        blob.save(profile)
    }

    func setAvoidList(_ list: AvoidList) {
        guard !blob.isWriteBlocked else { return }
        profile.avoid = list.isEmpty ? nil : list
        blob.save(profile)
    }

    func set(_ kind: HealthEntryKind, active: Bool) {
        guard !blob.isWriteBlocked, profile.contains(kind) != active else { return }
        if active {
            profile.entries = HealthEntryKind.allCases.filter { $0 == kind || profile.contains($0) }
        } else {
            profile.entries.removeAll { $0 == kind }
            profile.courses?[kind.rawValue] = nil
            if profile.courses?.isEmpty == true { profile.courses = nil }
        }
        blob.save(profile)
    }
}

/// A short course: an entry applies from `start` through `end`, plus the entry's tail days.
struct HealthCourse: Codable, Equatable {
    var start: Date
    var end: Date

    /// The last day the entry's rules apply.
    func lastDay(tailDays: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: tailDays, to: calendar.startOfDay(for: end)) ?? end
    }

    func applies(on date: Date, tailDays: Int, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= lastDay(tailDays: tailDays, calendar: calendar)
    }
}
