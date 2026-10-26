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
    /// Alcoholic drinks and foods, for metronidazole and tinidazole.
    case alcohol

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grapefruit: String(localized: "Grapefruit")
        case .cranberry: String(localized: "Cranberry")
        case .highTyramine: String(localized: "High tyramine")
        case .saltSubstitute: String(localized: "Potassium salt substitute")
        case .alcohol: String(localized: "Alcohol")
        }
    }

    /// Fixed English wording for AI prompts.
    var promptName: String {
        switch self {
        case .grapefruit: "grapefruit"
        case .cranberry: "cranberry"
        case .highTyramine: "high tyramine"
        case .saltSubstitute: "potassium salt substitute"
        case .alcohol: "alcohol"
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
        .alcohol: [
            "beer", "ale", "lager", "stout", "ipa", "wine", "prosecco", "champagne", "cider", "sake", "vodka",
            "whiskey", "whisky", "bourbon", "rum", "gin", "tequila", "mezcal", "brandy", "cognac", "liqueur",
            "cocktail", "margarita", "martini", "mimosa", "sangria", "mojito", "hard seltzer", "spritz",
        ],
    ]

    /// A text labeled with one of these is exempt from that flag altogether.
    static let exemptions: [FoodFlag: [String]] = [
        .alcohol: ["non-alcoholic", "non alcoholic", "alcohol-free", "alcohol free", "0.0%"],
    ]

    /// Removed from the text before matching that flag, so a look-alike does not match.
    static let lookAlikes: [FoodFlag: [String]] = [
        .alcohol: ["root beer", "ginger beer", "ginger ale", "wine vinegar", "rum extract", "rum raisin"],
    ]

    /// An alcohol estimate at or above this, in grams, counts as containing alcohol.
    static let alcoholGrams: Double = 0.5

    /// Every flag that applies to `entry`, from its name, ingredients, product ingredient list
    /// and tyramine estimate.
    static func flags(for entry: FoodEntry) -> Set<FoodFlag> {
        let texts = [entry.name] + entry.ingredients.map(\.name)
            + [entry.productMetadata?.ingredientsText].compactMap { $0 }
        let tyramine = entry.supplementalNutrients[SupplementalNutrient.tyramine.rawValue]
        return flags(texts: texts, tyramineMilligrams: tyramine, alcoholGrams: entry.supplementalNutrients[SupplementalNutrient.alcohol.rawValue])
    }

    static func flags(texts: [String], tyramineMilligrams: Double?, alcoholGrams: Double? = nil) -> Set<FoodFlag> {
        var found = Set<FoodFlag>()
        for flag in allCases {
            let table = [PurineReference.Food(flag.rawValue, keywords[flag] ?? [], 0)]
            let exempt = exemptions[flag] ?? []
            let cleaned = texts
                .filter { text in !exempt.contains { text.range(of: $0, options: .caseInsensitive) != nil } }
                .map { text in
                    (lookAlikes[flag] ?? []).reduce(text) { $0.replacingOccurrences(of: $1, with: " ", options: .caseInsensitive) }
                }
            if cleaned.contains(where: { PurineReference.match($0, in: table) != nil }) {
                found.insert(flag)
            }
        }
        if let tyramineMilligrams, tyramineMilligrams >= highTyramineMilligrams {
            found.insert(.highTyramine)
        }
        if let alcoholGrams, alcoholGrams >= Self.alcoholGrams {
            found.insert(.alcohol)
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
        case .grapefruit, .cranberry, .alcohol: rawValue
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
