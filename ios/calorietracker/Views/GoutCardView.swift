import SwiftUI

/// Day-view card for gout: purines against the daily limit, plus alcohol and added sugar,
/// the two other dietary triggers. All three are limit-style goals from `OptionalNutrientGoals`.
///
/// Purines and alcohol come from the AI estimate, a label, USDA (alcohol only) or the
/// built-in purine table, so the card says they are estimates.
struct GoutCardView: View {
    let date: Date

    @Environment(FoodStore.self) private var foodStore
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()
    @State private var health = HealthProfileStore.shared

    private struct Line: Identifiable {
        let nutrient: OptionalNutrient
        let value: Double
        let goal: Int

        var id: String { nutrient.rawValue }
        var isOver: Bool { goal > 0 && value > Double(goal) }
    }

    private static let nutrients: [OptionalNutrient] = [.purines, .alcohol, .addedSugar]

    private var lines: [Line] {
        let entries = foodStore.entries(for: date)
        let goals = OptionalNutrientGoals.decoded(from: goalsData)
        return Self.nutrients.map { nutrient in
            let value: Double
            switch nutrient {
            case .addedSugar: value = entries.reduce(0) { $0 + ($1.addedSugar ?? 0) }
            default: value = entries.reduce(0) { $0 + ($1.supplementalNutrients[nutrient.rawValue] ?? 0) }
            }
            return Line(nutrient: nutrient, value: value, goal: goals.goal(for: nutrient))
        }
    }

    var body: some View {
        if health.contains(.gout) { card }
    }

    @ViewBuilder
    private var card: some View {
        let rows = lines
        let withinLimit = rows.filter { !$0.isOver }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "allergens")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: AppColors.calorieGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Gout")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Text(String(localized: "\(withinLimit) of \(rows.count) within limit"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                MacroProgressRow(
                    label: row.nutrient.displayName,
                    current: row.value,
                    goal: row.goal,
                    unit: row.nutrient.unit,
                    color: row.isOver ? .red : AppColors.calorie,
                    gradientColors: row.isOver ? [Color.red.opacity(0.75), Color.red] : AppColors.calorieGradient,
                    localizeLabel: false
                )
            }

            Text("Purines and alcohol are estimates from AI analysis, labels or the built-in purine table.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .progressCardStyle()
    }
}
