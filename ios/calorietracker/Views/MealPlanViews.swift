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
                                          goals: .current, profile: profile, tastes: FoodTastesStore.shared.tastes)
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
                    PlannedOptionRow(option: option, caption: option.reason, isChosen: chosen && !meal.isSuggestion,
                                     warnings: warnings(for: option, profile: profile),
                                     isSuggested: chosen && meal.isSuggestion)
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
            Text(isToday ? "✨ is the suggestion until you tap an option to pick it; swipe left to log it now."
                 : "✨ is the suggestion until you tap an option to pick it.")
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
            .map { String(localized: "Inside your \(MedicinePrivacy.visibleDoseName($0)) dose window") }
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
    var isSuggested = false
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
                if let includes = option.includes, !includes.isEmpty {
                    Text(String(localized: "With \(includes.joined(separator: ", "))"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            } else if isSuggested {
                Text("✨").accessibilityLabel("Suggested")
            }
        }
    }
}

/// Imports a menu from a photo or pasted text: say whether it covers the week or one day,
/// read it, then check the days before saving. An `initialPhoto` (shared from another app)
/// waits for the user to choose week or day, then "Read this menu". Nothing needs picking here; each meal keeps the AI's suggestion until
/// the user picks.
struct ImportMenuView: View {
    let weekStart: Date
    var initialPhoto: UIImage? = nil
    var onImported: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodStore.self) private var foodStore
    @State private var meal: MealType = .lunch
    @State private var source = String(localized: "Work cafe")
    @State private var coversWeek = true
    @State private var weekOffset = 0
    @State private var oneDay = Date()
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var step: Step = .setup
    @State private var error: String?

    private enum Step {
        case setup
        case reading
        case review([PlannedMeal])
    }

    private var calendar: Calendar { .current }
    private var chosenWeekStart: Date {
        calendar.date(byAdding: .day, value: 7 * weekOffset, to: calendar.mondayOfWeek(containing: weekStart)) ?? weekStart
    }

    var body: some View {
        Group {
            switch step {
            case .setup: setupForm
            case .reading: readingView
            case .review(let meals): MenuImportReview(meals: meals, weekStart: chosenWeekStart, onSave: save)
            }
        }
        .navigationTitle("Import a Menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $capturedImage, onCancel: { showCamera = false }).ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            capturedImage = nil
            showCamera = false
            run(.photo(image))
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

    private var setupForm: some View {
        Form {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("menuImport.error")
                }
            }
            Section {
                Picker("Covers", selection: $coversWeek) {
                    Text("A whole week").tag(true)
                    Text("One day").tag(false)
                }
                .pickerStyle(.segmented)
                if coversWeek {
                    Picker("Week", selection: $weekOffset) {
                        Text("This week").tag(0)
                        Text("Next week").tag(1)
                    }
                } else {
                    DatePicker("Day", selection: $oneDay, displayedComponents: .date)
                }
                Picker("Usual meal", selection: $meal) {
                    ForEach([MealType.breakfast, .lunch, .dinner], id: \.self) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Where") {
                    TextField("Work cafe", text: $source)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("The menu")
            } footer: {
                Text("You can move meals to other days before saving.")
            }
            if let initialPhoto {
                Section {
                    Image(uiImage: initialPhoto)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button { run(.photo(initialPhoto)) } label: {
                        Label("Read this menu", systemImage: "text.viewfinder")
                    }
                    .accessibilityIdentifier("menuImport.readShared")
                } header: {
                    Text("Shared photo")
                } footer: {
                    Text("Choose a whole week or one day above first.")
                }
            }
            Section {
                Button { showCamera = true } label: {
                    Label("Take a photo of the menu", systemImage: "camera")
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose a photo or screenshot", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("From a photo")
            } footer: {
                Text(coversWeek ? "One photo can cover the whole week." : "")
            }
            Section("Or paste it") {
                TextField("Mon: chili, garden salad…", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                Button("Read text") { run(.text(text)) }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var readingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Reading the menu…")
                .font(.system(.headline, design: .rounded))
            Text("Estimating each dish with its sides. This can take a little while.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.appBackground)
    }

    private func run(_ input: MealPlanService.Input) {
        step = .reading
        error = nil
        let week = chosenWeekStart
        let day = coversWeek ? nil : oneDay
        Task {
            do {
                let meals = try await MealPlanService.importMenu(
                    input, weekStart: day.map { calendar.mondayOfWeek(containing: $0) } ?? week, day: day,
                    defaultMeal: meal, source: source,
                    healthLines: HealthContextPrompt.lines(foods: foodStore.entries, plan: [], onHand: []),
                    entries: foodStore.entries
                )
                let tastes = FoodTastesStore.shared.tastes
                step = .review(meals.map { meal in
                    var meal = meal
                    meal.applyTastes(tastes)
                    return meal
                })
            } catch {
                self.error = GeminiService.analysisErrorMessage(error)
                step = .setup
            }
        }
    }

    private func save(_ meals: [PlannedMeal]) {
        MealPlanStore.shared.add(meals)
        onImported?()
        dismiss()
    }
}

/// Checks an imported menu before it is saved: each meal's day and meal type can change,
/// and options or meals can go. Suggestions are marked but nothing has to be picked.
private struct MenuImportReview: View {
    @State var meals: [PlannedMeal]
    let weekStart: Date
    let onSave: ([PlannedMeal]) -> Void

    private var calendar: Calendar { .current }

    /// Two weeks from the menu's Monday, plus any day the AI chose outside them.
    private var dayChoices: [Date] {
        let base = (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.mondayOfWeek(containing: weekStart)) }
        let extra = meals.map { calendar.startOfDay(for: $0.day) }.filter { !base.contains($0) }
        return (base + extra).sorted()
    }

    var body: some View {
        List {
            Section {
                Text(meals.count == 1 ? String(localized: "Found 1 meal.") : String(localized: "Found \(meals.count) meals."))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("Check each day, then save. ✨ marks the suggested option, which counts toward that day until you pick another in the week plan.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(AppColors.appCard)

            ForEach($meals) { $meal in
                Section {
                    Picker("Day", selection: Binding(
                        get: { calendar.startOfDay(for: meal.day) },
                        set: { meal.day = $0 }
                    )) {
                        ForEach(dayChoices, id: \.self) { day in
                            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).tag(day)
                        }
                    }
                    Picker("Meal", selection: $meal.mealType) {
                        ForEach([MealType.breakfast, .lunch, .dinner, .snack], id: \.self) { Text($0.displayName).tag($0) }
                    }
                    ForEach(meal.options) { option in
                        PlannedOptionRow(option: option, caption: nil, isChosen: false, warnings: [],
                                         isSuggested: meal.chosen?.id == option.id && meal.options.count > 1)
                    }
                    .onDelete { meal.options.remove(atOffsets: $0) }
                    Button("Remove this meal", role: .destructive) {
                        let id = meal.id
                        withAnimation { meals.removeAll { $0.id == id } }
                    }
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(meals.filter { !$0.options.isEmpty }) }
                    .disabled(meals.allSatisfy { $0.options.isEmpty })
            }
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

/// A shared screenshot the user chose to import as a menu.
struct SharedMenuImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
