import SwiftUI

/// Likes, dislikes and treats. Linked from the Health Profile and the Suggestions sheet.
struct FoodTastesView: View {
    @Environment(FoodStore.self) private var foodStore
    @State private var store = FoodTastesStore.shared
    @State private var newLike = ""
    @State private var newDislike = ""

    /// Most-logged foods not yet liked or disliked, offered as likes.
    private var likeIdeas: [String] {
        let listed = Set(store.tastes.likes + store.tastes.dislikes)
        var seen = Set<String>()
        return foodStore.frequentGroups(days: 60).map { $0.template.name.lowercased() }
            .filter { !listed.contains($0) && seen.insert($0).inserted }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        List {
            Section {
                ForEach(store.tastes.likes, id: \.self) { Text($0) }
                    .onDelete { store.removeLikes(at: $0) }
                termField("Add a like, e.g. salmon", text: $newLike) { store.addLike($0) }
                ForEach(likeIdeas, id: \.self) { idea in
                    Button {
                        withAnimation { store.addLike(idea) }
                    } label: {
                        Label(idea, systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Likes")
            } footer: {
                Text(likeIdeas.isEmpty
                     ? "Suggestions and meal plans put these first when they fit your goals, and Coach plans around them."
                     : "Suggestions and meal plans put these first when they fit your goals, and Coach plans around them. The plus rows are foods you log most.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                ForEach(store.tastes.dislikes, id: \.self) { Text($0) }
                    .onDelete { store.removeDislikes(at: $0) }
                termField("Add a dislike, e.g. olives", text: $newDislike) { store.addDislike($0) }
            } header: {
                Text("Dislikes")
            } footer: {
                Text("Never suggested or picked for you. For allergies and foods you must avoid, use Foods to Avoid in the Health Profile instead.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                ForEach(store.tastes.treats) { treat in
                    HStack(spacing: 10) {
                        Text(treat.emoji ?? "🍰").font(.system(size: 22))
                        Text(treat.name)
                        Spacer()
                        Text("\(treat.calories) kcal")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { store.removeTreats(at: $0) }
                NavigationLink {
                    TreatPicker()
                } label: {
                    Label("Choose treats", systemImage: "plus.circle.fill")
                }
                Toggle("Show “Room for a treat” on Home", isOn: Binding(
                    get: { store.tastes.treatCard },
                    set: { store.setTreatCard($0) }
                ))
            } header: {
                Text("Treats")
            } footer: {
                Text("Your guilty pleasures. When your last few days are on track and today still has room under every goal, Home shows the ones that fit, and Coach can help you plan one in.")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Tastes & Treats")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.reload() }
    }

    private func termField(_ prompt: LocalizedStringKey, text: Binding<String>, add: @escaping (String) -> Void) -> some View {
        HStack {
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .onSubmit {
                    add(text.wrappedValue)
                    text.wrappedValue = ""
                }
            Button("Add") {
                add(text.wrappedValue)
                text.wrappedValue = ""
            }
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

/// Picks treats from Favorites, Frequent and Recent; tap toggles.
private struct TreatPicker: View {
    @Environment(FoodStore.self) private var foodStore
    @State private var store = FoodTastesStore.shared
    @State private var search = ""

    private var foods: [FoodEntry] {
        let all = foodStore.favorites + foodStore.frequentGroups(days: 90).map(\.template) + foodStore.recentEntries(days: 30)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return all.filter { entry in
            seen.insert(entry.favoriteKey).inserted
                && (query.isEmpty || entry.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
    }

    var body: some View {
        List {
            if foods.isEmpty {
                Text(search.isEmpty ? "Log a treat once, then choose it here." : "No matching foods")
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppColors.appCard)
            }
            ForEach(foods) { entry in
                let isTreat = store.tastes.isTreat(entry)
                HStack(spacing: 10) {
                    Text(entry.emoji ?? "🍽️").font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                        Text("\(entry.calories) kcal")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isTreat ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(AppColors.calorie)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { store.toggleTreat(entry) } }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .searchable(text: $search, prompt: Text("Search foods"))
        .navigationTitle("Choose Treats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Home card: on a day with room under every goal after a few on-track days, the user's
/// treats that fit, with one-tap logging. Hidden for the day with "Not today".
struct TreatCardView: View {
    let date: Date

    @Environment(FoodStore.self) private var foodStore
    @State private var store = FoodTastesStore.shared
    @State private var health = HealthProfileStore.shared
    @AppStorage("fork.treatCardDismissedDay") private var dismissedDay: Double = 0

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let fitting = calendar.isDateInToday(date) && store.tastes.treatCard && dismissedDay != today.timeIntervalSince1970
            ? TreatRoom.fitting(store.tastes.treats, entries: foodStore.entries, now: now,
                                calorieGoal: UserProfile.load()?.effectiveCalories ?? 0, goals: .current,
                                profile: health.profile.effective(on: now))
            : []
        if !fitting.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.calorie)
                    Text("Room for a treat")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                }
                Text("Your last few days are on track, and these still fit today under every goal.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                ForEach(fitting.prefix(3)) { treat in
                    HStack(spacing: 10) {
                        Text(treat.emoji ?? "🍰").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(treat.name)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                            Text("\(treat.calories) kcal")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Log") {
                            withAnimation { _ = foodStore.addEntry(treat.duplicatedForLogging(at: Date())) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.calorie)
                    }
                }
                Button("Not today") { withAnimation { dismissedDay = today.timeIntervalSince1970 } }
                    .font(.system(.caption, design: .rounded))
                    .buttonStyle(.borderless)
            }
            .padding()
            .progressCardStyle()
        }
    }
}
