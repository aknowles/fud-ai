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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gout: String(localized: "Gout")
        case .dash: String(localized: "High blood pressure (DASH)")
        case .diabetes: String(localized: "Type 2 diabetes or prediabetes")
        case .heartHealth: String(localized: "High cholesterol or heart disease")
        case .kidneyDisease: String(localized: "Chronic kidney disease")
        case .kidneyStones: String(localized: "Kidney stones")
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

    init(entries: [HealthEntryKind] = [], avoid: AvoidList? = nil) {
        self.entries = entries
        self.avoid = avoid
    }

    var avoidList: AvoidList { avoid ?? AvoidList() }

    /// True when there is nothing for Coach or Suggestions to weigh.
    var isEmpty: Bool { entries.isEmpty && avoidList.isEmpty }

    func contains(_ kind: HealthEntryKind) -> Bool { entries.contains(kind) }

    var rules: [HealthRule] { entries.flatMap(\.rules) }

    var conflicts: [HealthConflict] { HealthConflict.find(in: rules) }

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
        }
        blob.save(profile)
    }
}
