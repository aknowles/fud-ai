import Foundation

extension OptionalNutrient {
    /// Fixed English name for AI prompts, so advice does not depend on the app language.
    var promptName: String {
        switch self {
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .addedSugar: "Added sugar"
        case .saturatedFat: "Saturated fat"
        case .cholesterol: "Cholesterol"
        case .caffeine: "Caffeine"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .transFat: "Trans fat"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .magnesium: "Magnesium"
        case .zinc: "Zinc"
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminB12: "Vitamin B12"
        case .vitaminE: "Vitamin E"
        case .vitaminK: "Vitamin K"
        case .folate: "Folate"
        case .omega3: "Omega-3"
        case .creatine: "Creatine"
        case .betaAlanine: "Beta-alanine"
        case .lCitrulline: "L-citrulline"
        case .lCarnitine: "L-carnitine"
        case .lArginine: "L-arginine"
        case .taurine: "Taurine"
        case .betaine: "Betaine"
        case .hmb: "HMB"
        case .purines: "Purines"
        case .alcohol: "Alcohol"
        case .phosphorus: "Phosphorus"
        case .oxalate: "Oxalate"
        case .tyramine: "Tyramine"
        }
    }
}

extension FoodEntry {
    /// This entry's amount of `nutrient` in the nutrient's own unit, or nil when unknown.
    func amount(of nutrient: OptionalNutrient) -> Double? {
        switch nutrient {
        case .fiber: fiber
        case .sugar: sugar
        case .addedSugar: addedSugar
        case .saturatedFat: saturatedFat
        case .cholesterol: cholesterol
        case .caffeine: caffeine
        case .sodium: sodium
        case .potassium: potassium
        case .transFat: transFat
        case .calcium: calcium
        case .iron: iron
        case .magnesium: magnesium
        case .zinc: zinc
        case .vitaminA: vitaminA
        case .vitaminC: vitaminC
        case .vitaminD: vitaminD
        case .vitaminB12: vitaminB12
        case .vitaminE: vitaminE
        case .vitaminK: vitaminK
        case .folate: folate
        case .omega3: omega3
        case .creatine, .betaAlanine, .lCitrulline, .lCarnitine, .lArginine, .taurine, .betaine, .hmb,
             .purines, .alcohol, .phosphorus, .oxalate, .tyramine:
            supplementalNutrients[nutrient.rawValue]
        }
    }
}

extension Array where Element == FoodEntry {
    /// The summed amount of `nutrient`, counting unknown values as zero.
    func total(of nutrient: OptionalNutrient) -> Double {
        reduce(0) { $0 + ($1.amount(of: nutrient) ?? 0) }
    }
}
