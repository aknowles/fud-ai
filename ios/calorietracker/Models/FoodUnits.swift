import Foundation

/// The user's measurement system. US uses ounces, pounds, cups and fluid ounces for food;
/// metric uses grams, kilograms and milliliters. Defaults to the phone's region.
enum MeasurementSystem: String, CaseIterable, Identifiable {
    case us
    case metric

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: String(localized: "US (oz, lb, cups)")
        case .metric: String(localized: "Metric (g, kg, ml)")
        }
    }

    /// The phone's region; metric under the test runner, where upstream tests expect grams.
    static var regionDefault: MeasurementSystem {
        if SimulatorTestEnvironment.isRunningTests { return .metric }
        return Locale.current.measurementSystem == .us ? .us : .metric
    }
}

/// One unit dimension: follow the system, or always metric or always US.
enum UnitOverride: String, CaseIterable, Identifiable {
    case auto
    case metric
    case us

    var id: String { rawValue }
}

/// Which units food amounts use: the system, with optional overrides for weight and volume.
struct UnitConfig: Equatable {
    static let systemKey = "fork.units.system"
    static let foodWeightKey = "fork.units.foodWeight"
    static let foodVolumeKey = "fork.units.foodVolume"

    var system: MeasurementSystem
    var foodWeight: UnitOverride = .auto
    var foodVolume: UnitOverride = .auto

    static var current: UnitConfig { load(from: .standard) }

    static func load(from defaults: UserDefaults) -> UnitConfig {
        UnitConfig(
            system: defaults.string(forKey: systemKey).flatMap(MeasurementSystem.init) ?? .regionDefault,
            foodWeight: defaults.string(forKey: foodWeightKey).flatMap(UnitOverride.init) ?? .auto,
            foodVolume: defaults.string(forKey: foodVolumeKey).flatMap(UnitOverride.init) ?? .auto
        )
    }

    func resolved(_ override: UnitOverride) -> MeasurementSystem {
        switch override {
        case .auto: system
        case .metric: .metric
        case .us: .us
        }
    }

    var weightIsUS: Bool { resolved(foodWeight) == .us }
    var volumeIsUS: Bool { resolved(foodVolume) == .us }

    /// Switches the system and moves body weight, height and water to match. Each of those
    /// can still be changed on its own afterwards; food overrides are kept.
    static func apply(_ system: MeasurementSystem, to defaults: UserDefaults = .standard) {
        defaults.set(system.rawValue, forKey: systemKey)
        defaults.set(system == .us ? WeightUnit.lbs.rawValue : WeightUnit.kg.rawValue, forKey: WeightUnit.storageKey)
        defaults.set(system == .us ? HeightUnit.ftin.rawValue : HeightUnit.cm.rawValue, forKey: HeightUnit.storageKey)
        defaults.set(system == .us ? WaterUnit.fluidOunces.rawValue : WaterUnit.milliliters.rawValue, forKey: WaterSettings.unitKey)
    }
}

/// Food amounts in the units a person would use: "4.5 oz", "1 lb 4 oz", "250 g", "1.2 kg",
/// with portion pickers that offer the configured weight unit and convert metric or US volumes.
/// Amounts are always stored in grams.
enum FoodUnits {
    static let gramsPerOunce = 28.349523125
    static let gramsPerPound = 453.59237
    static let millilitersPerFluidOunce = 29.5735295625
    static let millilitersPerCup = 236.5882365

    static let ounce = ServingUnitOption(unit: "oz", gramsPerUnit: gramsPerOunce)

    /// The plain weight unit for portions: ounces in US, grams in metric.
    static func baseWeight(_ config: UnitConfig = .current) -> ServingUnitOption {
        config.weightIsUS ? ounce : .grams
    }

    static func isBaseWeight(_ option: ServingUnitOption) -> Bool {
        option.isGramUnit || option.normalizedUnit == "oz" || option.normalizedUnit == "ounce" || option.normalizedUnit == "ounces"
    }

    // MARK: - Text

    static func weightText(grams: Double, config: UnitConfig = .current) -> String {
        guard grams.isFinite, grams > 0 else { return config.weightIsUS ? "0 oz" : "0 g" }
        if config.weightIsUS {
            let ounces = grams / gramsPerOunce
            if ounces < 1 { return "\(trimmed(max(ounces, 0.1), places: 1)) oz" }
            if ounces < 16 { return "\(trimmed((ounces * 2).rounded() / 2, places: 1)) oz" }
            let pounds = ounces / 16
            if pounds >= 10 { return "\(trimmed(pounds, places: 1)) lb" }
            var whole = Int(pounds)
            var rest = Int((ounces - Double(whole) * 16).rounded())
            if rest == 16 { whole += 1; rest = 0 }
            return rest == 0 ? "\(whole) lb" : "\(whole) lb \(rest) oz"
        }
        if grams < 10 { return "\(trimmed(grams, places: 1)) g" }
        if grams < 1_000 { return "\(Int(grams.rounded())) g" }
        return "\(trimmed(grams / 1_000, places: 1)) kg"
    }

