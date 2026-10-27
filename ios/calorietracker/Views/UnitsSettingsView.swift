import SwiftUI

/// Settings → App Settings → Units: one measurement system for the whole app, with overrides.
struct UnitsSettingsView: View {
    @AppStorage(UnitConfig.systemKey) private var systemRaw = MeasurementSystem.regionDefault.rawValue
    @AppStorage(UnitConfig.foodWeightKey) private var foodWeightRaw = UnitOverride.auto.rawValue
    @AppStorage(UnitConfig.foodVolumeKey) private var foodVolumeRaw = UnitOverride.auto.rawValue
    @AppStorage(WeightUnit.storageKey) private var bodyWeightRaw = WeightUnit.lbs.rawValue
    @AppStorage(HeightUnit.storageKey) private var heightRaw = HeightUnit.ftin.rawValue
    @AppStorage(WaterSettings.unitKey) private var waterRaw = WaterUnit.defaultUnit.rawValue
    @AppStorage(EnergyUnit.storageKey) private var energyRaw = EnergyUnit.defaultUnit.rawValue

    private var system: MeasurementSystem { MeasurementSystem(rawValue: systemRaw) ?? .regionDefault }

    var body: some View {
        Form {
            Section {
                Picker("System", selection: Binding(
                    get: { system },
                    set: { UnitConfig.apply($0); systemRaw = $0.rawValue }
                )) {
                    ForEach(MeasurementSystem.allCases) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Changing the system also switches body weight, height and water below. Change any of them afterwards to override it.")
            }

            Section {
                Picker("Food weight", selection: $foodWeightRaw) {
                    Text(String(localized: "Automatic (\(system == .us ? "oz, lb" : "g, kg"))")).tag(UnitOverride.auto.rawValue)
                    Text("Grams and kilograms").tag(UnitOverride.metric.rawValue)
                    Text("Ounces and pounds").tag(UnitOverride.us.rawValue)
                }
                Picker("Food volume", selection: $foodVolumeRaw) {
                    Text(String(localized: "Automatic (\(system == .us ? "fl oz, cups" : "ml, L"))")).tag(UnitOverride.auto.rawValue)
                    Text("Milliliters and liters").tag(UnitOverride.metric.rawValue)
                    Text("Fluid ounces and cups").tag(UnitOverride.us.rawValue)
                }
            } header: {
                Text("Food")
            } footer: {
                Text("Portions keep the food's own units (slices, cups, pieces) and show the weight in these units. Nutrition stays in grams and milligrams, as on US labels.")
            }

            Section("Body and water") {
                Picker("Body weight", selection: $bodyWeightRaw) {
                    Text("Pounds").tag(WeightUnit.lbs.rawValue)
                    Text("Kilograms").tag(WeightUnit.kg.rawValue)
                }
                Picker("Height", selection: $heightRaw) {
                    Text("Feet and inches").tag(HeightUnit.ftin.rawValue)
                    Text("Centimeters").tag(HeightUnit.cm.rawValue)
                }
                Picker("Water", selection: $waterRaw) {
                    Text("Fluid ounces").tag(WaterUnit.fluidOunces.rawValue)
                    Text("Milliliters").tag(WaterUnit.milliliters.rawValue)
                }
                Picker("Energy", selection: $energyRaw) {
                    ForEach(EnergyUnit.allCases) { Text($0.rawValue == "kcal" ? "Calories (kcal)" : "Kilojoules (kJ)").tag($0.rawValue) }
                }
            }
        }
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }
}
