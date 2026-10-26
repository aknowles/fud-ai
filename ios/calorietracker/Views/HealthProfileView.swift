import SwiftUI

/// Settings → Goals → Other Nutrients → Health Profile: turn conditions on or off, see
/// the goals each one uses and any conflicts between them.
struct HealthProfileView: View {
    @State private var store = HealthProfileStore.shared
    @State private var newAvoidTerm = ""
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()

    private var goals: OptionalNutrientGoals { OptionalNutrientGoals.decoded(from: goalsData) }

    var body: some View {
        List {
            Section {
                ForEach(HealthEntryKind.allCases.filter { !$0.isMedicine }) { kind in
                    entryRow(kind)
                }
            } header: {
                Text("Conditions")
            } footer: {
                Text("Change the numbers under Other Nutrients. Use the values your doctor gives you.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                ForEach(HealthEntryKind.allCases.filter(\.isMedicine)) { kind in
                    entryRow(kind)
                }
            } header: {
                Text("Medicines")
            } footer: {
                Text("Add the medicines you take so Coach and Suggestions account for food interactions. This never changes how you take them; ask your doctor or pharmacist about your own medicines.")
            }
            .listRowBackground(AppColors.appCard)

            avoidSection

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

    private func entryRow(_ kind: HealthEntryKind) -> some View {
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
                let goals = goalSummary(for: kind)
                if !goals.isEmpty {
                    Text(goals)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(AppColors.calorie)
                }
                if !kind.avoidedFoodFlags.isEmpty {
                    Label(String(localized: "Avoid: \(kind.avoidedFoodFlags.map(\.displayName).joined(separator: ", "))"),
                          systemImage: "hand.raised.fill")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.red)
                }
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

    private var avoidSection: some View {
        Section {
            Toggle("Celiac disease (gluten)", isOn: avoidBinding(\.celiac))
                .tint(AppColors.calorie)
            Toggle("Lactose intolerance", isOn: avoidBinding(\.lactose))
                .tint(AppColors.calorie)
            ForEach(store.profile.avoidList.custom, id: \.self) { term in
                Label(term, systemImage: "hand.raised.fill")
            }
            .onDelete { offsets in
                var list = store.profile.avoidList
                list.custom.remove(atOffsets: offsets)
                store.setAvoidList(list)
            }
            HStack {
                TextField("Add a food, e.g. peanuts", text: $newAvoidTerm)
                    .textInputAutocapitalization(.never)
                    .onSubmit(addAvoidTerm)
                Button("Add", action: addAvoidTerm)
                    .disabled(newAvoidTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Foods to Avoid")
        } footer: {
            Text("Coach and Suggestions steer clear of these and flag options that contain them. Matching uses food names, ingredients and product allergen lists, so it can miss hidden ingredients; always check labels.")
        }
        .listRowBackground(AppColors.appCard)
    }

    private func avoidBinding(_ keyPath: WritableKeyPath<AvoidList, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.profile.avoidList[keyPath: keyPath] },
            set: { value in
                var list = store.profile.avoidList
                list[keyPath: keyPath] = value
                store.setAvoidList(list)
            }
        )
    }

    private func addAvoidTerm() {
        let term = newAvoidTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return }
        var list = store.profile.avoidList
        if !list.custom.contains(term) { list.custom.append(term) }
        store.setAvoidList(list)
        newAvoidTerm = ""
    }

    private func goalSummary(for kind: HealthEntryKind) -> String {
        kind.rules.map { rule in
            switch rule.direction {
            case .limit: return "\(rule.nutrient.displayName) \(String(localized: "max")) \(goals.goal(for: rule.nutrient)) \(rule.nutrient.unit)"
            case .target: return "\(rule.nutrient.displayName) \(String(localized: "min")) \(goals.goal(for: rule.nutrient)) \(rule.nutrient.unit)"
            case .steady: return "\(rule.nutrient.displayName) \(String(localized: "steady"))"
            }
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
