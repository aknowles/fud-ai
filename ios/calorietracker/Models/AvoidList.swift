import Foundation

/// Foods the user must keep out entirely: gluten for celiac disease, lactose, and their own
/// terms for allergies. Matching is by whole word on the food name, its ingredients and a
/// product's ingredient and allergen lists, so it can miss ingredients nobody wrote down.
/// A "gluten-free" or "dairy-free" label exempts a food from that category; a product's
/// allergen list still counts.
struct AvoidList: Codable, Equatable {
    var celiac = false
    var lactose = false
    /// The user's own terms, e.g. "peanut", "shellfish", "sesame".
    var custom: [String] = []

    init(celiac: Bool = false, lactose: Bool = false, custom: [String] = []) {
        self.celiac = celiac
        self.lactose = lactose
        self.custom = custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        celiac = try container.decodeIfPresent(Bool.self, forKey: .celiac) ?? false
        lactose = try container.decodeIfPresent(Bool.self, forKey: .lactose) ?? false
        custom = try container.decodeIfPresent([String].self, forKey: .custom) ?? []
    }

    var isEmpty: Bool { !celiac && !lactose && custom.isEmpty }

    static let glutenTerms = [
        "gluten", "wheat", "barley", "rye", "malt", "spelt", "farro", "semolina", "durum", "bulgur", "couscous",
        "seitan", "bread", "pasta", "noodles", "pizza", "bagel", "croissant", "cracker", "crackers", "flour tortilla",
        "breadcrumbs", "panko", "pretzel", "cake", "cookie", "muffin", "pancake", "waffle", "beer", "sandwich",
        "sub", "toast", "bun", "wrap", "biscuit", "pie", "dumpling", "ramen", "udon", "tempura", "breaded",
    ]
    static let lactoseTerms = [
        "lactose", "milk", "cream", "ice cream", "whey", "custard", "ricotta", "cottage cheese", "milkshake",
        "condensed milk", "evaporated milk", "milk chocolate",
    ]
    /// A food labeled with one of these is exempt from that category altogether.
    static let glutenFreeLabels = ["gluten free", "gluten-free", "wheat free", "wheat-free"]
    static let lactoseFreeLabels = ["lactose free", "lactose-free", "dairy free", "dairy-free", "vegan"]
    /// Safe look-alikes removed before matching, so "oat milk" and "buckwheat" do not match.
    static let glutenLookAlikes = ["buckwheat", "rice noodles", "corn tortilla", "rice cracker", "rice crackers"]
    static let lactoseLookAlikes = [
        "oat milk", "almond milk", "soy milk", "rice milk", "coconut milk", "coconut cream", "cashew milk", "pea milk",
    ]

    /// Short labels for prompts and flags, e.g. "gluten (celiac disease)".
    var labels: [String] {
        (celiac ? ["gluten (celiac disease)"] : []) + (lactose ? ["lactose"] : []) + custom
    }

    /// The labels of everything on the list that `entry` appears to contain.
    func matches(for entry: FoodEntry) -> [String] {
        let metadata = entry.productMetadata
        let texts = [entry.name] + entry.ingredients.map(\.name) + [metadata?.ingredientsText].compactMap { $0 }
        let allergens = (metadata?.allergens ?? []) + (metadata?.traces ?? [])
        return matches(texts: texts, allergens: allergens)
    }

    func matches(texts: [String], allergens: [String] = []) -> [String] {
        let allergenTexts = allergens.map { $0.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ") }
        func contains(_ terms: [String], in candidates: [String]) -> Bool {
            let table = [PurineReference.Food("avoid", terms, 0)]
            return candidates.contains { PurineReference.match($0, in: table) != nil }
        }
        func candidates(exempt labels: [String], lookAlikes: [String]) -> [String] {
            (texts.filter { text in !labels.contains { text.range(of: $0, options: [.caseInsensitive]) != nil } } + allergenTexts)
                .map { Self.removing(lookAlikes, from: $0) }
        }
        var found: [String] = []
        if celiac, contains(Self.glutenTerms, in: candidates(exempt: Self.glutenFreeLabels, lookAlikes: Self.glutenLookAlikes)) {
            found.append("gluten (celiac disease)")
        }
        if lactose, contains(Self.lactoseTerms, in: candidates(exempt: Self.lactoseFreeLabels, lookAlikes: Self.lactoseLookAlikes)) {
            found.append("lactose")
        }
        for term in custom where contains([term], in: texts + allergenTexts) { found.append(term) }
        return found
    }

    private static func removing(_ phrases: [String], from text: String) -> String {
        phrases.reduce(text) { $0.replacingOccurrences(of: $1, with: " ", options: [.caseInsensitive, .diacriticInsensitive]) }
    }
}
