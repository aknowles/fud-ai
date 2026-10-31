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
}
