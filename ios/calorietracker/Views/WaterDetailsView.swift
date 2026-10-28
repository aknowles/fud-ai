import SwiftUI

/// What makes up a day's water: water logs and the drinks from the diary that count, with
/// the drinks that do not count and why.
struct WaterDetailsView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodStore.self) private var foodStore
    @Environment(WaterStore.self) private var waterStore
    @AppStorage(WaterSettings.dailyGoalKey) private var goal = WaterSettings.defaultDailyGoalMl
    @AppStorage(WaterSettings.unitKey) private var unitRaw = WaterUnit.defaultUnit.rawValue
    @AppStorage(Hydration.countDrinksKey) private var countDrinks = true

    private var unit: WaterUnit { WaterUnit(rawValue: unitRaw) ?? .defaultUnit }

    var body: some View {
        let water = waterStore.entries(on: date).sorted { $0.date < $1.date }
        let drinks = foodStore.entries(for: date)
            .map { (entry: $0, result: Hydration.classify($0)) }
            .filter { $0.result != .notADrink }
            .sorted { $0.entry.timestamp < $1.entry.timestamp }
        let total = waterStore.totalIncludingDrinks(on: date, foods: foodStore)
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Total").font(.system(.headline, design: .rounded))
                        Spacer()
                        Text("\(unit.formatted(milliliters: total)) of \(unit.formatted(milliliters: goal))")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    if water.isEmpty {
                        Text("No water logged.").foregroundStyle(.secondary)
                    }
                    ForEach(water) { entry in
                        row(String(localized: "Water"), time: entry.date, amount: unit.formatted(milliliters: entry.milliliters))
                    }
                } header: {
                    Text("Water")
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    if drinks.isEmpty {
                        Text("No drinks logged as food.").foregroundStyle(.secondary)
                    }
                    ForEach(drinks, id: \.entry.id) { drink in
                        row(drink.entry.name, time: drink.entry.timestamp, amount: amountText(drink.result))
                    }
                    CountDrinksTowardWaterToggle()
                } header: {
                    Text("Drinks from your diary")
                } footer: {
                    Text("Every non-alcoholic drink counts as fluid, including coffee, tea, milk, juice and sports drinks. Their sugar and caffeine still count toward those goals. Alcohol doesn't count.")
                }
                .listRowBackground(AppColors.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle("Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func amountText(_ result: Hydration.Result) -> String {
        switch result {
        case .counts(let milliliters):
            countDrinks ? unit.formatted(milliliters: milliliters) : String(localized: "Not counted")
        case .alcohol: String(localized: "Alcohol doesn't count")
        case .noServingSize: String(localized: "No serving size")
        case .notADrink: ""
        }
    }

    private func row(_ name: String, time: Date, amount: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(.body, design: .rounded))
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Wraps the water bar or row so tapping it opens `WaterDetailsView`.
struct WaterDetailsLink<Label: View>: View {
    let date: Date
    @ViewBuilder let label: () -> Label
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowing) {
            WaterDetailsView(date: date)
        }
    }
}
