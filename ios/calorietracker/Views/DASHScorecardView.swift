import SwiftUI

/// DASH scorecard over the existing sodium, potassium, calcium and magnesium totals:
/// one day against the goals plus a seven-day rolling average, and a one-tap preset
/// that writes the DASH values into `OptionalNutrientGoals`. Stores nothing new.
struct DASHScorecardSection: View {
    var date: Date = .now

    @Environment(FoodStore.self) private var foodStore
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()

    @State private var health = HealthProfileStore.shared

    private var goals: OptionalNutrientGoals { OptionalNutrientGoals.decoded(from: goalsData) }

    var body: some View {
        if health.contains(.dash) { card }
    }

    @ViewBuilder
    private var card: some View {
        let scorecard = DASHScorecard(foodStore: foodStore, date: date, goals: goals)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("DASH Scorecard")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Text(String(localized: "Today \(scorecard.todayScore)/\(scorecard.lines.count) · 7-day \(scorecard.weekScore)/\(scorecard.lines.count)"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(scorecard.lines) { line in
                NutrientContributorsLink(metric: .nutrient(line.nutrient), date: date) {
                    DASHScorecardRow(line: line)
                }
            }

            Text(weekFootnote(for: scorecard))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)

            Divider()

            DASHPresetButtons()
        }
        .padding()
        .progressCardStyle()
    }

    private func weekFootnote(for scorecard: DASHScorecard) -> String {
        if scorecard.loggedDaysInWeek == 0 {
            return String(localized: "No food logged in the last 7 days.")
        }
        return String(localized: "7-day average over \(scorecard.loggedDaysInWeek) logged day(s). Sodium is a limit; potassium, calcium and magnesium are targets.")
    }
}

private struct DASHScorecardRow: View {
    let line: DASHScorecard.Line

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MacroProgressRow(
                label: line.nutrient.displayName,
                current: line.today,
                goal: line.goal,
                unit: line.nutrient.unit,
                color: barColor,
                gradientColors: barGradient,
                localizeLabel: false
            )
            HStack(spacing: 6) {
                Image(systemName: line.weekMeetsGoal ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(line.weekMeetsGoal ? Color.green : Color.secondary)
                Text(String(localized: "7-day avg \(MacroValueFormatter.string(line.weeklyAverage))\(line.nutrient.unit) · \(line.isLimit ? String(localized: "limit") : String(localized: "target")) \(line.goal)\(line.nutrient.unit)"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var barColor: Color {
        line.isLimit && !line.todayMeetsGoal ? .red : AppColors.calorie
    }

    private var barGradient: [Color] {
        line.isLimit && !line.todayMeetsGoal ? [Color.red.opacity(0.75), Color.red] : AppColors.calorieGradient
    }
}

/// One tap sets the four DASH goals. Shown in the scorecard and in Other Nutrients settings.
struct DASHPresetButtons: View {
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()

    private var goals: OptionalNutrientGoals { OptionalNutrientGoals.decoded(from: goalsData) }
    private var applied: DASHPreset.SodiumVariant? { DASHPreset.appliedVariant(in: goals) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(DASHPreset.SodiumVariant.allCases) { variant in
                Button {
                    goalsData = DASHPreset.applying(variant, to: goals).mergedWithDefaults().encodedData
                } label: {
                    HStack {
                        Image(systemName: applied == variant ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(applied == variant ? AppColors.calorie : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variant.displayName)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(detail(for: variant))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detail(for variant: DASHPreset.SodiumVariant) -> String {
        "Na \(variant.sodiumMilligrams) · K \(DASHPreset.potassiumMilligrams) · Ca \(DASHPreset.calciumMilligrams) · Mg \(DASHPreset.magnesiumMilligrams) mg"
    }
}