    /// The number for a weight text field, in ounces or grams.
    static func fieldText(grams: Double, config: UnitConfig = .current) -> String {
        guard config.weightIsUS else { return MacroValueFormatter.string(grams) }
        let ounces = grams / gramsPerOunce
        return trimmed(ounces, places: ounces < 1 ? 2 : 1)
    }

    /// Grams from a weight text field in ounces or grams.
    static func grams(fromField value: Double, config: UnitConfig = .current) -> Double {
        config.weightIsUS ? value * gramsPerOunce : value
    }

    static func fieldUnitLabel(_ config: UnitConfig = .current) -> String { config.weightIsUS ? "oz" : "g" }

    // MARK: - Portion pickers

    /// The configured weight unit first, then the food's own units, with metric volumes shown
    /// in fluid ounces and cups for US (and the reverse for metric), kilograms as pounds for US.
    static func pickerOptions(_ options: [ServingUnitOption], config: UnitConfig = .current) -> [ServingUnitOption] {
        let base = baseWeight(config)
        var seen: Set<String> = [base.id]
        var result = [base]
        func add(_ option: ServingUnitOption) {
            guard option.isValid, !isBaseWeight(option), seen.insert(option.id).inserted else { return }
            result.append(option)
        }
        for option in options where option.isValid {
            for converted in converted(option, config: config) { add(converted) }
        }
        return result
    }

    /// The picker unit that stands for a stored or suggested unit under the current config.
    static func mappedID(_ id: String, config: UnitConfig = .current) -> String {
        let unit = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch unit {
        case "g", "gram", "grams", "oz", "ounce", "ounces": return baseWeight(config).id
        case "ml", "milliliter", "milliliters", "l", "liter", "liters": return config.volumeIsUS ? "fl oz" : unit
        case "fl oz", "floz": return config.volumeIsUS ? "fl oz" : "ml"
        case "kg", "kilogram", "kilograms": return config.weightIsUS ? "lb" : "kg"
        case "lb", "lbs", "pound", "pounds": return config.weightIsUS ? "lb" : "kg"
        default: return unit
        }
    }

    /// A stored or AI-suggested quantity, when it still describes `totalGrams` in `option`.
    /// Units are mapped to the configured system first, so a "355" saved with ml must not be
    /// shown as 355 fl oz: the quantity counts only when quantity × unit size matches the total
    /// (within the 15% the AI's unit options are held to); otherwise nil, and callers derive it.
    static func storedQuantity(_ quantity: Double?, fits option: ServingUnitOption, totalGrams: Double) -> Double? {
        guard let quantity, quantity.isFinite, quantity > 0, option.gramsPerUnit > 0 else { return nil }
        guard totalGrams.isFinite, totalGrams > 0 else { return quantity }
        let represented = quantity * option.gramsPerUnit
        return abs(represented - totalGrams) <= max(1, totalGrams * 0.15) ? quantity : nil
    }

    private static func converted(_ option: ServingUnitOption, config: UnitConfig) -> [ServingUnitOption] {
        func scaled(_ unit: String, factor: Double) -> ServingUnitOption {
            ServingUnitOption(unit: unit, gramsPerUnit: option.gramsPerUnit * factor, quantity: option.quantity.map { $0 / factor })
        }
        switch option.normalizedUnit {
        case "ml", "milliliter", "milliliters":
            return config.volumeIsUS
                ? [scaled("fl oz", factor: millilitersPerFluidOunce), scaled("cup", factor: millilitersPerCup)]
                : [option]
        case "l", "liter", "liters":
            return config.volumeIsUS
                ? [scaled("fl oz", factor: millilitersPerFluidOunce / 1_000), scaled("cup", factor: millilitersPerCup / 1_000)]
                : [option]
        case "fl oz", "floz":
            return config.volumeIsUS ? [option] : [scaled("ml", factor: 1 / millilitersPerFluidOunce)]
        case "kg", "kilogram", "kilograms":
            return config.weightIsUS ? [scaled("lb", factor: gramsPerPound / option.gramsPerUnit)] : [option]
        case "lb", "lbs", "pound", "pounds":
            return config.weightIsUS ? [option] : [scaled("kg", factor: 1_000 / option.gramsPerUnit)]
        default:
            return [option]
        }
    }

    private static func trimmed(_ value: Double, places: Int) -> String {
        var text = String(format: "%.\(places)f", value)
        while text.contains(".") && text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}
