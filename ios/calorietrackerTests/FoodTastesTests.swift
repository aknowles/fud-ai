import Foundation
import Testing
@testable import calorietracker

/// Likes, dislikes and treats: ranking, picks, meal plans, treat room, the store and Coach.
@MainActor
struct FoodTastesTests {
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    private var noon: Date { calendar.date(byAdding: .hour, value: 12, to: today)! }

    private func food(_ name: String, calories: Int = 500, sodium: Double? = nil, daysAgo: Int = 0) -> FoodEntry {
        let time = calendar.date(byAdding: .day, value: -daysAgo, to: noon)!
        return FoodEntry(name: name, calories: calories, protein: 20, carbs: 50, fat: 15,
                         timestamp: time, source: .textInput, mealType: .lunch, sodium: sodium)
    }

    private func option(_ name: String, flags: [SuggestionFlag] = [], contains: [String] = []) -> SuggestionOption {
        var option = SuggestionOption(entry: food(name), reason: "", tweak: nil, contains: contains)
        option.flags = flags
        return option
    }

    @Test func dislikesDropOutAndLikesLeadAmongOptionsThatFit() {
        let tastes = FoodTastes(likes: ["salmon"], dislikes: ["olives"])
        let options = [option("Greek salad", contains: ["olives"]), option("Chicken wrap"),
                       option("Salmon bowl"), option("Salmon pizza", flags: [.calories])]
        let ranked = SuggestionRanking.ranked(options, tastes: tastes)
        #expect(ranked.map(\.entry.name) == ["Salmon bowl", "Chicken wrap", "Salmon pizza"])

        let onlyDisliked = [option("Olive tapenade"), option("Olive bread")]
        #expect(SuggestionRanking.ranked(onlyDisliked, tastes: tastes).count == 2)
    }

    @Test func aLikedOptionThatFitsBeatsAnUnlikedPick() {
        let tastes = FoodTastes(likes: ["salmon"], dislikes: ["olives"])
        let ranked = SuggestionRanking.ranked([option("Chicken wrap"), option("Salmon bowl")], tastes: tastes)
        let wrap = ranked.first { $0.entry.name == "Chicken wrap" }!.id
        let salmon = ranked.first { $0.entry.name == "Salmon bowl" }!.id
        #expect(SuggestionRanking.tastePick(wrap, in: ranked, tastes: tastes) == salmon)
        #expect(SuggestionRanking.tastePick(salmon, in: ranked, tastes: tastes) == salmon)
        // A pick dropped as disliked falls back to the first option.
        #expect(SuggestionRanking.tastePick(UUID(), in: ranked, tastes: tastes) == salmon)
        #expect(SuggestionRanking.tastePick(wrap, in: ranked, tastes: FoodTastes()) == wrap)
    }

    @Test func mealPlanSuggestionsMoveOffDislikesAndOntoLikes() {
        let options = [PlannedOption(entry: food("Mushroom risotto")), PlannedOption(entry: food("Chicken curry")),
                       PlannedOption(entry: food("Salmon teriyaki"))]
        var meal = PlannedMeal(day: today, mealType: .lunch, options: options, suggestedID: options[0].id)
        meal.applyTastes(FoodTastes(dislikes: ["mushroom"]))
        #expect(meal.chosen?.entry.name == "Chicken curry")
        meal.applyTastes(FoodTastes(likes: ["salmon"], dislikes: ["mushroom"]))
        #expect(meal.chosen?.entry.name == "Salmon teriyaki")

        var picked = PlannedMeal(day: today, mealType: .lunch, options: options, chosenID: options[0].id)
        picked.applyTastes(FoodTastes(dislikes: ["mushroom"]))
        #expect(picked.chosen?.entry.name == "Mushroom risotto")
    }

    @Test func swapsNeverOfferADislikedFood() {
        let options = [PlannedOption(entry: food("Pepperoni pizza", sodium: 2_500)), PlannedOption(entry: food("Tuna melt", sodium: 600))]
        let lunch = PlannedMeal(day: today, mealType: .lunch, options: options, chosenID: options[0].id)
        let liked = PlanDaySummary.make(day: today, meals: [lunch], logged: [], calorieGoal: 2_200, goals: .defaults,
                                        profile: HealthProfile(entries: [.dash]))
        #expect(liked.swaps.first?.toName == "Tuna melt")
        let disliked = PlanDaySummary.make(day: today, meals: [lunch], logged: [], calorieGoal: 2_200, goals: .defaults,
                                           profile: HealthProfile(entries: [.dash]), tastes: FoodTastes(dislikes: ["tuna"]))
        #expect(disliked.swaps.isEmpty)
    }

