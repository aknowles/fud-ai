import Foundation
import Testing
@testable import calorietracker

/// "I'm hungry, here are my options": usual meal times, when waiting wins, goal flags,
/// ranking, the bridge snack and parsing the AI's answer.
@MainActor
struct FoodSuggestionTests {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func food(_ name: String, calories: Int, protein: Double = 5, fiber: Double? = nil, at date: Date = .now,
                      meal: MealType = .snack, purines: Double = 0, sodium: Double? = nil) -> FoodEntry {
        FoodEntry(name: name, calories: calories, protein: protein, carbs: 20, fat: 5, timestamp: date, source: .manual,
                  mealType: meal, fiber: fiber, supplementalNutrients: ["purines": purines], sodium: sodium)
    }

    private func dinnerHistory() -> [FoodEntry] {
        (1...5).flatMap { day in
            [food("Lunch", calories: 600, at: at(12, 0, daysAgo: day), meal: .lunch),
             food("Dinner", calories: 700, at: at(18, 30, daysAgo: day), meal: .dinner)]
        } + [food("One-off breakfast", calories: 300, at: at(7, 0, daysAgo: 2), meal: .breakfast)]
    }

    // MARK: - Usual meals and waiting

    @Test func nextUsualMealIsLearnedFromLoggedMealTimes() throws {
        let next = try #require(UsualMeal.next(after: at(17, 30), entries: dinnerHistory(), calendar: calendar))

        #expect(next == UsualMeal(mealType: .dinner, minutesAway: 60, typicalCalories: 700))
    }

    @Test func mealsLoggedOnTooFewDaysAndMealsAlreadyPastAreIgnored() {
        #expect(UsualMeal.next(after: at(6, 0), entries: dinnerHistory(), calendar: calendar)?.mealType == .lunch)
        #expect(UsualMeal.next(after: at(20, 0), entries: dinnerHistory(), calendar: calendar) == nil)
    }

    @Test func anHourBeforeDinnerWithLittleLeftWaitingWins() {
        let dinner = UsualMeal(mealType: .dinner, minutesAway: 60, typicalCalories: 700)

        #expect(SuggestionContext(caloriesLeft: 750, nextMeal: dinner, isFasting: false).prefersWaiting)
        #expect(!SuggestionContext(caloriesLeft: 1_500, nextMeal: dinner, isFasting: false).prefersWaiting)
        let later = UsualMeal(mealType: .dinner, minutesAway: 180, typicalCalories: 700)
        #expect(!SuggestionContext(caloriesLeft: 750, nextMeal: later, isFasting: false).prefersWaiting)
        #expect(!SuggestionContext(caloriesLeft: 100, nextMeal: nil, isFasting: false).prefersWaiting)
        #expect(SuggestionContext(caloriesLeft: 2_000, nextMeal: nil, isFasting: true).prefersWaiting)
    }

    // MARK: - Flags and ranking

    @Test func optionsAreFlaggedForEveryGoalTheyWouldBreak() {
        let today = [food("Breakfast", calories: 1_800, purines: 300, sodium: 2_000)]
        let options = [
            SuggestionOption(entry: food("Sardines", calories: 250, purines: 150, sodium: 400), reason: "", tweak: nil),
            SuggestionOption(entry: food("Apple", calories: 95, purines: 2, sodium: 1), reason: "", tweak: nil),
        ]

        let evaluated = SuggestionRanking.evaluate(options, today: today, calorieGoal: 2_000, goals: .defaults,
                                                   profile: .migratedDefault)

        #expect(Set(evaluated[0].flags) == [.calories, .over(.purines), .over(.sodium)])
        #expect(evaluated[0].caloriesAfter == 2_050)
        #expect(evaluated[1].flags.isEmpty)
        #expect(evaluated[1].limitsAfter.map(\.nutrient) == [.purines, .alcohol, .addedSugar, .sodium])
        #expect(evaluated[1].limitsAfter.first?.amount == 302)
    }

