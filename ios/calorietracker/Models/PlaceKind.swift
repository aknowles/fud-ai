import Foundation
import UIKit

/// A kind of food place a collection has, e.g. a coffee bar or a vending machine. Suggestions
/// and Coach assume what is typical there; each kind can have a typical menu for logging.
enum PlaceKind: String, CaseIterable, Identifiable {
    case coffeeBar, juiceBar, vendingMachine, pantry, cafeteria, saladBar, deli, pizza, bakery, fastFood, pub

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coffeeBar: String(localized: "Coffee bar")
        case .juiceBar: String(localized: "Juice & smoothie bar")
        case .vendingMachine: String(localized: "Vending machine")
        case .pantry: String(localized: "Snack pantry")
        case .cafeteria: String(localized: "Cafeteria or hot line")
        case .saladBar: String(localized: "Salad bar")
        case .deli: String(localized: "Sandwich or deli counter")
        case .pizza: String(localized: "Pizza place")
        case .bakery: String(localized: "Bakery")
        case .fastFood: String(localized: "Fast food")
        case .pub: String(localized: "Bar or pub")
        }
    }

    var systemImage: String {
        switch self {
        case .coffeeBar: "cup.and.saucer.fill"
        case .juiceBar: "takeoutbag.and.cup.and.straw.fill"
        case .vendingMachine: "cabinet.fill"
        case .pantry: "basket.fill"
        case .cafeteria: "fork.knife"
        case .saladBar: "leaf.fill"
        case .deli: "rectangle.stack.fill"
        case .pizza: "triangle.fill"
        case .bakery: "birthday.cake.fill"
        case .fastFood: "bag.fill"
        case .pub: "wineglass.fill"
        }
    }

    /// What is typical there, for prompts.
    var promptDescription: String {
        switch self {
        case .coffeeBar: "a coffee bar with a barista (lattes, cappuccinos, americanos, brewed coffee, cold brew, mochas, matcha and chai lattes, teas, hot chocolate; whole, 2%, skim, oat, almond or soy milk; optional syrup; often pastries)"
        case .juiceBar: "a juice and smoothie bar (fresh juices, smoothies, acai and smoothie bowls, protein add-ins)"
        case .vendingMachine: "a vending machine (packaged chips, candy, cookies, crackers, nuts, granola bars, sodas, juices, water)"
        case .pantry: "a workplace snack pantry (packaged snacks, fruit, nuts, bars, yogurt, drinks)"
        case .cafeteria: "a cafeteria hot line (a daily entree with sides, soups, a grill, sandwiches)"
        case .saladBar: "a salad bar (greens, vegetables, beans, eggs, cheese, proteins, dressings, by the bowl)"
        case .deli: "a sandwich and deli counter (made-to-order sandwiches, wraps, deli meats and cheeses, soups, sides)"
        case .pizza: "a pizza place (slices and pies with various toppings, garlic knots, salads, wings)"
        case .bakery: "a bakery (pastries, muffins, croissants, bagels, breads, cookies, coffee)"
        case .fastFood: "a fast-food restaurant (burgers, fries, chicken, wraps, salads, shakes, sodas)"
        case .pub: "a bar or pub (beer, wine, cocktails, pub food such as burgers, wings, fries)"
        }
    }

    /// Kinds where scanning what is actually stocked beats a generic list.
    var prefersScan: Bool { self == .vendingMachine || self == .pantry }
}

/// A kind as stored on a collection: a `PlaceKind` raw value, or the user's own words.
struct PlaceKindKey: Hashable, Identifiable {
    let raw: String
    var id: String { raw }
    var known: PlaceKind? { PlaceKind(rawValue: raw) }
    var displayName: String { known?.displayName ?? raw }
    var systemImage: String { known?.systemImage ?? "storefront.fill" }
    var promptDescription: String { known?.promptDescription ?? raw }
}

extension FoodCollection {
    /// The kinds of place here; an older coffee-bar switch counts as the coffee-bar kind.
    var placeKinds: [PlaceKindKey] {
        (kinds ?? (coffeeBar == true ? [PlaceKind.coffeeBar.rawValue] : [])).map(PlaceKindKey.init)
    }

    var hasCoffeeBar: Bool { placeKinds.contains { $0.known == .coffeeBar } }

    /// The saved typical menu for a kind, or empty.
    func typicalMenu(for kind: PlaceKindKey) -> [FoodEntry] {
        typicalMenus?[kind.raw] ?? []
    }
}

/// Writes a typical menu for a kind of place, in one AI call, in the collection-scan shape.
enum TypicalMenuService {
    static func menu(for kind: PlaceKindKey, healthLines: [String], now: Date = Date()) async throws -> [FoodEntry] {
        let text = try await GeminiService.callAI(prompt: prompt(for: kind, healthLines: healthLines), image: nil)
        return try CollectionScanService.parse(text, now: now)
    }

    static func prompt(for kind: PlaceKindKey, healthLines: [String]) -> String {
        ([
            "List the foods and drinks typically available at \(kind.promptDescription), as a menu the user can log from.",
            "Give about 12 common items, most popular first, each once, with nutrition for one typical serving as ordered (one slice, one sandwich, one 16 oz drink). Include a few lighter choices.",
        ] + healthLines + [
            "",
            "Answer with JSON only, in this shape: {\"foods\":[FOOD, ...]} where each FOOD is \(FoodSuggestionService.foodShape)",
            "- At most \(CollectionScanService.maxItems) foods.",
        ]).joined(separator: "\n")
    }
}
