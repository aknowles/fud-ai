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
        #expect(meals[0].options[1].contains == ["egg"])
        #expect(meals[0].options[0].entry.sodium == 1_100)
        #expect(meals[1].mealType == .dinner)
        #expect(calendar.component(.hour, from: meals[1].options[0].entry.timestamp) == 18)
        #expect(throws: (any Error).self) {
            try MealPlanService.parse(#"{"days":[]}"#, weekStart: monday, defaultMeal: .lunch, source: "x", entries: [])
        }
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

        let lines = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(entries: [.dash]), plan: plan, symptoms: [],
                                              now: calendar.date(byAdding: .hour, value: 9, to: today)!, calendar: calendar)

        #expect(lines.contains("- Today, lunch (Work cafe): planned Pepperoni pizza (620 kcal, sodium 1500 mg); other options: Grilled chicken bowl."))
        #expect(lines.contains("- Tomorrow, dinner (Recipe): planned Lentil soup (400 kcal)."))

        let noProfile = HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(), plan: plan, symptoms: [],
                                                  now: calendar.date(byAdding: .hour, value: 9, to: today)!, calendar: calendar)
        #expect(noProfile.contains("## Meal plan"))
        #expect(!noProfile.contains("## Health goals"))
    }
}