    @Test func optionsThatBreakAGoalMoveBehindThoseThatDoNotKeepingTheAIOrder() {
        func option(_ name: String, flagged: Bool) -> SuggestionOption {
            var option = SuggestionOption(entry: food(name, calories: 100), reason: "", tweak: nil)
            option.flags = flagged ? [.over(.purines)] : []
            return option
        }
        let ranked = SuggestionRanking.ranked([option("A", flagged: true), option("B", flagged: false),
                                               option("C", flagged: true), option("D", flagged: false)])

        #expect(ranked.map(\.entry.name) == ["B", "D", "A", "C"])
    }

    @Test func bridgeSnackIsTheSmallSavedFoodWithTheMostProteinAndFiberPerCalorie() {
        let saved = [
            food("Pretzels", calories: 110, protein: 3, fiber: 1),
            food("Greek yogurt", calories: 120, protein: 15),
            food("Big burrito", calories: 900, protein: 40),
        ]

        #expect(SuggestionRanking.bridgeSnack(from: saved)?.name == "Greek yogurt")
        #expect(SuggestionRanking.bridgeSnack(from: [food("Big burrito", calories: 900)]) == nil)
    }

    // MARK: - The AI's answer

    @Test func savedOptionsKeepTheirNutritionAndNewOnesAreParsed() throws {
        let saved = [food("Apple", calories: 95), food("Greek yogurt", calories: 120, protein: 15, purines: 5)]
        let response = """
        ```json
        {"options":[
          {"saved_id":"S2","food":null,"servings":0.5,"tweak":"Half the cup","reason":"Protein, almost no purines."},
          {"saved_id":null,"food":{"name":"Turkey sandwich","emoji":"🥪","serving_size_grams":250,"calories":420,"protein":28,"carbs":45,"fat":12,"sodium":1100,"purines":80,"alcohol":0},"servings":1,"tweak":null,"reason":"High sodium."},
          {"saved_id":"S9","food":null,"reason":"Unknown id is skipped."}
        ],"pick":1,"pick_reason":"Filling.","wait_reason":"Dinner is in an hour.","bridge":null}
        ```
        """

        let (suggestions, aiPickedWait) = try FoodSuggestionService.parse(response, saved: saved, source: .textInput, now: .now)

        #expect(!aiPickedWait)
        #expect(suggestions.options.count == 2)
        let yogurt = suggestions.options[0]
        #expect(yogurt.entry.name == "Greek yogurt")
        #expect(yogurt.entry.calories == 60)
        #expect(yogurt.tweak == "Half the cup")
        let sandwich = suggestions.options[1]
        #expect(sandwich.entry.calories == 420)
        #expect(sandwich.entry.sodium == 1_100)
        #expect(sandwich.entry.supplementalNutrients["purines"] == 80)
        #expect(sandwich.tweak == nil)
        #expect(suggestions.pick == sandwich.id)
        #expect(suggestions.waitReason == "Dinner is in an hour.")
    }

    @Test func aWaitPickHasNoOptionPicked() throws {
        let response = #"{"options":[{"saved_id":"S1","food":null,"reason":"ok"}],"pick":"wait","pick_reason":"","wait_reason":"Dinner soon.","bridge":"A glass of water"}"#

        let (suggestions, aiPickedWait) = try FoodSuggestionService.parse(response, saved: [food("Apple", calories: 95)],
                                                                          source: .textInput, now: .now)

        #expect(aiPickedWait)
        #expect(suggestions.pick == nil)
        #expect(suggestions.bridgeText == "A glass of water")
    }

