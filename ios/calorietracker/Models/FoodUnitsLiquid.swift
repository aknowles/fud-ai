import Foundation

/// Liquids in volume: a 591 g bottle of Vitaminwater reads "20 fl oz" (or "591 ml"), not
/// "1 lb 5 oz". A food is a liquid when its unit is a volume or its name is a drink (the same
/// words that count drinks toward water). Amounts stay stored in grams, at 1 g ≈ 1 ml.
extension FoodUnits {
    static let volumeUnitNames: Set<String> = [
        "ml", "milliliter", "milliliters", "millilitre", "millilitres", "l", "liter", "liters", "litre", "litres",
        "fl oz", "floz", "fluid ounce", "fluid ounces",
    ]

    static func isVolume(_ unit: String?) -> Bool {
        guard let unit else { return false }
        return volumeUnitNames.contains(unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// A liquid by name or unit alone, for places without the whole entry.
    static func isLiquid(name: String, unit: String? = nil, options: [ServingUnitOption] = []) -> Bool {
        isVolume(unit) || options.contains { isVolume($0.unit) } || Hydration.isDrink(name: name)
    }

    /// A logged food is a liquid when it is a drink (name, brand or beverage product), or its
    /// units or package size are volumes ("591 ml", "20 fl oz").
    static func isLiquid(_ entry: FoodEntry) -> Bool {
        if Hydration.classify(entry) != .notADrink { return true }
        if isLiquid(name: entry.name, unit: entry.selectedServingUnit, options: entry.servingUnitOptions) { return true }
        guard let package = entry.productMetadata?.packageQuantity?.lowercased() else { return false }
        return package.range(of: #"\d\s*(ml|cl|l|fl\.?\s?oz)\b"#, options: .regularExpression) != nil
    }

    /// Volume for a liquid entry, weight otherwise.
    static func amountText(grams: Double, entry: FoodEntry, config: UnitConfig = .current) -> String {
        isLiquid(entry) ? volumeText(milliliters: grams, config: config) : weightText(grams: grams, config: config)
    }

    /// "8 fl oz", "20 fl oz", "1.5 gal" in US; "250 ml", "1.2 L" in metric.
    static func volumeText(milliliters: Double, config: UnitConfig = .current) -> String {
        guard milliliters.isFinite, milliliters > 0 else { return config.volumeIsUS ? "0 fl oz" : "0 ml" }
        if config.volumeIsUS {
            let ounces = milliliters / millilitersPerFluidOunce
            if ounces >= 128 { return "\(trimmedNumber(ounces / 128, places: 1)) gal" }
            if ounces < 1 { return "\(trimmedNumber(max(ounces, 0.1), places: 1)) fl oz" }
            if ounces < 10 { return "\(trimmedNumber((ounces * 2).rounded() / 2, places: 1)) fl oz" }
            return "\(Int(ounces.rounded())) fl oz"
        }
        if milliliters < 1_000 { return "\(Int(milliliters.rounded())) ml" }
        return "\(trimmedNumber(milliliters / 1_000, places: 1)) L"
    }

    /// Volume for a liquid, weight otherwise.
    static func amountText(grams: Double, name: String, unit: String? = nil, config: UnitConfig = .current) -> String {
        isLiquid(name: name, unit: unit) ? volumeText(milliliters: grams, config: config) : weightText(grams: grams, config: config)
    }

    /// For a liquid, volume units lead the portion picker (fl oz and cups in US, ml in metric),
    /// then the rest in the usual order; other foods are unchanged.
    static func pickerOptions(_ options: [ServingUnitOption], liquid: Bool, config: UnitConfig = .current) -> [ServingUnitOption] {
        let standard = pickerOptions(options, config: config)
        guard liquid else { return standard }
        let volumeIDs: Set<String> = ["fl oz", "cup", "ml", "l"]
        return standard.filter { volumeIDs.contains($0.id) } + standard.filter { !volumeIDs.contains($0.id) }
    }

    private static func trimmedNumber(_ value: Double, places: Int) -> String {
        var text = String(format: "%.\(places)f", value)
        while text.contains(".") && text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}

extension Hydration {
    /// True for a drink by name, alcoholic or not.
    static func isDrink(name: String) -> Bool {
        guard !matches(name, notDrinkTerms) else { return false }
        return nameLooksLikeDrink(name) || (matches(name, alcoholTerms))
    }
}