    @Test func aTreatFitsOnlyAfterOnTrackDaysAndWithRoomToday() {
        let cheesecake = food("Cheesecake", calories: 450, sodium: 300)
        let onTrack = [food("Lunch", calories: 1_800, sodium: 1_500, daysAgo: 1), food("Lunch", calories: 1_900, sodium: 1_400, daysAgo: 2)]
        let profile = HealthProfile(entries: [.dash])

        #expect(TreatRoom.fitting([cheesecake], entries: onTrack + [food("Breakfast", calories: 600, sodium: 500)], now: noon,
                                  calorieGoal: 2_200, goals: .defaults, profile: profile).map(\.name) == ["Cheesecake"])
        // No room left today.
        #expect(TreatRoom.fitting([cheesecake], entries: onTrack + [food("Big lunch", calories: 1_900)], now: noon,
                                  calorieGoal: 2_200, goals: .defaults, profile: profile).isEmpty)
        // A recent day over a limit.
        let salty = [food("Lunch", calories: 1_800, sodium: 3_000, daysAgo: 1), onTrack[1]]
        #expect(TreatRoom.fitting([cheesecake], entries: salty, now: noon,
                                  calorieGoal: 2_200, goals: .defaults, profile: profile).isEmpty)
        // Too little history to say.
        #expect(TreatRoom.fitting([cheesecake], entries: [onTrack[0]], now: noon,
                                  calorieGoal: 2_200, goals: .defaults, profile: profile).isEmpty)
    }

    @Test func storeKeepsLikesAndDislikesApartAndTreatsWithoutPhotos() throws {
        let defaults = try #require(UserDefaults(suiteName: "FoodTastesTests-\(UUID())"))
        let store = FoodTastesStore(defaults: defaults)
        store.addLike("  Salmon ")
        store.addLike("salmon")
        store.addDislike("olives")
        store.addDislike("salmon")
        var treat = food("Cheesecake")
        treat.imageFilename = "photo.jpg"
        store.toggleTreat(treat)
        store.setTreatCard(false)

        let reloaded = FoodTastesStore(defaults: defaults).tastes
        #expect(reloaded.likes.isEmpty)
        #expect(reloaded.dislikes == ["olives", "salmon"])
        #expect(reloaded.treats.map(\.name) == ["Cheesecake"])
        #expect(reloaded.treats.first?.imageFilename == nil)
        #expect(!reloaded.treatCard)

        store.toggleTreat(treat)
        #expect(FoodTastesStore(defaults: defaults).tastes.treats.isEmpty)
        #expect(try JSONDecoder().decode(FoodTastes.self, from: Data(#"{"likes":["kale"]}"#.utf8)).treatCard)
    }

    @Test func coachHearsTastesAndWhenATreatFits() {
        let tastes = FoodTastes(likes: ["salmon"], dislikes: ["olives"], treats: [food("Cheesecake", calories: 450)])
        let history = [food("Lunch", calories: 1_800, daysAgo: 1), food("Lunch", calories: 1_800, daysAgo: 2)]
        let lines = HealthContextPrompt.lines(foods: history, goals: .defaults, profile: HealthProfile(), plan: [], symptoms: [],
                                              onHand: [], tastes: tastes, calorieGoal: 2_200, now: noon, calendar: calendar)
        #expect(lines.contains("## Tastes"))
        #expect(lines.contains { $0.hasPrefix("- Likes: salmon.") })
        #expect(lines.contains { $0.hasPrefix("- Dislikes: olives. Never suggest") })
        #expect(lines.contains { $0.hasPrefix("- Treats they enjoy: Cheesecake (450 kcal).") && $0.contains("never as cheating") })
        #expect(lines.contains { $0.hasPrefix("- Room for a treat today: Cheesecake still fits") })
    }
}