    @Test func anAnswerWithNoUsableOptionsIsAnError() {
        #expect(throws: (any Error).self) {
            try FoodSuggestionService.parse(#"{"options":[],"pick":"wait"}"#, saved: [], source: .textInput, now: .now)
        }
        #expect(throws: (any Error).self) {
            try FoodSuggestionService.parse("not json", saved: [], source: .textInput, now: .now)
        }
    }

    @Test func thePromptCarriesTheDayTheHealthGoalsAndTheSavedIDs() {
        let context = SuggestionContext(caloriesLeft: 750, nextMeal: UsualMeal(mealType: .dinner, minutesAway: 60, typicalCalories: 700),
                                        isFasting: false)
        let saved = [food("Greek yogurt", calories: 120, protein: 15, purines: 5, sodium: 60)]

        let prompt = FoodSuggestionService.prompt(for: .saved(title: "Work snacks", entries: saved), saved: saved,
                                                  context: context, healthLines: ["## Health goals", "- Gout: favor low-purine choices"],
                                                  now: at(17, 30))

        #expect(prompt.contains("- Calories left today: 750 kcal"))
        #expect(prompt.contains("- Next usual meal: dinner in about 60 minutes, usually about 700 kcal"))
        #expect(prompt.contains("- Gout: favor low-purine choices"))
        #expect(prompt.contains("- S1: Greek yogurt: 120 kcal, protein 15 g, purines 5 mg, sodium 60 mg"))
        #expect(prompt.contains("\"wait\""))
    }
}

/// The foods-to-avoid list and the wider nutrient set reach Suggestions.
@MainActor
struct FoodSuggestionAvoidTests {
    private func option(_ name: String, contains: [String] = [], calories: Int = 300) -> SuggestionOption {
        SuggestionOption(entry: FoodEntry(name: name, calories: calories, protein: 10, carbs: 30, fat: 10, source: .textInput),
                         reason: "", tweak: nil, contains: contains)
    }

    @Test func optionsWithAnAvoidedFoodAreFlaggedFromTheirNameOrTheAIsContainsList() {
        let profile = HealthProfile(entries: [], avoid: AvoidList(celiac: true, custom: ["peanut"]))
        let evaluated = SuggestionRanking.evaluate(
            [option("Turkey sandwich"), option("Pad thai", contains: ["rice noodles", "peanut", "egg"]), option("Chicken rice bowl")],
            today: [], calorieGoal: 2_000, goals: .defaults, profile: profile
        )

        #expect(evaluated[0].flags == [.avoid("gluten (celiac disease)")])
        #expect(evaluated[1].flags == [.avoid("peanut")])
        #expect(evaluated[2].flags.isEmpty)
        #expect(SuggestionRanking.ranked(evaluated).first?.entry.name == "Chicken rice bowl")
    }

    @Test func anAvoidedPickFallsToTheBestSafeOptionOrToWaiting() {
        var bread = option("Bread"); bread.flags = [.avoid("gluten (celiac disease)")]
        var salty = option("Soup"); salty.flags = [.over(.sodium)]
        let safe = option("Salad")

        #expect(SuggestionRanking.safePick(bread.id, in: [safe, salty, bread]) == safe.id)
        #expect(SuggestionRanking.safePick(salty.id, in: [safe, salty, bread]) == salty.id)
        #expect(SuggestionRanking.safePick(bread.id, in: [bread]) == nil)
        #expect(SuggestionRanking.safePick(nil, in: [safe]) == nil)
    }

    @Test func newFoodsKeepTheirContainsListAndTheWiderNutrients() throws {
        let response = #"{"options":[{"saved_id":null,"food":{"name":"Cheese pizza","calories":600,"protein":25,"carbs":70,"fat":22,"saturated_fat":11,"phosphorus":420,"tyramine":2,"contains":["wheat","milk"]},"reason":"ok"}],"pick":0}"#

        let (suggestions, _) = try FoodSuggestionService.parse(response, saved: [], source: .textInput, now: .now)
        let pizza = try #require(suggestions.options.first)

        #expect(pizza.contains == ["wheat", "milk"])
        #expect(pizza.entry.saturatedFat == 11)
        #expect(pizza.entry.supplementalNutrients["phosphorus"] == 420)
    }
}
