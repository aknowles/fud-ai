import PhotosUI
import SwiftUI

extension Calendar {
    /// Monday of the week containing `date`, whatever the locale's first weekday is.
    func mondayOfWeek(containing date: Date) -> Date {
        let day = startOfDay(for: date)
        let daysSinceMonday = (component(.weekday, from: day) + 5) % 7
        return self.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }
}

/// Today's planned meals and a link to the week, shown in the Suggestions sheet.
struct MealPlanSection: View {
    let onLog: (FoodEntry) -> Void

    @Environment(FoodStore.self) private var foodStore
    @State private var plan = MealPlanStore.shared

    var body: some View {
        let today = Date()
        let logged = foodStore.entries(for: today)
        let pending = plan.meals(on: today).filter { !$0.isLogged(in: logged) }
        Section {
            ForEach(pending) { meal in
                if let chosen = meal.chosen {
                    PlannedOptionRow(option: chosen, caption: "\(meal.mealType.displayName)\(meal.source.map { " · \($0)" } ?? "") · tap to log",
                                     isChosen: false, warnings: [])
                        .contentShape(Rectangle())
                        .onTapGesture { onLog(chosen.entry) }
                }
            }
            NavigationLink {
                WeekPlanView(onLog: onLog)
            } label: {
                Label("Week plan", systemImage: "calendar")
                    .font(.system(.body, design: .rounded, weight: .medium))
            }
        } header: {
            Text("Meal plan")
        } footer: {
            Text("Plan recipes or import a cafe's weekly menu; days that would break a limit get a swap.")
        }
        .listRowBackground(AppColors.appCard)
        .onAppear { plan.reload() }
    }
}

/// A week of planned meals with day totals, limit flags and swaps.
struct WeekPlanView: View {
    let onLog: (FoodEntry) -> Void

    @Environment(FoodStore.self) private var foodStore
    @State private var plan = MealPlanStore.shared
    @State private var health = HealthProfileStore.shared
    @State private var weekOffset = 0
    @State private var sheet: Sheet?
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit

    private enum Sheet: String, Identifiable {
        case importMenu, addSaved
        var id: String { rawValue }
    }

