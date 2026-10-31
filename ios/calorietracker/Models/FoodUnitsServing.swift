import Foundation

/// Serving amounts that stay exact through unit switches, ingredient edits and the diary.
extension FoodUnits {
    /// The picker option a stored or suggested unit stands for under `config`.
    static func option(matching unit: String, in options: [ServingUnitOption], config: UnitConfig = .current) -> ServingUnitOption {
        let mapped = mappedID(unit, config: config)
        return pickerOptions(options, config: config).first { $0.id == mapped } ?? baseWeight(config)
    }

    /// Diary text for a logged amount of known weight: "0.5 bowls (~6 oz)", "12 fl oz", "12 oz".
    /// The plain weight unit is not paired with itself, and a stored count that no longer fits
    /// the unit it maps to (355 saved with ml, shown in fl oz) is worked out from the weight.
    static func loggedServingText(grams: Double, entry: FoodEntry, config: UnitConfig = .current) -> String {
        let amount = amountText(grams: grams, entry: entry, config: config)
        guard let unit = entry.selectedServingUnit else { return amount }
        let option = option(matching: unit, in: entry.servingUnitOptions, config: config)
        guard !isBaseWeight(option), option.gramsPerUnit > 0 else { return amount }
        let quantity = storedQuantity(entry.selectedServingQuantity, fits: option, totalGrams: grams)
            ?? grams / option.gramsPerUnit
        let label = "\(ServingUnitEditor.formatQuantity(quantity)) \(option.displayUnit(for: quantity))"
        let isMeasure = isVolume(option.unit) || ["lb", "kg"].contains(option.id)
        return isMeasure ? label : "\(label) (~\(amount))"
    }

    /// Grams for a quantity typed or set in `option`. When the text is just the current amount
    /// as the field shows it (after a unit switch or a finished edit), the current grams stay:
    /// turning the rounded "12.3" oz back into 348.7 g would shift every number a little.
    static func grams(forQuantityText text: String, option: ServingUnitOption, currentGrams: Double) -> Double? {
        guard let quantity = ServingAmountExpression.evaluate(text), quantity > 0 else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if option.gramsPerUnit > 0, currentGrams.isFinite, currentGrams > 0,
           ServingUnitEditor.formatQuantity(currentGrams / option.gramsPerUnit) == trimmed {
            return currentGrams
        }
        return quantity * option.gramsPerUnit
    }

    /// Grams from a weight field that opened at `original`: unchanged text keeps the exact
    /// original, so saving an ingredient in ounces does not round its weight.
    static func grams(fromField value: Double, text: String, original: Double, config: UnitConfig = .current) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == fieldText(grams: original, config: config) ? original : grams(fromField: value, config: config)
    }
}
