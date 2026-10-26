import Foundation

/// How strongly a sensitivity steers advice.
enum SensitivityLevel: String, Codable, CaseIterable, Identifiable {
    /// Keep it out, like the avoid list.
    case avoid
    /// A little is fine; rank foods with it lower.
    case limit
    /// Only tell Coach.
    case note

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avoid: String(localized: "Avoid")
        case .limit: String(localized: "Limit")
        case .note: String(localized: "Note")
        }
    }
}

/// Graded food sensitivities, unlike allergies on the avoid list. Matching is by whole word on
/// food names, ingredients and the AI's `contains` tags.
enum SensitivityKind: String, Codable, CaseIterable, Identifiable {
    case fructans
    case excessFructose
    case polyols
    case gos
    case lactose
    case histamine
    case reflux
    case caffeine
    case sulfites
    case msg
    case nightshades

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fructans: String(localized: "Fructans (wheat, onion, garlic)")
        case .excessFructose: String(localized: "Excess fructose (honey, apples, mango)")
        case .polyols: String(localized: "Polyols (sugar alcohols, stone fruit, mushrooms)")
        case .gos: String(localized: "GOS (beans, lentils, chickpeas)")
        case .lactose: String(localized: "Lactose")
        case .histamine: String(localized: "Histamine (aged, cured, fermented foods)")
        case .reflux: String(localized: "Reflux triggers (spicy, acidic, fatty, mint)")
        case .caffeine: String(localized: "Caffeine")
        case .sulfites: String(localized: "Sulfites")
        case .msg: String(localized: "MSG")
        case .nightshades: String(localized: "Nightshades (tomato, potato, peppers, eggplant)")
        }
    }

    /// Short English label for prompts and flags.
    var label: String {
        switch self {
        case .fructans: "fructans"
        case .excessFructose: "excess fructose"
        case .polyols: "polyols"
        case .gos: "GOS"
        case .lactose: "lactose"
        case .histamine: "histamine"
        case .reflux: "reflux triggers"
        case .caffeine: "caffeine"
        case .sulfites: "sulfites"
        case .msg: "MSG"
        case .nightshades: "nightshades"
        }
    }

    var isFODMAP: Bool { [.fructans, .excessFructose, .polyols, .gos, .lactose].contains(self) }

    var keywords: [String] {
        switch self {
        case .fructans:
            ["wheat", "rye", "barley", "onion", "onions", "garlic", "leek", "shallot", "scallion", "inulin", "chicory",
             "bread", "pasta", "couscous", "artichoke"]
        case .excessFructose:
            ["honey", "apple", "apples", "pear", "pears", "mango", "watermelon", "agave", "high fructose corn syrup",
             "dried fruit", "fruit juice", "asparagus"]
        case .polyols:
            ["sorbitol", "mannitol", "xylitol", "maltitol", "isomalt", "sugar free", "sugar-free", "peach", "plum", "cherry",
             "cherries", "apricot", "nectarine", "prune", "prunes", "mushroom", "mushrooms", "cauliflower", "avocado"]
        case .gos:
            // Singular forms: matching adds plurals, not the other way round.
            ["bean", "lentil", "chickpea", "hummus", "falafel", "split pea", "cashew", "pistachio"]
        case .lactose:
            AvoidList.lactoseTerms + ["yogurt", "yoghurt", "soft cheese"]
        case .histamine:
            ["aged cheese", "parmesan", "cheddar", "blue cheese", "salami", "pepperoni", "prosciutto", "cured", "smoked",
             "sauerkraut", "kimchi", "kombucha", "soy sauce", "miso", "fish sauce", "tuna", "mackerel", "sardines",
             "anchovies", "wine", "beer", "vinegar", "spinach", "eggplant", "leftovers"]
        case .reflux:
            ["spicy", "chili", "chilli", "hot sauce", "jalapeno", "jalapeño", "sriracha", "curry", "buffalo", "tomato sauce",
             "marinara", "salsa", "orange juice", "lemon", "lime", "grapefruit", "citrus", "fried", "fries", "chocolate",
             "peppermint", "mint", "soda", "cola", "coffee", "espresso"]
        case .caffeine:
            ["coffee", "espresso", "latte", "cappuccino", "cold brew", "energy drink", "black tea", "green tea", "matcha",
             "cola", "pre-workout"]
        case .sulfites:
            ["wine", "dried apricot", "dried apricots", "dried fruit", "raisins", "pickled", "pickles", "bottled lemon juice"]
        case .msg:
            ["msg", "monosodium glutamate", "instant noodles", "ramen", "bouillon", "stock cube", "seasoning packet"]
        case .nightshades:
            ["tomato", "tomatoes", "potato", "potatoes", "fries", "eggplant", "bell pepper", "peppers", "paprika",
             "cayenne", "chili", "chilli", "jalapeno", "jalapeño", "goji", "salsa", "marinara", "ketchup"]
        }
    }

    /// A text labeled with one of these is exempt (e.g. "lactose-free milk").
    var exemptions: [String] {
        switch self {
        case .fructans: ["gluten free", "gluten-free", "low fodmap", "low-fodmap", "garlic-infused oil"]
        case .lactose: ["lactose free", "lactose-free", "dairy free", "dairy-free", "vegan"]
        case .caffeine: ["decaf", "decaffeinated", "caffeine free", "caffeine-free"]
        default: []
        }
    }

    /// Look-alikes removed before matching (e.g. "sweet potato" is not a nightshade).
    var lookAlikes: [String] {
        switch self {
        case .nightshades: ["sweet potato", "sweet potatoes", "black pepper", "peppercorn"]
        case .lactose: AvoidList.lactoseLookAlikes
        case .fructans: ["buckwheat"]
        case .excessFructose: ["pineapple"]
        default: []
        }
    }
}

