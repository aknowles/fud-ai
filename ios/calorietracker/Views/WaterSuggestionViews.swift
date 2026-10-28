import SwiftUI

/// Home card suggesting water tracking for gout or kidney stones; never turns it on by itself.
struct WaterSuggestionCardView: View {
    @State private var health = HealthProfileStore.shared
    @AppStorage(WaterSettings.enabledKey) private var waterOn = false
    @AppStorage(WaterSuggestion.dismissedKey) private var dismissed = false
    @AppStorage(WaterSettings.unitKey) private var unitRaw = WaterUnit.defaultUnit.rawValue

    var body: some View {
        if !waterOn, !dismissed, WaterSuggestion.applies(to: health.profile) {
            let unit = WaterUnit(rawValue: unitRaw) ?? .defaultUnit
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.calorie)
                    Text("Track water?")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                }
                Text("Drinking plenty helps clear uric acid and prevent kidney stones; about \(unit.formatted(milliliters: WaterSuggestion.suggestedGoalMl)) a day is common advice unless your doctor limits fluids. Coffee, tea, milk and other drinks you log count too.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Track water") { withAnimation { WaterSuggestion.accept() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.calorie)
                    Button("Not now") { withAnimation { dismissed = true } }
                        .buttonStyle(.bordered)
                        .tint(AppColors.calorie)
                }
            }
            .padding()
            .progressCardStyle()
        }
    }
}

/// Settings row under Water Tracking: count unsweetened drinks from the diary toward water.
struct CountDrinksTowardWaterToggle: View {
    @AppStorage(Hydration.countDrinksKey) private var countDrinks = true

    var body: some View {
        Toggle(isOn: $countDrinks) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Count drinks toward water")
                Text("Coffee, tea, milk, juice and sports drinks you log as food; not alcohol")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(AppColors.calorie)
    }
}
