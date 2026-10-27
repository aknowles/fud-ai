import SwiftUI

/// Settings → App Settings → Food Memory: the user's standing corrections to AI estimates.
struct FoodMemoryView: View {
    @State private var store = FoodMemoryStore.shared
    @State private var match = ""
    @State private var instruction = ""

    var body: some View {
        Form {
            Section {
                if store.rules.isEmpty {
                    Text("No corrections yet. Swap an ingredient on Review Food and tap Remember, or add one here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.rules) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.match.isEmpty ? String(localized: "Always") : String(localized: "For \(rule.match)"))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(AppColors.calorie)
                        Text(rule.instruction)
                    }
                }
                .onDelete { store.remove(at: $0) }
            } footer: {
                Text("Sent with every food estimate (photo, text, voice, Suggestions and menu imports) and to Coach, so the AI starts from your version of a dish.")
            }

            Section("Add a correction") {
                TextField("Dish (optional), e.g. omelet", text: $match)
                    .textInputAutocapitalization(.never)
                TextField("Use egg whites instead of whole eggs", text: $instruction, axis: .vertical)
                Button("Add") {
                    store.add(FoodMemoryRule(match: match, instruction: instruction))
                    match = ""
                    instruction = ""
                }
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Food Memory")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shown in the ingredient editor when an ingredient was renamed: offers to remember the swap.
struct FoodMemoryOfferSection: View {
    let original: String
    let edited: String

    @State private var dish = ""
    @State private var saved = false

    private var isSwap: Bool {
        let before = original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let after = edited.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !before.isEmpty && !after.isEmpty && before != after
    }

    var body: some View {
        if isSwap {
            Section {
                if saved {
                    Label("Saved to food memory", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.calorie)
                } else {
                    TextField("Only for a dish (optional), e.g. omelet", text: $dish)
                        .textInputAutocapitalization(.never)
                    Button {
                        FoodMemoryStore.shared.add(FoodMemoryRule(match: dish, instruction: FoodMemory.swapInstruction(from: original, to: edited)))
                        withAnimation { saved = true }
                    } label: {
                        Label(String(localized: "Remember: \(FoodMemory.swapInstruction(from: original, to: edited))"), systemImage: "brain")
                    }
                }
            } footer: {
                Text("Next time the AI estimates this food, it uses your version.")
            }
        }
    }
}