/// A user's own sensitivity, e.g. "coconut" at limit.
struct CustomSensitivity: Codable, Equatable, Identifiable {
    var term: String
    var level: SensitivityLevel
    var id: String { term }
}

/// The user's sensitivities and their levels, stored in the health profile.
struct Sensitivities: Codable, Equatable {
    var levels: [String: SensitivityLevel] = [:]
    var custom: [CustomSensitivity] = []
    /// No caffeine after this many minutes past midnight, when caffeine is set.
    var caffeineCutoffMinutes: Int?

    init(levels: [String: SensitivityLevel] = [:], custom: [CustomSensitivity] = [], caffeineCutoffMinutes: Int? = nil) {
        self.levels = levels
        self.custom = custom
        self.caffeineCutoffMinutes = caffeineCutoffMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        levels = try container.decodeIfPresent([String: SensitivityLevel].self, forKey: .levels) ?? [:]
        custom = try container.decodeIfPresent([CustomSensitivity].self, forKey: .custom) ?? []
        caffeineCutoffMinutes = try container.decodeIfPresent(Int.self, forKey: .caffeineCutoffMinutes)
    }

    var isEmpty: Bool { levels.isEmpty && custom.isEmpty }

    func level(for kind: SensitivityKind) -> SensitivityLevel? { levels[kind.rawValue] }

    /// One match: the sensitivity's label and the user's level for it.
    struct Match: Equatable, Hashable {
        let label: String
        let level: SensitivityLevel
    }

    /// The user's sensitivities that `texts` (names, ingredients, AI tags) hit. Caffeine also
    /// counts when the entry has caffeine after the cut-off time.
    func matches(texts: [String], caffeineMilligrams: Double? = nil, at time: Date? = nil,
                 calendar: Calendar = .current) -> [Match] {
        var found: [Match] = []
        for kind in SensitivityKind.allCases {
            guard let level = level(for: kind) else { continue }
            if Self.hits(texts, kind: kind) {
                found.append(Match(label: kind.label, level: level))
            } else if kind == .caffeine, (caffeineMilligrams ?? 0) >= 10 {
                found.append(Match(label: kind.label, level: level))
            }
        }
        if let cutoff = caffeineCutoffMinutes, let level = level(for: .caffeine), let time,
           found.contains(where: { $0.label == SensitivityKind.caffeine.label }) {
            let parts = calendar.dateComponents([.hour, .minute], from: time)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            found.removeAll { $0.label == SensitivityKind.caffeine.label }
            if minute >= cutoff { found.append(Match(label: "caffeine after the cut-off", level: level)) }
        }
        for item in custom where !item.term.isEmpty {
            let table = [PurineReference.Food("custom", [item.term], 0)]
            if texts.contains(where: { PurineReference.match($0, in: table) != nil }) {
                found.append(Match(label: item.term, level: item.level))
            }
        }
        return found
    }

    func matches(for entry: FoodEntry, extraTags: [String] = []) -> [Match] {
        let texts = [entry.name] + entry.ingredients.map(\.name)
            + [entry.productMetadata?.ingredientsText].compactMap { $0 } + extraTags
        return matches(texts: texts, caffeineMilligrams: entry.caffeine, at: entry.timestamp)
    }

    /// Every built-in sensitivity `texts` hit, whatever the user's settings: for symptom triggers.
    static func tags(for texts: [String]) -> [SensitivityKind] {
        SensitivityKind.allCases.filter { hits(texts, kind: $0) }
    }

    private static func hits(_ texts: [String], kind: SensitivityKind) -> Bool {
        let table = [PurineReference.Food(kind.rawValue, kind.keywords, 0)]
        return texts
            .filter { text in !kind.exemptions.contains { text.range(of: $0, options: .caseInsensitive) != nil } }
            .map { text in kind.lookAlikes.reduce(text) { $0.replacingOccurrences(of: $1, with: " ", options: .caseInsensitive) } }
            .contains { PurineReference.match($0, in: table) != nil }
    }
}
