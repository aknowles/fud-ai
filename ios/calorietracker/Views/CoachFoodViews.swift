import SwiftUI

/// The + menu's From Coach list: foods Coach suggested or the user mentioned in chat in the
/// last week. Opening it reads any new Coach replies first. Shown inside `RecentsView`.
struct CoachFoodsSection: View {
    let searchText: String
    let onLog: (FoodEntry) -> Void

    @Environment(FoodStore.self) private var foodStore
    @State private var store = CoachFoodStore.shared
    @State private var isReading = false
    @State private var error: String?

    private var visible: [CoachFood] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.foods }
        return store.foods.filter { $0.entry.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        Section {
            if isReading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading your recent chat…").foregroundStyle(.secondary)
                }
                .listRowBackground(AppColors.appCard)
            }
            if let error {
                Text(error)
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppColors.appCard)
            }
            if visible.isEmpty, !isReading {
                Text(searchText.isEmpty
                     ? String(localized: "No foods from Coach yet. Ask Coach what to eat, or tell it what you had, and the foods show up here.")
                     : String(localized: "No matching foods"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppColors.appCard)
            }
            ForEach(visible) { food in
                CoachFoodRow(food: food, accessory: "plus.circle.fill")
                    .contentShape(Rectangle())
                    .onTapGesture { onLog(food.entry) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation { store.remove(food.id) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            withAnimation { foodStore.toggleFavorite(food.entry) }
                        } label: {
                            Label("Favorite", systemImage: "heart.fill")
                        }
                        .tint(AppColors.calorie)
                    }
                    .listRowBackground(AppColors.appCard)
            }
        } footer: {
            Text("Foods Coach suggested or you mentioned in chat. Tap to review and log; swipe to favorite or remove.")
        }
        .task { await readNewReplies() }
    }

    private func readNewReplies() async {
        let conversation = ChatStore().messages
        let unread = store.unreadReplies(in: conversation)
        guard !unread.isEmpty, !isReading else { return }
        isReading = true
        error = nil
        do {
            try await store.read(unread, conversation: conversation)
        } catch {
            self.error = GeminiService.analysisErrorMessage(error)
        }
        isReading = false
    }
}

/// Under a Coach reply: find the foods in it and log them in a tap.
struct CoachMessageFoodsButton: View {
    let message: ChatMessage

    @State private var store = CoachFoodStore.shared
    @State private var isShowing = false

    var body: some View {
        if message.role == .assistant {
            let found = store.foods(from: message.id)
            Button {
                isShowing = true
            } label: {
                Label(found.isEmpty ? String(localized: "Log foods from this")
                      : found.count == 1 ? String(localized: "1 food to log") : String(localized: "\(found.count) foods to log"),
                      systemImage: "fork.knife")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .tint(AppColors.calorie)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 56)
            .padding(.top, -6)
            .sheet(isPresented: $isShowing) {
                NavigationStack { CoachMessageFoodsSheet(message: message) }
            }
        }
    }
}

/// The foods in one Coach reply, each logged now with one tap.
private struct CoachMessageFoodsSheet: View {
    let message: ChatMessage

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodStore.self) private var foodStore
    @State private var store = CoachFoodStore.shared
    @State private var isReading = false
    @State private var error: String?
    @State private var logged: Set<UUID> = []

    var body: some View {
        let found = store.foods(from: message.id)
        List {
            if isReading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Finding the foods…").foregroundStyle(.secondary)
                }
                .listRowBackground(AppColors.appCard)
            } else if let error {
                Text(error)
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppColors.appCard)
            } else if found.isEmpty, store.hasRead(message.id) {
                Text("No specific foods in this reply.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppColors.appCard)
            }
            if !found.isEmpty {
                Section {
                    ForEach(found) { food in
                        HStack {
                            CoachFoodRow(food: food, accessory: nil)
                            if logged.contains(food.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppColors.calorie)
                                    .accessibilityLabel("Logged")
                            } else {
                                Button("Log") {
                                    withAnimation {
                                        _ = foodStore.addEntry(food.entry.duplicatedForLogging(at: Date()))
                                        logged.insert(food.id)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.calorie)
                            }
                        }
                        .listRowBackground(AppColors.appCard)
                    }
                } footer: {
                    Text("Logged now as one serving; edit the entry in your diary to change it. These also stay under From Coach in the + menu.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Foods from Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task {
            guard !store.hasRead(message.id), !isReading else { return }
            isReading = true
            do {
                try await store.read([message], conversation: ChatStore().messages)
            } catch {
                self.error = GeminiService.analysisErrorMessage(error)
            }
            isReading = false
        }
    }
}

private struct CoachFoodRow: View {
    let food: CoachFood
    let accessory: String?
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit

    var body: some View {
        HStack(spacing: 12) {
            Text(food.entry.emoji ?? "🍽️")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(food.entry.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(energyUnit.format(kcal: food.entry.calories)) · \(food.foundAt.formatted(.relative(presentation: .named)))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let accessory {
                Image(systemName: accessory)
                    .font(.title3)
                    .foregroundStyle(AppColors.calorie)
            }
        }
    }
}
