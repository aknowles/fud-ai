import Foundation

/// The standard drinks of a coffee bar, built from a reference table instead of the AI, so a
/// barista drink logs in a couple of taps with the same numbers every time. Values are typical
/// café recipes; brands vary.
enum CoffeeDrink: String, CaseIterable, Codable, Identifiable {
    case latte, cappuccino, flatWhite, americano, brewedCoffee, coldBrew, mocha, matchaLatte, chaiLatte, blackTea, greenTea, herbalTea, hotChocolate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .latte: String(localized: "Latte")
        case .cappuccino: String(localized: "Cappuccino")
        case .flatWhite: String(localized: "Flat white")
        case .americano: String(localized: "Americano")
        case .brewedCoffee: String(localized: "Brewed coffee")
        case .coldBrew: String(localized: "Cold brew")
        case .mocha: String(localized: "Mocha")
        case .matchaLatte: String(localized: "Matcha latte")
        case .chaiLatte: String(localized: "Chai latte")
        case .blackTea: String(localized: "Black tea")
        case .greenTea: String(localized: "Green tea")
        case .herbalTea: String(localized: "Herbal tea")
        case .hotChocolate: String(localized: "Hot chocolate")
        }
    }

    var emoji: String {
        switch self {
        case .latte, .cappuccino, .flatWhite, .mocha: "☕️"
        case .americano, .brewedCoffee, .coldBrew: "☕️"
        case .matchaLatte, .greenTea: "🍵"
        case .chaiLatte, .blackTea, .herbalTea: "🫖"
        case .hotChocolate: "🍫"
        }
    }

    /// Fluid ounces of milk in a medium (16 oz) drink.
    var mediumMilkOunces: Double {
        switch self {
        case .latte, .mocha: 12
        case .matchaLatte: 12
        case .cappuccino: 8
        case .flatWhite: 10
        case .chaiLatte: 8
        case .hotChocolate: 14
        case .americano, .brewedCoffee, .coldBrew, .blackTea, .greenTea, .herbalTea: 0
        }
    }

    /// Takes milk by default; the others offer it as a splash.
    var isMilkDrink: Bool { mediumMilkOunces > 0 }

    /// Espresso shots by size; zero for drinks without espresso.
    func shots(_ size: CoffeeSize, iced: Bool) -> Int {
        switch self {
        case .latte, .cappuccino, .americano, .mocha:
            switch size {
            case .small: 1
            case .medium: 2
            case .large: iced || self == .americano ? 3 : 2
            }
        case .flatWhite: size == .small ? 2 : 3
        default: 0
        }
    }

    /// What the drink adds besides milk, espresso and syrup, for a medium.
    var mediumBase: CoffeeNutrition {
        switch self {
        case .brewedCoffee: CoffeeNutrition(calories: 5, potassium: 230, caffeine: 310)
        case .coldBrew: CoffeeNutrition(calories: 5, potassium: 200, caffeine: 205)
        case .mocha: CoffeeNutrition(calories: 100, carbs: 24, fat: 3, saturatedFat: 2, sugar: 20, addedSugar: 20, sodium: 20, caffeine: 25)
        // Café matcha powder is usually sweetened.
        case .matchaLatte: CoffeeNutrition(calories: 90, protein: 1, carbs: 22, sugar: 20, addedSugar: 20, caffeine: 80)
        case .chaiLatte: CoffeeNutrition(calories: 120, carbs: 25, sugar: 25, addedSugar: 25, sodium: 40, caffeine: 95)
        case .blackTea: CoffeeNutrition(calories: 2, potassium: 90, caffeine: 50)
        case .greenTea: CoffeeNutrition(calories: 2, potassium: 50, caffeine: 30)
        case .herbalTea: CoffeeNutrition(calories: 2)
        case .hotChocolate: CoffeeNutrition(calories: 150, protein: 2, carbs: 30, fat: 4, saturatedFat: 2.5, sugar: 25, addedSugar: 25, sodium: 60, caffeine: 25)
        case .latte, .cappuccino, .flatWhite, .americano: CoffeeNutrition()
        }
    }
}

