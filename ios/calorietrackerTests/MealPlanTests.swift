import Foundation
import Testing
@testable import calorietracker

/// Planned meals and cafe menus: picks, logged detection, day totals with swaps, the store,
/// menu import parsing, and what Coach is told.
@MainActor
struct MealPlanTests {
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }

    private func food(_ name: String, calories: Int = 500, sodium: Double? = nil, at date: Date? = nil,
                      meal: MealType = .lunch) -> FoodEntry {
        FoodEntry(name: name, calories: calories, protein: 20, carbs: 50, fat: 15,
                  timestamp: date ?? calendar.date(byAdding: .hour, value: 12, to: today)!, source: .textInput,
                  mealType: meal, sodium: sodium)
    }

    private func cafeLunch(_ options: [FoodEntry], chosen: Int = 0, day: Date? = nil, contains: [[String]] = []) -> PlannedMeal {
        let planned = options.enumerated().map { index, entry in
            PlannedOption(entry: entry, contains: contains.indices.contains(index) ? contains[index] : [])
        }
        return PlannedMeal(day: day ?? today, mealType: .lunch, source: "Work cafe", options: planned, chosenID: planned[chosen].id)
    }

    @Test func aSingleOptionIsAlwaysChosenAndLoggedMealsAreRecognizedByName() {
        let recipe = PlannedMeal(day: today, mealType: .dinner, options: [PlannedOption(entry: food("Lentil soup"))])
        #expect(recipe.chosen?.entry.name == "Lentil soup")
        #expect(recipe.isLogged(in: [food("lentil soup")]))
        #expect(!recipe.isLogged(in: [food("Tomato soup")]))
    }

    @Test func aDayOverTheSodiumLimitOffersTheSwapThatFixesIt() throws {
        let lunch = cafeLunch([food("Pepperoni pizza", sodium: 1_500), food("Grilled chicken bowl", sodium: 600)])
        let breakfast = food("Bagel with lox", calories: 450, sodium: 1_200, meal: .breakfast)

        let summary = PlanDaySummary.make(day: today, meals: [lunch], logged: [breakfast], calorieGoal: 2_200,
                                          goals: .defaults, profile: HealthProfile(entries: [.dash]))

        #expect(summary.calories == 950)
        #expect(summary.overLimits == [.sodium])
        let swap = try #require(summary.swaps.first)
        #expect(swap.fromName == "Pepperoni pizza")
        #expect(swap.toName == "Grilled chicken bowl")
        #expect(swap.nutrient == .sodium)
    }

    @Test func swapsNeverOfferAnAvoidedFoodAndLoggedMealsAreNotCountedTwice() {
        let lunch = cafeLunch([food("Ramen", sodium: 2_000), food("Turkey sandwich", sodium: 900)],
                              contains: [["wheat", "soy"], ["wheat"]])
        let profile = HealthProfile(entries: [.dash], avoid: AvoidList(celiac: true))

        let summary = PlanDaySummary.make(day: today, meals: [lunch], logged: [], calorieGoal: 2_200, goals: .defaults, profile: profile)
        #expect(summary.overLimits.isEmpty)

        let heavy = cafeLunch([food("Ramen", sodium: 2_500), food("Turkey sandwich", sodium: 900)], contains: [["wheat"], ["wheat"]])
        let over = PlanDaySummary.make(day: today, meals: [heavy], logged: [], calorieGoal: 2_200, goals: .defaults, profile: profile)
        #expect(over.overLimits == [.sodium])
        #expect(over.swaps.isEmpty)

        let logged = PlanDaySummary.make(day: today, meals: [heavy], logged: [food("Ramen", sodium: 2_500)], calorieGoal: 2_200,
                                         goals: .defaults, profile: HealthProfile())
        #expect(logged.calories == 500)
    }

    @Test func theStorePersistsChoicesAndDropsOldDays() {
        let suite = "MealPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MealPlanStore(defaults: defaults)
        let lunch = cafeLunch([food("Pizza"), food("Salad")])
        let old = cafeLunch([food("Old soup")], day: calendar.date(byAdding: .day, value: -40, to: today)!)

        store.add([lunch, old])
        store.choose(lunch.options[1].id, in: lunch.id)
        let reloaded = MealPlanStore(defaults: defaults)

        #expect(reloaded.meals.count == 1)
        #expect(reloaded.meals(on: today).first?.chosen?.entry.name == "Salad")
        reloaded.remove(lunch.id)
        #expect(MealPlanStore(defaults: defaults).meals.isEmpty)
    }

    // MARK: - Repeating meals

    private func freshDefaults() -> (UserDefaults, () -> Void) {
        let suite = "MealPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    private func days(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    /// Taco Tuesday at the cafe, first planned `offset` days from today, with the second option picked.
    private func tacoTuesday(startingAt offset: Int) -> PlannedMeal {
        var meal = cafeLunch([food("Chicken burrito"), food("Taco salad")], chosen: 1, day: days(offset))
        meal.repeatsWeekly = true
        return meal
    }

    @Test func aRepeatingMealIsFilledInOnTheSameWeekdayUpToTwoWeeksAhead() throws {
        let (defaults, cleanUp) = freshDefaults()
        defer { cleanUp() }
        let store = MealPlanStore(defaults: defaults)
        let taco = tacoTuesday(startingAt: -7)

        store.add([taco])

        let copies = store.meals.filter { $0.repeatOf == taco.id }.sorted { $0.day < $1.day }
        #expect(copies.map(\.day) == [days(0), days(7)])
        let next = try #require(copies.last)
        #expect(next.chosen?.entry.name == "Taco salad")
        #expect(next.isPartOfRepeat && !next.isRepeating)
        #expect(calendar.isDate(next.chosen!.entry.timestamp, inSameDayAs: days(7)))
        #expect(Set(next.options.map(\.id)).isDisjoint(with: taco.options.map(\.id)))

        let reloaded = MealPlanStore(defaults: defaults)
        #expect(reloaded.meals.count == 3, "A reload fills nothing twice")
    }

    @Test func aRemovedCopyStaysRemovedAfterAReload() {
        let (defaults, cleanUp) = freshDefaults()
        defer { cleanUp() }
        let store = MealPlanStore(defaults: defaults)
        let taco = tacoTuesday(startingAt: 0)
        store.add([taco])
        let nextWeek = store.meals.first { $0.repeatOf == taco.id }!

        store.remove(nextWeek.id)

        let reloaded = MealPlanStore(defaults: defaults)
        #expect(reloaded.meals(on: days(7)).isEmpty)
        #expect(reloaded.meals.first { $0.id == taco.id }?.skippedDays?.count == 1)
    }

    @Test func stoppingTheRepeatFromACopyRemovesTheComingCopiesOnly() {
        let (defaults, cleanUp) = freshDefaults()
        defer { cleanUp() }
        let store = MealPlanStore(defaults: defaults)
        let taco = tacoTuesday(startingAt: -7)
        store.add([taco])
        let todayCopy = store.meals.first { $0.repeatOf == taco.id && calendar.isDate($0.day, inSameDayAs: today) }!

        store.setRepeatsWeekly(false, for: todayCopy.id)

        let reloaded = MealPlanStore(defaults: defaults)
        #expect(reloaded.meals.first { $0.id == taco.id }?.isRepeating == false)
        #expect(reloaded.meals.map(\.day).sorted() == [days(-7), days(0)])
    }

    @Test func removingTheRepeatingMealHandsTheRepeatToItsNextCopy() {
        let (defaults, cleanUp) = freshDefaults()
        defer { cleanUp() }
        let store = MealPlanStore(defaults: defaults)
        let taco = tacoTuesday(startingAt: -7)
        store.add([taco])

        store.remove(taco.id)

        let reloaded = MealPlanStore(defaults: defaults)
        let template = reloaded.meals.first { $0.isRepeating }
        #expect(template?.day == days(0))
        #expect(template?.repeatOf == nil)
        #expect(reloaded.meals.map(\.day).sorted() == [days(0), days(7)])
        #expect(reloaded.meals.first { $0.day == days(7) }?.repeatOf == template?.id)
    }

    @Test func anOldRepeatingMealSurvivesTheCleanupAndKeepsFillingIn() {
        let (defaults, cleanUp) = freshDefaults()
        defer { cleanUp() }
        let store = MealPlanStore(defaults: defaults)
        var old = tacoTuesday(startingAt: -40)
        old.repeatsWeekly = nil
        var repeating = tacoTuesday(startingAt: -40)
        repeating.mealType = .dinner
        store.add([old, repeating])

        let reloaded = MealPlanStore(defaults: defaults)
        #expect(reloaded.meals.contains { $0.id == repeating.id })
        #expect(!reloaded.meals.contains { $0.id == old.id })
        #expect(reloaded.meals.filter { $0.repeatOf == repeating.id }.map(\.day).sorted() == [days(2), days(9)])
    }

    @Test func aWeeklyMenuBecomesPlannedMealsInsideTheWeek() throws {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let response = """
        {"days":[
          {"date":"2026-11-02","meal":"lunch","options":[
            {"food":{"name":"Chili","calories":450,"protein":25,"carbs":40,"fat":18,"sodium":1100,"contains":[]},"reason":"Filling."},
            {"food":{"name":"Garden salad","calories":250,"protein":8,"carbs":20,"fat":14,"sodium":300,"contains":["egg"]},"reason":"Light."}
          ],"pick":1},
          {"date":"2026-11-04","meal":"Dinner","options":[{"food":{"name":"Fish tacos","calories":550,"protein":30,"carbs":50,"fat":20,"contains":["fish","wheat"]}}],"pick":0},
          {"date":"2026-11-12","meal":"lunch","options":[{"food":{"name":"Out of week","calories":1,"protein":0,"carbs":0,"fat":0}}]}
        ]}
        """

        let meals = try MealPlanService.parse(response, weekStart: monday, defaultMeal: .lunch, source: "Work cafe",
                                              entries: [], calendar: calendar)

        #expect(meals.count == 2)
        #expect(meals[0].day == monday)
        #expect(meals[0].chosen?.entry.name == "Garden salad")
        #expect(meals[0].isSuggestion)
        #expect(meals[0].chosenID == nil)
        #expect(!meals[1].isSuggestion)
        #expect(meals[0].options[1].contains == ["egg"])
        #expect(meals[0].options[0].entry.sodium == 1_100)
        #expect(meals[1].mealType == .dinner)
        #expect(calendar.component(.hour, from: meals[1].options[0].entry.timestamp) == 18)
        #expect(throws: (any Error).self) {
            try MealPlanService.parse(#"{"days":[]}"#, weekStart: monday, defaultMeal: .lunch, source: "x", entries: [])
        }
    }

    @Test func aOneDayMenuLandsOnThatDayWithSidesAndOneMealPerSlot() throws {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!
        let response = """
        {"days":[
          {"date":"2026-11-02","meal":"lunch","options":[
            {"food":{"name":"Roast chicken","calories":650,"protein":45,"carbs":50,"fat":25},"includes":["rice pilaf"," green beans",""]}
          ],"pick":0},
          {"date":"2026-11-03","meal":"lunch","options":[
            {"food":{"name":"Tomato soup","calories":200,"protein":5,"carbs":30,"fat":6}}
          ]}
        ]}
        """

        let meals = try MealPlanService.parse(response, weekStart: monday, day: thursday, defaultMeal: .lunch,
                                              source: "Work cafe", entries: [], calendar: calendar)

        #expect(meals.count == 1)
        #expect(meals[0].day == calendar.startOfDay(for: thursday))
        #expect(meals[0].options.map(\.entry.name) == ["Roast chicken", "Tomato soup"])
        #expect(meals[0].options[0].includes == ["rice pilaf", "green beans"])
        #expect(meals[0].options[1].includes == nil)
        #expect(meals[0].chosen?.entry.name == "Roast chicken")
        #expect(meals[0].isSuggestion)
    }

    @Test func aUserPickReplacesTheSuggestion() throws {
        let defaults = try #require(UserDefaults(suiteName: "MealPlanTests-pick-\(UUID())"))
        let store = MealPlanStore(defaults: defaults)
        let options = [PlannedOption(entry: food("Chili", calories: 450)), PlannedOption(entry: food("Salad", calories: 250))]
        let meal = PlannedMeal(day: today, mealType: .lunch, options: options, suggestedID: options[0].id)
        store.add([meal])
        store.choose(options[1].id, in: meal.id)
        let reloaded = try #require(MealPlanStore(defaults: defaults).meals.first)
        #expect(reloaded.chosen?.entry.name == "Salad")
        #expect(!reloaded.isSuggestion)
    }

    @Test func plansSavedBeforeSuggestionsStillDecode() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","day":0,"mealType":"lunch","options":[]}]"#
        let decoded = try JSONDecoder().decode([PlannedMeal].self, from: Data(json.utf8))
        #expect(decoded.first?.suggestedID == nil)
    }

    @Test func theOneDayPromptNamesTheDayAndAsksForSides() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        let prompt = MealPlanService.prompt(for: .text("Roast chicken"), weekStart: monday, day: thursday,
                                            defaultMeal: .lunch, healthLines: [])
        #expect(prompt.contains("menu for one day"))
        #expect(prompt.contains("2026-11-05"))
        #expect(prompt.contains("includes"))
    }

    @Test func theImportPromptCarriesTheWeekAndTheFoodShape() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let prompt = MealPlanService.prompt(for: .text("Mon: chili, salad"), weekStart: monday, defaultMeal: .lunch,
                                            healthLines: ["- Gout: favor low-purine choices"])

        #expect(prompt.contains("The week starts on Monday 2026-11-02"))
        #expect(prompt.contains("Mon: chili, salad"))
        #expect(prompt.contains("- Gout: favor low-purine choices"))
        #expect(prompt.contains(#""contains":["wheat"]"#))
    }

    @Test func coachSeesTheRestOfTodaysPlanAndTomorrow() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let plan = [
            cafeLunch([food("Pepperoni pizza", calories: 620, sodium: 1_500), food("Grilled chicken bowl", sodium: 600)]),
            PlannedMeal(day: tomorrow, mealType: .dinner, source: "Recipe", options: [PlannedOption(entry: food("Lentil soup", calories: 400))]),
        ]

        let lines = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(entries: [.dash]), plan: plan, symptoms: [], onHand: [], tastes: FoodTastes(),
                                              now: calendar.date(byAdding: .hour, value: 9, to: today)!, calendar: calendar)

        #expect(lines.contains("- Today, lunch (Work cafe): planned Pepperoni pizza (620 kcal, sodium 1500 mg); other options: Grilled chicken bowl."))
        #expect(lines.contains("- Tomorrow, dinner (Recipe): planned Lentil soup (400 kcal)."))

        let noProfile = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(), plan: plan, symptoms: [], onHand: [], tastes: FoodTastes(),
                                                  now: calendar.date(byAdding: .hour, value: 9, to: today)!, calendar: calendar)
        #expect(noProfile.contains("## Meal plan"))
        #expect(!noProfile.contains("## Health goals"))
    }

    // A shared week menu failed after a long spin: the reply hit the 1,024-token default
    // cap twice. Menu import and Suggestions now raise the cap for their own calls only.
    @Test func menuImportAndSuggestionsRaiseTheReplyCapOnlyForTheirOwnCalls() async {
        let outside = AIProviderSettings.maxResponseTokens
        #expect(AIResponseBudget.minimumTokens == 0)
        let inside = await AIResponseBudget.withMinimum(AIResponseBudget.menuImport) { AIProviderSettings.maxResponseTokens }
        #expect(inside == max(outside, 8_192))
        let nested = await AIResponseBudget.withMinimum(AIResponseBudget.menuImport) {
            await AIResponseBudget.withMinimum(AIResponseBudget.suggestions) { AIProviderSettings.maxResponseTokens }
        }
        #expect(nested == max(outside, 8_192), "An inner, smaller budget never lowers an outer one")
        #expect(AIProviderSettings.maxResponseTokens == outside)
    }

    @Test func aMenuMealKeepsAtMostFourOptions() throws {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let dishes = (1...6).map { #"{"food":{"name":"Dish \#($0)","calories":500,"protein":20,"carbs":50,"fat":15},"includes":[]}"# }
        let response = #"{"days":[{"date":"2026-11-02","meal":"lunch","options":["# + dishes.joined(separator: ",") + #"],"pick":0}]}"#
        let meals = try MealPlanService.parse(response, weekStart: monday, defaultMeal: .lunch, source: "Work cafe",
                                              entries: [], calendar: calendar)
        #expect(meals.first?.options.count == 4)
        let prompt = MealPlanService.prompt(for: .text("Mon: chili"), weekStart: monday, defaultMeal: .lunch, healthLines: [])
        #expect(prompt.contains("options: up to 4,"))
    }
}