    private var calendar: Calendar { .current }
    private var weekStart: Date {
        calendar.date(byAdding: .day, value: 7 * weekOffset, to: calendar.mondayOfWeek(containing: .now)) ?? .now
    }
    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }

    var body: some View {
        let plannedDays = days.filter { !plan.meals(on: $0).isEmpty }
        List {
            Section {
                Picker("Week", selection: $weekOffset) {
                    Text("This week").tag(0)
                    Text("Next week").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            if plannedDays.isEmpty {
                Section {
                    Text("Nothing planned this week. Import a menu or add a saved food from the + button.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppColors.appCard)
            }
            ForEach(plannedDays, id: \.self) { day in
                daySection(day)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Week Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sheet = .importMenu } label: { Label("Import a menu", systemImage: "doc.text.viewfinder") }
                    Button { sheet = .addSaved } label: { Label("Add a saved food", systemImage: "heart") }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheet) { which in
            NavigationStack {
                switch which {
                case .importMenu: ImportMenuView(weekStart: weekStart)
                case .addSaved: AddPlannedFoodView(weekStart: weekStart)
                }
            }
        }
        .onAppear { plan.reload() }
    }

    private func daySection(_ day: Date) -> some View {
        let meals = plan.meals(on: day)
        let logged = foodStore.entries(for: day)
        let profile = health.profile.effective(on: day)
        let summary = PlanDaySummary.make(day: day, meals: meals, logged: logged,
                                          calorieGoal: UserProfile.load()?.effectiveCalories ?? 0,
                                          goals: .current, profile: profile)
        let isToday = calendar.isDateInToday(day)
        return Section {
            Text(summaryLine(summary))
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(summary.overLimits.isEmpty && !summary.overCalories ? Color.secondary : Color.red)
            ForEach(summary.swaps, id: \.mealID) { swap in
                Button {
                    withAnimation { plan.choose(swap.to, in: swap.mealID) }
                } label: {
                    Label(String(localized: "Swap \(swap.fromName) for \(swap.toName) to fix \(swap.nutrient.displayName.lowercased())"),
                          systemImage: "arrow.triangle.swap")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
            }
            ForEach(meals) { meal in
                let isLogged = meal.isLogged(in: logged)
                HStack {
                    Text("\(meal.mealType.displayName)\(meal.source.map { " · \($0)" } ?? "")\(isLogged ? " · logged" : "")")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Spacer()
                    Button(role: .destructive) {
                        withAnimation { plan.remove(meal.id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                ForEach(meal.options) { option in
                    let chosen = meal.chosen?.id == option.id
                    PlannedOptionRow(option: option, caption: option.reason, isChosen: chosen,
                                     warnings: warnings(for: option, profile: profile))
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { plan.choose(option.id, in: meal.id) } }
                        .swipeActions(edge: .trailing) {
                            if isToday && !isLogged {
                                Button { onLog(option.entry) } label: { Label("Log", systemImage: "plus.circle.fill") }
                                    .tint(AppColors.calorie)
                            }
                        }
                }
            }
        } header: {
            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        } footer: {
            if isToday { Text("Tap an option to pick it; swipe left to log it now.") }
        }
        .listRowBackground(AppColors.appCard)
    }

    private func summaryLine(_ summary: PlanDaySummary) -> String {
        var parts = [energyUnit.format(kcal: summary.calories) + (summary.overCalories ? " ⚠︎" : "")]
        for limit in summary.limits {
            let over = summary.overLimits.contains(limit.nutrient) ? " ⚠︎" : ""
            parts.append("\(limit.nutrient.displayName) \(Int(limit.amount.rounded()))/\(limit.goal) \(limit.nutrient.unit)\(over)")
        }
        return parts.joined(separator: " · ")
    }

    private func warnings(for option: PlannedOption, profile: HealthProfile) -> [String] {
        let suggestion = SuggestionOption(entry: option.entry, reason: "", tweak: nil, contains: option.contains)
        let avoid = SuggestionRanking.avoidMatches(for: suggestion, in: profile.avoidList).map { String(localized: "Contains \($0)") }
        let interactions = SuggestionRanking.interactions(for: suggestion, in: profile)
            .map { String(localized: "Avoid with your medicine: \($0.displayName)") }
        let dose = Set(DoseTiming.conflicts(for: option.entry, profile: profile).map(\.kind))
            .map { String(localized: "Inside your \($0.doseName) dose window") }
        let sensitivities = profile.sensitivityList.matches(for: option.entry, extraTags: option.contains)
            .filter { $0.level != .note }
            .map { $0.level == .avoid ? String(localized: "Avoid: \($0.label)") : String(localized: "Go easy: \($0.label)") }
        return avoid + interactions + dose.sorted() + sensitivities
    }
}

private struct PlannedOptionRow: View {
    let option: PlannedOption
    let caption: String?
    let isChosen: Bool
    let warnings: [String]
    @AppStorage(EnergyUnit.storageKey) private var energyUnit = EnergyUnit.defaultUnit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(option.entry.emoji ?? "🍽️")
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(option.entry.name)
                    .font(.system(.body, design: .rounded, weight: isChosen ? .semibold : .regular))
                Text(energyUnit.format(kcal: option.entry.calories) + (caption.map { " · \($0)" } ?? ""))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
            if isChosen {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.calorie)
            }
        }
    }
}

/// Imports a multi-day menu from a photo or pasted text into the chosen week.
private struct ImportMenuView: View {
    let weekStart: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodStore.self) private var foodStore
    @State private var meal: MealType = .lunch
    @State private var source = String(localized: "Work cafe")
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Picker("Usual meal", selection: $meal) {
                    ForEach([MealType.breakfast, .lunch, .dinner], id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField("Where", text: $source)
            } footer: {
                Text(String(localized: "Week of \(weekStart.formatted(date: .abbreviated, time: .omitted))"))
            }
            Section("From a photo") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose a menu photo or screenshot", systemImage: "photo.on.rectangle")
                }
                .disabled(isWorking)
            }
            Section("Or paste the menu") {
                TextField("Mon: chili, garden salad…", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                Button("Import text") { run(.text(text)) }
                    .disabled(isWorking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isWorking {
                Section { HStack { ProgressView(); Text("Reading the menu…").foregroundStyle(.secondary) } }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Import a Menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    run(.photo(image))
                }
            }
        }
    }

    private func run(_ input: MealPlanService.Input) {
        isWorking = true
        error = nil
        Task {
            do {
                let meals = try await MealPlanService.importMenu(
                    input, weekStart: weekStart, defaultMeal: meal, source: source,
                    healthLines: HealthContextPrompt.lines(foods: foodStore.entries, plan: []),
                    entries: foodStore.entries
                )
                MealPlanStore.shared.add(meals)
                dismiss()
            } catch {
                self.error = GeminiService.analysisErrorMessage(error)
            }
            isWorking = false
        }
    }
}

/// Puts a saved food or recipe on a day of the week.
private struct AddPlannedFoodView: View {
    let weekStart: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodStore.self) private var foodStore
    @State private var day = Date()
    @State private var meal: MealType = .dinner
    @State private var search = ""

    private var saved: [FoodEntry] {
        let all = foodStore.favorites + FoodCollectionStore.shared.collections.flatMap(\.items)
            + foodStore.frequentGroups(days: 90).map(\.template)
        var seen = Set<String>()
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { entry in
            seen.insert(entry.favoriteKey).inserted
                && (query.isEmpty || entry.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
    }

    var body: some View {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        List {
            Section {
                DatePicker("Day", selection: $day, in: weekStart...weekEnd, displayedComponents: .date)
                Picker("Meal", selection: $meal) {
                    ForEach([MealType.breakfast, .lunch, .dinner, .snack], id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("Saved foods") {
                ForEach(saved) { entry in
                    PlannedOptionRow(option: PlannedOption(entry: entry), caption: nil, isChosen: false, warnings: [])
                        .contentShape(Rectangle())
                        .onTapGesture {
                            MealPlanStore.shared.add([MealPlanService.plannedMeal(from: entry, day: day, meal: meal,
                                                                                  entries: foodStore.entries)])
                            dismiss()
                        }
                }
            }
        }
        .searchable(text: $search, prompt: Text("Search saved foods"))
        .navigationTitle("Add a Saved Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .onAppear {
            let today = Calendar.current.startOfDay(for: .now)
            day = (weekStart...weekEnd).contains(today) ? today : weekStart
        }
    }
}