enum CoffeeSize: String, CaseIterable, Codable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: String(localized: "Small (12 oz)")
        case .medium: String(localized: "Medium (16 oz)")
        case .large: String(localized: "Large (20 oz)")
        }
    }

    var shortName: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }

    var factor: Double {
        switch self {
        case .small: 0.75
        case .medium: 1
        case .large: 1.25
        }
    }

    var fluidOunces: Double { 16 * factor }
}

enum CoffeeMilk: String, CaseIterable, Codable, Identifiable {
    case none, whole, twoPercent, skim, oat, almond, soy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: String(localized: "No milk")
        case .whole: String(localized: "Whole milk")
        case .twoPercent: String(localized: "2% milk")
        case .skim: String(localized: "Skim milk")
        case .oat: String(localized: "Oat milk")
        case .almond: String(localized: "Almond milk")
        case .soy: String(localized: "Soy milk")
        }
    }

    /// Short name for the drink's title, e.g. "Oat".
    var shortName: String? {
        switch self {
        case .none, .whole: nil
        case .twoPercent: "2%"
        case .skim: String(localized: "Skim")
        case .oat: String(localized: "Oat")
        case .almond: String(localized: "Almond")
        case .soy: String(localized: "Soy")
        }
    }

    /// Per fluid ounce (about 30 ml); barista versions of plant milks.
    var perOunce: CoffeeNutrition {
        switch self {
        case .none: CoffeeNutrition()
        case .whole: CoffeeNutrition(calories: 18.6, protein: 1, carbs: 1.5, fat: 1, saturatedFat: 0.57, sugar: 1.5, sodium: 13, potassium: 41, calcium: 34)
        case .twoPercent: CoffeeNutrition(calories: 15.3, protein: 1, carbs: 1.5, fat: 0.6, saturatedFat: 0.38, sugar: 1.5, sodium: 13, potassium: 42, calcium: 35)
        case .skim: CoffeeNutrition(calories: 10.4, protein: 1, carbs: 1.5, fat: 0.03, saturatedFat: 0.02, sugar: 1.5, sodium: 13, potassium: 44, calcium: 37)
        case .oat: CoffeeNutrition(calories: 15, protein: 0.4, carbs: 2, fat: 0.7, saturatedFat: 0.07, sugar: 0.9, addedSugar: 0.9, sodium: 13, potassium: 48, calcium: 43)
        case .almond: CoffeeNutrition(calories: 4, protein: 0.13, carbs: 0.13, fat: 0.31, sodium: 21, potassium: 21, calcium: 56)
        case .soy: CoffeeNutrition(calories: 13, protein: 0.9, carbs: 1.3, fat: 0.5, saturatedFat: 0.06, sugar: 1, addedSugar: 0.8, sodium: 12, potassium: 37, calcium: 37)
        }
    }
}

/// Amounts for part of a drink, added up into a food entry.
struct CoffeeNutrition: Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var saturatedFat: Double = 0
    var sugar: Double = 0
    var addedSugar: Double = 0
    var sodium: Double = 0
    var potassium: Double = 0
    var calcium: Double = 0
    var caffeine: Double = 0

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein, carbs: lhs.carbs + rhs.carbs,
             fat: lhs.fat + rhs.fat, saturatedFat: lhs.saturatedFat + rhs.saturatedFat, sugar: lhs.sugar + rhs.sugar,
             addedSugar: lhs.addedSugar + rhs.addedSugar, sodium: lhs.sodium + rhs.sodium,
             potassium: lhs.potassium + rhs.potassium, calcium: lhs.calcium + rhs.calcium, caffeine: lhs.caffeine + rhs.caffeine)
    }

    static func * (lhs: Self, factor: Double) -> Self {
        Self(calories: lhs.calories * factor, protein: lhs.protein * factor, carbs: lhs.carbs * factor, fat: lhs.fat * factor,
             saturatedFat: lhs.saturatedFat * factor, sugar: lhs.sugar * factor, addedSugar: lhs.addedSugar * factor,
             sodium: lhs.sodium * factor, potassium: lhs.potassium * factor, calcium: lhs.calcium * factor,
             caffeine: lhs.caffeine * factor)
    }

    /// One espresso shot.
    static let espressoShot = CoffeeNutrition(calories: 3, sodium: 4, potassium: 34, caffeine: 75)
    /// One pump of flavored syrup.
    static let syrupPump = CoffeeNutrition(calories: 20, carbs: 5, sugar: 5, addedSugar: 5)
}

