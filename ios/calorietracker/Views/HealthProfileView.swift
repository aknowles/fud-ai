import SwiftUI

/// Settings → Goals → Other Nutrients → Health Profile: turn conditions on or off, see
/// the goals each one uses and any conflicts between them.
struct HealthProfileView: View {
    @State private var store = HealthProfileStore.shared
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()

    private var goals: OptionalNutrientGoals { OptionalNutrientGoals.decoded(from: goalsData) }

    var body: some View {
        List {
            Section {
                ForEach(HealthEntryKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { store.contains(kind) },
                            set: { active in withAnimation { store.set(kind, active: active) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.displayName)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                Text(kind.summary)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(AppColors.calorie)

                        if store.contains(kind) {
                            Text(goalSummary(for: kind))
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(AppColors.calorie)
                            if let note = kind.setupNote {
                                Label(note, systemImage: "stethoscope")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if kind == .dash {
                                DASHPresetButtons()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Conditions")
            } footer: {
                Text("Change the numbers under Other Nutrients. Use the values your doctor gives you.")
            }
            .listRowBackground(AppColors.appCard)

            let conflicts = store.profile.conflicts
            if !conflicts.isEmpty {
                Section {
                    ForEach(conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(conflict.nutrient.displayName, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.orange)
                            HStack(alignment: .top, spacing: 12) {
                                conflictSide(title: String(localized: "Raise it"), sources: conflict.raisedBy, systemImage: "arrow.up")
                                conflictSide(title: String(localized: "Limit it"), sources: conflict.limitedBy, systemImage: "arrow.down")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Conflicts")
                } footer: {
                    Text("These conditions pull the same nutrient in opposite directions. Ask your doctor which goal applies; Coach will point the conflict out instead of choosing.")
                }
                .listRowBackground(AppColors.appCard)
            }

            Section {
                Text("This profile guides the Gout card, the DASH scorecard and Coach's advice. It is not medical advice, and Fud AI never suggests starting, stopping or changing a medicine.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Health Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.reload() }
    }

    private func goalSummary(for kind: HealthEntryKind) -> String {
        kind.rules.map { rule in
            let verb = rule.direction == .limit ? String(localized: "max") : String(localized: "min")
            return "\(rule.nutrient.displayName) \(verb) \(goals.goal(for: rule.nutrient)) \(rule.nutrient.unit)"
        }
        .joined(separator: " · ")
    }

    private func conflictSide(title: String, sources: [String], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption, design: .rounded, weight: .semibold))
            Text(sources.joined(separator: ", "))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
