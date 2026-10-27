import SwiftUI

/// On the Calories screen: how maintenance, goal, eaten, left, burned and deficit relate,
/// with this day's numbers.
struct CalorieBreakdownSection: View {
    let date: Date

    @Environment(FoodStore.self) private var foodStore
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit
    @State private var burned: Int?

    @AppStorage(ActivityGoal.modeKey) private var modeRaw = ActivityGoalMode.fixed.rawValue
    @AppStorage(ActivityGoal.shareKey) private var share = ActivityGoal.defaultShare
    @State private var activity = ActivityGoalStore.shared

    private var mode: ActivityGoalMode { ActivityGoalMode(rawValue: modeRaw) ?? .fixed }

    var body: some View {
        if let profile = UserProfile.load() {
            let active = activity.active(on: date)
            let breakdown = CalorieBreakdown.make(profile: profile, eaten: foodStore.calories(for: date), burned: burned,
                                                  active: active, activityBonus: activity.bonus(on: date, profile: profile))
            Section {
                row("Maintenance (estimated)", breakdown.maintenance,
                    detail: String(localized: "Resting \(number(breakdown.restingCalories)) × \(breakdown.activityName.lowercased()) \(breakdown.activityMultiplier.formatted(.number.precision(.fractionLength(0...3))))"))
                row(breakdown.isCustomGoal ? "Your custom goal" : "Goal adjustment", breakdown.adjustment, signed: true,
                    detail: breakdown.adjustment < 0 ? String(localized: "The planned deficit, for steady weight loss")
                        : breakdown.adjustment > 0 ? String(localized: "The planned surplus, for gaining")
                        : String(localized: "Eating at maintenance"))
                row("Daily goal", breakdown.goal, bold: breakdown.activityBonus == 0,
                    detail: String(localized: "Calories to eat, not net: your activity level already covers usual exercise."))
                if breakdown.activityBonus != 0 {
                    row(breakdown.activityBonus > 0 ? "Activity added" : "Not yet earned", breakdown.activityBonus, signed: true,
                        detail: mode == .followHealth
                            ? String(localized: "Sedentary base plus \(Int(share * 100))% of the \(number(breakdown.active ?? 0)) Apple Health recorded as active")
                            : String(localized: "\(Int(share * 100))% of the active energy beyond the \(number(ActivityGoal.assumedActive(profile: profile))) your activity level assumes"))
                    row("Today's goal", breakdown.goalToday, bold: true)
                }
                row("Eaten", breakdown.eaten)
                row(breakdown.left >= 0 ? "Left" : "Over", abs(breakdown.left), bold: true,
                    detail: String(localized: "Today's goal minus eaten."))
            } header: {
                Text("How your goal works")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                if let burned = breakdown.burned, let balance = breakdown.balance {
                    row("Burned so far", burned, detail: String(localized: "From Apple Health: resting plus active energy up to now"))
                    if let active {
                        row("Active so far", active, detail: String(localized: "Exercise and movement only"))
                    }
                    row(balance >= 0 ? "Deficit" : "Surplus", abs(balance), bold: true,
                        detail: String(localized: "Burned minus eaten. Grows through the day as you burn more; the end-of-day number is the one that counts."))
                    if breakdown.left < 0, balance > 0 {
                        Text("Over your goal but still in deficit: you ate more than planned, but less than you burned.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(healthKitEnabled
                         ? "Apple Health has no energy for this day yet."
                         : "Connect Apple Health to see calories burned and your real deficit.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Burn and deficit")
            } footer: {
                Text("Eat to your goal and burn about your maintenance, and you end the day near the planned deficit.")
            }
            .listRowBackground(AppColors.appCard)
            .task(id: "\(date.timeIntervalSince1970)-\(healthKitEnabled)") { await loadBurn(profile: profile) }

            Section {
                Picker("Calorie goal", selection: $modeRaw) {
                    ForEach(ActivityGoalMode.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                if mode != .fixed {
                    Picker("Count", selection: $share) {
                        ForEach(ActivityGoal.shareChoices, id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Exercise and your goal")
            } footer: {
                Text(mode.explanation + (mode == .fixed ? "" : " " + String(localized: "Watches often overestimate active calories, so counting part of them (50–75%) is a common hedge."))
                     + (healthKitEnabled ? "" : " " + String(localized: "Needs Apple Health.")))
            }
            .listRowBackground(AppColors.appCard)
            .onChange(of: modeRaw) { _, _ in activity.settingsChanged() }
            .onChange(of: share) { _, _ in activity.settingsChanged() }
        }
    }

    private func loadBurn(profile: UserProfile) async {
        guard healthKitEnabled, let energy = await healthKitManager.readEnergyForDay(date) else {
            burned = nil
            return
        }
        activity.record(activeCalories: energy.activeCalories, on: date)
        burned = DailySummaryPolicy.resolveBurnedCalories(
            measuredTotalCalories: energy.totalCalories,
            externalActiveCalories: energy.activeCalories,
            profileBmrCalories: Int(profile.bmr.rounded())
        )
    }

    private func number(_ kcal: Int) -> String {
        "\(energyUnit.number(kcal: kcal)) \(energyUnit.symbol)"
    }

    private func row(_ title: LocalizedStringKey, _ kcal: Int, signed: Bool = false, bold: Bool = false, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: bold ? .semibold : .regular))
                Spacer()
                Text((signed && kcal > 0 ? "+" : signed && kcal < 0 ? "−" : "") + number(abs(kcal)))
                    .font(.system(.body, design: .rounded, weight: bold ? .semibold : .regular))
                    .monospacedDigit()
            }
            if let detail {
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