/// One coffee-bar order: drink, size, milk, iced or hot, syrup pumps.
struct CoffeeOrder: Codable, Equatable {
    var drink: CoffeeDrink = .latte
    var size: CoffeeSize = .medium
    var milk: CoffeeMilk = .whole
    var iced = false
    var syrupPumps = 0

    /// Splash of milk in a black drink, in ounces.
    static let splashOunces = 1.0

    var milkOunces: Double {
        guard milk != .none else { return 0 }
        let ounces = drink.isMilkDrink ? drink.mediumMilkOunces * size.factor : Self.splashOunces
        // Ice takes up some of the cup.
        return iced && drink.isMilkDrink ? ounces * 0.75 : ounces
    }

    var nutrition: CoffeeNutrition {
        drink.mediumBase * size.factor
            + milk.perOunce * milkOunces
            + CoffeeNutrition.espressoShot * Double(drink.shots(size, iced: iced))
            + CoffeeNutrition.syrupPump * Double(syrupPumps)
    }

    /// "Iced oat matcha latte", "Americano with a splash of almond milk".
    var name: String {
        var words: [String] = []
        if iced { words.append(String(localized: "Iced")) }
        if drink.isMilkDrink, let milkName = milk.shortName { words.append(milkName) }
        words.append(drink.displayName)
        // Sentence case: only the first word keeps its capital.
        var name = words.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }.joined(separator: " ")
        if !drink.isMilkDrink, milk != .none {
            name += " " + String(localized: "with a splash of \(milk.displayName.lowercased())")
        }
        if syrupPumps > 0 {
            name += syrupPumps == 1 ? String(localized: ", 1 pump syrup") : String(localized: ", \(syrupPumps) pumps syrup")
        }
        return name
    }

    func entry(at date: Date = Date(), mealType: MealType = .currentMeal) -> FoodEntry {
        let n = nutrition
        let grams = (size.fluidOunces * 29.57).rounded()
        func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
        return FoodEntry(
            name: "\(name) (\(size.shortName.lowercased()))",
            calories: Int(n.calories.rounded()),
            protein: round1(n.protein), carbs: round1(n.carbs), fat: round1(n.fat),
            timestamp: date, emoji: drink.emoji, source: .manual, mealType: mealType,
            sugar: round1(n.sugar), addedSugar: round1(n.addedSugar), saturatedFat: round1(n.saturatedFat),
            caffeine: n.caffeine.rounded(),
            // Coffee, tea and milk are low in purines.
            supplementalNutrients: [OptionalNutrient.purines.rawValue: 0],
            sodium: n.sodium.rounded(), potassium: n.potassium.rounded(), calcium: n.calcium.rounded(),
            servingSizeGrams: grams,
            servingUnitOptions: [ServingUnitOption(unit: "drink", gramsPerUnit: grams)],
            selectedServingUnit: "drink",
            selectedServingQuantity: 1
        )
    }
}

/// The user's usual coffee-bar order, offered first.
enum CoffeeUsual {
    static let storageKey = "fork.coffee.usual"

    static func load(_ defaults: UserDefaults = .standard) -> CoffeeOrder? {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(CoffeeOrder.self, from: $0) }
    }

    static func save(_ order: CoffeeOrder, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(order) { defaults.set(data, forKey: storageKey) }
    }
}

extension FoodCollection {
    /// The usual order (or a latte), then a few common drinks with the usual milk, for picking
    /// from a coffee bar without building a drink.
    static func coffeeStarters(usual: CoffeeOrder? = CoffeeUsual.load(), at date: Date = Date()) -> [FoodEntry] {
        let first = usual ?? CoffeeOrder()
        let milk = first.milk == .none ? CoffeeMilk.whole : first.milk
        let others = [CoffeeDrink.americano, .latte, .matchaLatte, .chaiLatte, .greenTea]
            .filter { $0 != first.drink }
            .map { CoffeeOrder(drink: $0, size: first.size, milk: $0.isMilkDrink ? milk : .none) }
        return ([first] + others).map { $0.entry(at: date) }
    }

    /// Items plus coffee-bar drinks when there is one.
    var onHandEntries: [FoodEntry] {
        items + (hasCoffeeBar ? Self.coffeeStarters() : [])
    }
}
