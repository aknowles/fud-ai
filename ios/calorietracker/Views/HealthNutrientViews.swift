import SwiftUI

/// The nutrients the user's active health entries track (gout: purines, alcohol, added sugar;
/// DASH: sodium, potassium, calcium, magnesium), for one food entry.
enum HealthNutrientDisplay {
    static func nutrients(on date: Date, store: HealthProfileStore = .shared) -> [OptionalNutrient] {
        store.profile.effective(on: date).trackedNutrients
    }

    /// "12 mg", or "—" when the entry has no value (unknown is never shown as 0).
    static func valueText(_ nutrient: OptionalNutrient, in entry: FoodEntry) -> String {
        guard let value = entry.amount(of: nutrient) else { return "—" }
        return "\(MacroValueFormatter.string(value)) \(nutrient.unit)"
    }
}

/// One line under a diary row: "Purines 12 mg · Sodium 5 mg". Empty when no entry is active.
struct HealthNutrientLine: View {
    let entry: FoodEntry
    @State private var health = HealthProfileStore.shared

    var body: some View {
        let nutrients = HealthNutrientDisplay.nutrients(on: entry.timestamp, store: health)
        if !nutrients.isEmpty {
            Text(nutrients.map { "\($0.shortDisplayName) \(HealthNutrientDisplay.valueText($0, in: entry))" }
                .joined(separator: " · "))
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A section for the entry and review screens listing the tracked nutrients and which
/// health entry tracks each. Hidden when no entry is active.
struct HealthNutrientsSection: View {
    let entry: FoodEntry
    @State private var health = HealthProfileStore.shared

    var body: some View {
        let profile = health.profile.effective(on: entry.timestamp)
        let nutrients = profile.trackedNutrients
        if !nutrients.isEmpty {
            Section {
                ForEach(nutrients, id: \.self) { nutrient in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nutrient.displayName)
                                .foregroundStyle(.secondary)
                            Text(profile.rules.filter { $0.nutrient == nutrient }.map(\.source).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(HealthNutrientDisplay.valueText(nutrient, in: entry))
                            .fontWeight(.medium)
                    }
                }
            } header: {
                Text("Health Profile")
            } footer: {
                Text("Estimates for this entry. — means no value was found.")
            }
        }
    }
}
