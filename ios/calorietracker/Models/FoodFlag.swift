import Foundation

/// Foods that matter for a medicine rather than for a daily amount: grapefruit (colchicine,
/// several statins, many other drugs), cranberry (warfarin) and high-tyramine foods (MAOIs,
/// linezolid). Flags are worked out from the entry, never stored, so every food logged before
/// or after this existed is flagged the same way.
enum FoodFlag: String, CaseIterable, Identifiable {
    case grapefruit
    case cranberry
    case highTyramine
    /// Potassium-chloride salt substitutes, a risk with ACE inhibitors, ARBs and spironolactone.
    case saltSubstitute

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grapefruit: String(localized: "Grapefruit")
        case .cranberry: String(localized: "Cranberry")
        case .highTyramine: String(localized: "High tyramine")
        case .saltSubstitute: String(localized: "Potassium salt substitute")
        }
    }

    /// Fixed English wording for AI prompts.
    var promptName: String {
        switch self {
        case .grapefruit: "grapefruit"
        case .cranberry: "cranberry"
        case .highTyramine: "high tyramine"
        case .saltSubstitute: "potassium salt substitute"
        }
    }

    /// Tyramine in one logged portion at or above this counts as high. MAOI diet sheets treat
    /// about 6 mg as the amount that can start to raise blood pressure.
    static let highTyramineMilligrams: Double = 6

    /// Whole-word match terms. Seville (bitter) orange and pomelo carry the same compounds as grapefruit.
    static let keywords: [FoodFlag: [String]] = [
        .grapefruit: ["grapefruit", "pomelo", "pummelo", "seville orange", "bitter orange"],
        .cranberry: ["cranberry", "cranberries", "craisins"],
        .highTyramine: [
            "aged cheese", "aged cheddar", "cheddar", "parmesan", "parmigiano", "pecorino", "blue cheese",
            "gorgonzola", "stilton", "roquefort", "camembert", "brie", "gouda", "gruyere", "emmental",
            "swiss cheese", "provolone", "salami", "pepperoni", "chorizo", "summer sausage", "soppressata",
            "prosciutto", "soy sauce", "teriyaki", "miso", "natto", "tempeh", "fish sauce", "shrimp paste",
            "sauerkraut", "kimchi", "tap beer", "draft beer", "draught beer", "yeast extract", "marmite", "vegemite",
        ],
        // Not "no salt": that would match "no salt added" foods.
        .saltSubstitute: ["salt substitute", "lite salt", "losalt", "lo salt", "nosalt", "nu salt", "potassium chloride"],
    ]

    /// Every flag that applies to `entry`, from its name, ingredients, product ingredient list
    /// and tyramine estimate.
    static func flags(for entry: FoodEntry) -> Set<FoodFlag> {
        let texts = [entry.name] + entry.ingredients.map(\.name)
            + [entry.productMetadata?.ingredientsText].compactMap { $0 }
        let tyramine = entry.supplementalNutrients[SupplementalNutrient.tyramine.rawValue]
        return flags(texts: texts, tyramineMilligrams: tyramine)
    }

    static func flags(texts: [String], tyramineMilligrams: Double?) -> Set<FoodFlag> {
        var found = Set<FoodFlag>()
        for flag in allCases {
            let table = [PurineReference.Food(flag.rawValue, keywords[flag] ?? [], 0)]
            if texts.contains(where: { PurineReference.match($0, in: table) != nil }) {
                found.insert(flag)
            }
        }
        if let tyramineMilligrams, tyramineMilligrams >= highTyramineMilligrams {
            found.insert(.highTyramine)
        }
        return found
    }
}

extension FoodFlag {
    /// Snake-case name for exports.
    var exportKey: String {
        switch self {
        case .highTyramine: "high_tyramine"
        case .saltSubstitute: "salt_substitute"
        case .grapefruit, .cranberry: rawValue
        }
    }

    /// The entry's flags in a fixed order for exports, or nil when there are none.
    static func exportList(for entry: FoodEntry) -> [String]? {
        let flags = entry.foodFlags
        let keys = allCases.filter(flags.contains).map(\.exportKey)
        return keys.isEmpty ? nil : keys
    }
}

extension FoodEntry {
    var foodFlags: Set<FoodFlag> { FoodFlag.flags(for: self) }
}
