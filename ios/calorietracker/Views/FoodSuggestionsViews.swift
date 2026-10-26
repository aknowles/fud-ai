import PhotosUI
import SwiftUI

/// "I'm hungry, here are my options": the input choices, shown inside the saved-meals
/// sheet (`RecentsView`) so a suggestion logs through the same review flow as a favorite.
struct FoodSuggestionsSection: View {
    let onLog: (FoodEntry) -> Void

    @Environment(FoodStore.self) private var foodStore
    @State private var collections = FoodCollectionStore.shared
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoInput: PhotoInput?

    private struct PhotoInput: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        Section {
            Button { showCamera = true } label: {
                inputLabel("Take a photo", detail: "A menu, shelf, fridge or buffet", systemImage: "camera.fill")
            }
            .buttonStyle(.plain)
            PhotosPicker(selection: $photoItem, matching: .images) {
                inputLabel("Choose a photo", detail: "A menu screenshot or a photo you took", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            NavigationLink {
                FoodSuggestionsTextEntry(onLog: onLog)
            } label: {
                inputLabel("Type or dictate them", detail: "Turkey sandwich, chili, salad bar", systemImage: "character.cursor.ibeam")
            }
            NavigationLink {
                FoodSuggestionsResultView(input: .saved(title: String(localized: "their saved foods"), entries: hungryCandidates), onLog: onLog)
            } label: {
                inputLabel("I'm just hungry", detail: "Pick from my saved foods, or wait", systemImage: "fork.knife")
            }
            .disabled(hungryCandidates.isEmpty)
        } header: {
            Text("What are your options?")
        }
        .listRowBackground(AppColors.appCard)
        .onAppear { collections.reload() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $capturedImage).ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            capturedImage = nil
            photoInput = PhotoInput(image: image)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photoInput = PhotoInput(image: image)
                }
            }
        }
        .sheet(item: $photoInput) { input in
            NavigationStack {
                FoodSuggestionsResultView(input: .photo(input.image), onLog: onLog)
            }
        }

        MealPlanSection(onLog: onLog)

        let sources = savedSources
        if !sources.isEmpty {
            Section {
                ForEach(sources, id: \.title) { source in
                    NavigationLink {
                        FoodSuggestionsResultView(input: .saved(title: source.title, entries: source.entries), onLog: onLog)
                    } label: {
                        inputLabel(source.title, detail: source.entries.count == 1 ? String(localized: "1 food") : String(localized: "\(source.entries.count) foods"), systemImage: source.systemImage)
                    }
                }
            } header: {
                Text("Choose from")
            }
            .listRowBackground(AppColors.appCard)
        }
    }

    private var savedSources: [(title: String, entries: [FoodEntry], systemImage: String)] {
        var sources = collections.collections
            .filter { !$0.items.isEmpty }
            .map { (title: $0.name, entries: $0.items, systemImage: "folder.fill") }
        if !foodStore.favorites.isEmpty {
            sources.append((title: String(localized: "Favorites"), entries: foodStore.favorites, systemImage: "heart.fill"))
        }
        return sources
    }

    /// Favorites, collection items and frequent foods, without repeats.
    private var hungryCandidates: [FoodEntry] {
        let all = foodStore.favorites + collections.collections.flatMap(\.items)
            + foodStore.frequentGroups(days: 30).map(\.template)
        var seen = Set<String>()
        return Array(all.filter { seen.insert($0.favoriteKey).inserted }.prefix(FoodSuggestionService.maxSaved))
    }

    private func inputLabel(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppColors.calorie)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Typed or dictated options.
private struct FoodSuggestionsTextEntry: View {
    let onLog: (FoodEntry) -> Void
    @State private var text = ""

