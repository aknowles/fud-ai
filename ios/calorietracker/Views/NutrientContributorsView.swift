import SwiftUI

/// A value whose day total can be broken down by food: calories, a macro or any tracked nutrient.
enum NutrientMetric: Hashable, Identifiable {
    case calories, protein, carbs, fat
    case nutrient(OptionalNutrient)

    var id: String {
        if case .nutrient(let nutrient) = self { return nutrient.rawValue }
        return String(describing: self)
    }

    var label: String {
        switch self {
        case .calories: String(localized: "Calories")
        case .protein: String(localized: "Protein")
        case .carbs: String(localized: "Carbs")
        case .fat: String(localized: "Fat")
        case .nutrient(let nutrient): nutrient.displayName
        }
    }

    /// The unit for non-calorie metrics; calories use the energy setting.
    var unit: String {
        switch self {
        case .calories: "kcal"
        case .protein, .carbs, .fat: "g"
        case .nutrient(let nutrient): nutrient.unit
        }
    }

    func amount(in entry: FoodEntry) -> Double? {
        switch self {
        case .calories: Double(entry.calories)
        case .protein: entry.protein
        case .carbs: entry.carbs
        case .fat: entry.fat
        case .nutrient(let nutrient): entry.amount(of: nutrient)
        }
    }

    /// Where the value came from when it is not from the food itself (AI estimate, label).
    func estimateNote(for entry: FoodEntry, amount: Double) -> String? {
        guard case .nutrient(let nutrient) = self else { return nil }
        let reference: Double? = switch nutrient {
        case .purines: PurineReference.estimateMilligrams(for: entry)
        case .oxalate: OxalateReference.estimateMilligrams(for: entry)
        default: nil
        }
        if let reference, abs(reference - amount) < 0.05 { return String(localized: "built-in table") }
        return nil
    }
}

extension NutrientMetric {
    /// The metric behind a home nutrient bar; only the macros have no `OptionalNutrient`.
    init(_ home: HomeTopNutrient) {
        switch home {
        case .protein: self = .protein
        case .carbs: self = .carbs
        case .fat: self = .fat
        default:
            guard let nutrient = home.optionalNutrient else { preconditionFailure("No metric for \(home)") }
            self = .nutrient(nutrient)
        }
    }
}

/// One contributor: a food and its share of the day's total.
struct NutrientContribution: Identifiable {
    let entry: FoodEntry
    let amount: Double
    let share: Double
    var id: UUID { entry.id }

    /// The day's foods with a value for `metric`, largest first.
    static func make(_ metric: NutrientMetric, entries: [FoodEntry]) -> [NutrientContribution] {
        let amounts = entries.compactMap { entry in metric.amount(in: entry).flatMap { $0 > 0 ? (entry, $0) : nil } }
        let total = amounts.reduce(0) { $0 + $1.1 }
        return amounts
            .sorted { $0.1 > $1.1 }
            .map { NutrientContribution(entry: $0.0, amount: $0.1, share: total > 0 ? $0.1 / total : 0) }
    }
}

/// Which foods made up a day's total for one metric, largest first; tap a food to edit it.
struct NutrientContributorsView: View {
    let metric: NutrientMetric
    let date: Date

    @Environment(FoodStore.self) private var foodStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit
    @State private var editing: FoodEntry?

    private var goal: Double? {
        switch metric {
        case .calories: UserProfile.load().map { Double($0.effectiveCalories) }
        case .protein: UserProfile.load().map { Double($0.effectiveProtein) }
        case .carbs: UserProfile.load().map { Double($0.effectiveCarbs) }
        case .fat: UserProfile.load().map { Double($0.effectiveFat) }
        case .nutrient(let nutrient): Double(OptionalNutrientGoals.decoded(from: goalsData).goal(for: nutrient))
        }
    }

    var body: some View {
        let entries = foodStore.entries(for: date)
        let contributions = NutrientContribution.make(metric, entries: entries)
        let total = contributions.reduce(0) { $0 + $1.amount }
        let missing = entries.count - contributions.count
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Total")
                            .font(.system(.headline, design: .rounded))
                        Spacer()
                        Text(goal.map { "\(text(total)) of \(text($0))" } ?? text(total))
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    if contributions.isEmpty {
                        Text("Nothing logged this day has a value for \(metric.label.lowercased()).")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(contributions) { item in
                        Button { editing = item.entry } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Largest first")
                } footer: {
                    if missing > 0 {
                        Text(String(localized: "\(missing) other foods have no value for this, so they are not counted. Tap a food to edit it."))
                    } else {
                        Text("Tap a food to edit it.")
                    }
                }
                .listRowBackground(AppColors.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle(metric.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { entry in
                EditFoodEntryView(entry: entry)
            }
        }
    }

    private func row(_ item: NutrientContribution) -> some View {
        HStack(spacing: 12) {
            Text(item.entry.emoji ?? "🍽️")
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.entry.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption(item))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                GeometryReader { geometry in
                    Capsule()
                        .fill(AppColors.calorie.opacity(0.7))
                        .frame(width: max(4, geometry.size.width * item.share))
                }
                .frame(height: 4)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(text(item.amount))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text("\(Int((item.share * 100).rounded()))%")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func caption(_ item: NutrientContribution) -> String {
        let source = metric.estimateNote(for: item.entry, amount: item.amount) ?? sourceName(item.entry.source)
        return [item.entry.timestamp.formatted(date: .omitted, time: .shortened), source].joined(separator: " · ")
    }

    private func sourceName(_ source: FoodSource) -> String {
        switch source {
        case .snapFood: String(localized: "photo estimate")
        case .nutritionLabel: String(localized: "label")
        case .barcode: String(localized: "barcode")
        case .textInput: String(localized: "text estimate")
        case .manual: String(localized: "entered by hand")
        }
    }

    private func text(_ value: Double) -> String {
        if case .calories = metric { return energyUnit.format(kcal: Int(value.rounded())) }
        let rounded = value >= 100 ? String(Int(value.rounded())) : MacroValueFormatter.string((value * 10).rounded() / 10)
        return "\(rounded) \(metric.unit)"
    }
}

/// Wraps a nutrient row so tapping it opens the foods behind the total.
struct NutrientContributorsLink<Label: View>: View {
    let metric: NutrientMetric
    let date: Date
    @ViewBuilder let label: () -> Label
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowing) {
            NutrientContributorsView(metric: metric, date: date)
        }
    }
}