    var body: some View {
        List {
            Section {
                TextField("Turkey sandwich, chili, salad bar…", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            } footer: {
                Text("List what you can choose from. Use the keyboard's microphone to dictate.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                NavigationLink {
                    FoodSuggestionsResultView(input: .text(text), onLog: onLog)
                } label: {
                    Label("Suggest", systemImage: "sparkles")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Your Options")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Runs the suggestion and shows the pick (an option, or waiting) and the ranked options.
struct FoodSuggestionsResultView: View {
    let input: FoodSuggestionInput
    let onLog: (FoodEntry) -> Void

    @Environment(FoodStore.self) private var foodStore
    @Environment(FastingStore.self) private var fastingStore
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case failed(String)
        case loaded(FoodSuggestions, waitWins: Bool, nextMeal: UsualMeal?)
    }

    var body: some View {
        List {
            switch phase {
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Weighing your options…")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(AppColors.appCard)
            case .failed(let message):
                Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
                .listRowBackground(AppColors.appCard)
            case .loaded(let suggestions, let waitWins, let nextMeal):
                pickSection(suggestions, waitWins: waitWins, nextMeal: nextMeal)
                Section {
                    ForEach(suggestions.options) { option in
                        SuggestionOptionRow(option: option, isPick: !waitWins && option.id == suggestions.pick)
                            .contentShape(Rectangle())
                            .onTapGesture { onLog(option.entry) }
                    }
                } header: {
                    Text("Your options, best first")
                } footer: {
                    Text("Totals are for today after eating it. Tap an option to review and log it.")
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func pickSection(_ suggestions: FoodSuggestions, waitWins: Bool, nextMeal: UsualMeal?) -> some View {
        Section {
            if waitWins {
                VStack(alignment: .leading, spacing: 6) {
                    Label(waitTitle(nextMeal), systemImage: "clock.fill")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.calorie)
                    if !suggestions.waitReason.isEmpty { Text(suggestions.waitReason).font(.subheadline) }
                    if let bridge = suggestions.bridgeText, !bridge.isEmpty {
                        Text(String(localized: "To tide you over: \(bridge)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if let snack = suggestions.bridgeSnack {
                    SuggestionEntryLine(entry: snack, caption: String(localized: "Small saved snack · tap to log"))
                        .contentShape(Rectangle())
                        .onTapGesture { onLog(snack) }
                }
            } else if let pick = suggestions.options.first(where: { $0.id == suggestions.pick }) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(localized: "Eat: \(pick.entry.name)"), systemImage: "checkmark.seal.fill")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.calorie)
                    if !suggestions.pickReason.isEmpty { Text(suggestions.pickReason).font(.subheadline) }
                    if !suggestions.waitReason.isEmpty {
                        Text(String(localized: "Or wait: \(suggestions.waitReason)"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Recommended")
        }
        .listRowBackground(AppColors.appCard)
    }

    private func waitTitle(_ nextMeal: UsualMeal?) -> String {
        guard let nextMeal else { return String(localized: "Wait for your next meal") }
        return String(localized: "Wait for \(nextMeal.mealType.displayName) (about \(nextMeal.minutesAway) min)")
    }

    private func load() async {
        phase = .loading
        let now = Date()
        let calendar = Calendar.current
        let today = foodStore.entries.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let calorieGoal = UserProfile.load()?.effectiveCalories ?? 0
        let context = SuggestionContext(
            caloriesLeft: calorieGoal - today.reduce(0) { $0 + $1.calories },
            nextMeal: UsualMeal.next(after: now, entries: foodStore.entries, calendar: calendar),
            isFasting: fastingStore.activeSession != nil
        )
        let profile = HealthProfileStore.shared.profile.effective(on: now, calendar: calendar)
        do {
            var (suggestions, aiPickedWait) = try await FoodSuggestionService.suggest(
                input, context: context,
                healthLines: HealthContextPrompt.lines(foods: foodStore.entries, profile: profile, now: now),
                now: now
            )
            var usual: [OptionalNutrient: Double] = [:]
            for rule in profile.rules where rule.direction == .steady {
                usual[rule.nutrient] = SteadyBand.usual(rule.nutrient, entries: foodStore.entries, before: now, calendar: calendar)
            }
            suggestions.options = SuggestionRanking.ranked(SuggestionRanking.evaluate(
                suggestions.options, today: today, calorieGoal: calorieGoal, goals: .current, profile: profile, usual: usual
            ))
            let originalPick = suggestions.pick
            suggestions.pick = SuggestionRanking.safePick(originalPick, in: suggestions.options)
            let everyOptionAvoided = originalPick != nil && suggestions.pick == nil
            let saved = foodStore.favorites + FoodCollectionStore.shared.collections.flatMap(\.items)
            suggestions.bridgeSnack = SuggestionRanking.bridgeSnack(from: saved)
            phase = .loaded(suggestions, waitWins: aiPickedWait || context.prefersWaiting || everyOptionAvoided,
                            nextMeal: context.nextMeal)
        } catch {
            phase = .failed(GeminiService.analysisErrorMessage(error))
        }
    }
}

private struct SuggestionOptionRow: View {
    let option: SuggestionOption
    let isPick: Bool
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SuggestionEntryLine(entry: option.entry, caption: nil)
                if isPick {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(AppColors.calorie)
                }
            }
            ForEach(interactionFlags) { flag in
                Label(String(localized: "Avoid with your medicine: \(flag.displayName)"), systemImage: "pills.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.red)
            }
            ForEach(sensitivityFlags, id: \.0) { label, level in
                Label(level == .avoid ? String(localized: "Avoid: \(label)") : String(localized: "Go easy: \(label)"),
                      systemImage: "exclamationmark.bubble.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(level == .avoid ? .red : .orange)
            }
            ForEach(doseWindowKinds) { kind in
                Label(String(localized: "Not now: inside your \(kind.doseName) dose window"), systemImage: "clock.badge.exclamationmark")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.red)
            }
            ForEach(unsteadyNutrients) { nutrient in
                Label(String(localized: "\(nutrient.displayName) well above your usual day"), systemImage: "waveform.path.ecg")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            ForEach(avoidLabels, id: \.self) { label in
                Label(String(localized: "Contains \(label)"), systemImage: "hand.raised.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.red)
            }
            if let tweak = option.tweak {
                Label(tweak, systemImage: "wand.and.stars")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppColors.calorie)
            }
            if !option.reason.isEmpty {
                Text(option.reason)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(afterLine)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(option.flags.isEmpty ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var interactionFlags: [FoodFlag] {
        option.flags.compactMap { if case .interaction(let flag) = $0 { flag } else { nil } }
    }

    private var sensitivityFlags: [(String, SensitivityLevel)] {
        option.flags.compactMap { if case .sensitivity(let label, let level) = $0 { (label, level) } else { nil } }
    }

    private var doseWindowKinds: [HealthEntryKind] {
        option.flags.compactMap { if case .doseWindow(let kind) = $0 { kind } else { nil } }
    }

    private var unsteadyNutrients: [OptionalNutrient] {
        option.flags.compactMap { if case .unsteady(let nutrient) = $0 { nutrient } else { nil } }
    }

    private var avoidLabels: [String] {
        option.flags.compactMap { if case .avoid(let label) = $0 { label } else { nil } }
    }

    private var afterLine: String {
        var parts = [String(localized: "After: \(energyUnit.format(kcal: option.caloriesAfter))")]
        for limit in option.limitsAfter {
            let over = option.flags.contains(.over(limit.nutrient)) ? " ⚠︎" : ""
            parts.append("\(limit.nutrient.displayName) \(Int(limit.amount.rounded()))/\(limit.goal) \(limit.nutrient.unit)\(over)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SuggestionEntryLine: View {
    let entry: FoodEntry
    let caption: String?
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji ?? "🍽️")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption ?? "\(energyUnit.format(kcal: entry.calories)) · P \(Int(entry.protein.rounded())) · C \(Int(entry.carbs.rounded())) · F \(Int(entry.fat.rounded()))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
