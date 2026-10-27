import Foundation
import Testing
@testable import calorietracker

@MainActor
struct CoachFoodTests {
    private let user = ChatMessage(role: .user, content: "I had a turkey sandwich for lunch. What should I have as a snack?")
    private let coach = ChatMessage(role: .assistant, content: "Try Greek yogurt with berries, or an apple with peanut butter.")

    @Test func thePromptMarksOnlyNewMessages() {
        let prompt = CoachFoodExtractor.prompt(messages: [user, coach], newIDs: [coach.id])
        #expect(prompt.contains("M1 User: I had a turkey sandwich"))
        #expect(prompt.contains("M2 NEW Coach: Try Greek yogurt"))
        #expect(prompt.contains(#""foods""#))
    }

    @Test func parsesFoodsFromNewMessagesOnlyWithoutRepeats() throws {
        let reply = """
        {"foods":[
          {"message":"M2","food":{"name":"Greek yogurt with berries","emoji":"🥣","serving_size_grams":200,"calories":180,"protein":17,"carbs":20,"fat":4}},
          {"message":"M2","food":{"name":"greek yogurt with berries","calories":180,"protein":17,"carbs":20,"fat":4}},
          {"message":"M1","food":{"name":"Turkey sandwich","calories":420,"protein":28,"carbs":40,"fat":14}},
          {"message":"M9","food":{"name":"Ghost","calories":1,"protein":0,"carbs":0,"fat":0}}
        ]}
        """
        let foods = try CoachFoodExtractor.parse(reply, messages: [user, coach], newIDs: [coach.id])
        #expect(foods.map(\.entry.name) == ["Greek yogurt with berries"])
        #expect(foods.first?.messageID == coach.id)
        #expect(foods.first?.entry.calories == 180)
    }

    @Test func theStoreRemembersReadRepliesAndKeepsTheNewestCopy() throws {
        let defaults = try #require(UserDefaults(suiteName: "CoachFoodTests-\(UUID())"))
        let store = CoachFoodStore(defaults: defaults)
        #expect(store.unreadReplies(in: [user, coach]).map(\.id) == [coach.id])

        let older = CoachFood(messageID: coach.id, entry: FoodEntry(name: "Apple", calories: 95, protein: 0, carbs: 25, fat: 0, source: .textInput),
                              foundAt: Date().addingTimeInterval(-60))
        store.record([older], reading: [coach.id])
        let newer = CoachFood(messageID: UUID(), entry: FoodEntry(name: "apple", calories: 100, protein: 0, carbs: 26, fat: 0, source: .textInput),
                              foundAt: Date())
        store.record([newer], reading: [newer.messageID])

        let reloaded = CoachFoodStore(defaults: defaults)
        #expect(reloaded.unreadReplies(in: [user, coach]).isEmpty)
        #expect(reloaded.foods.map(\.entry.calories) == [100])
        #expect(reloaded.hasRead(coach.id))
        reloaded.remove(newer.id)
        #expect(CoachFoodStore(defaults: defaults).foods.isEmpty)
    }

    @Test func oldRepliesAreNotRead() throws {
        let defaults = try #require(UserDefaults(suiteName: "CoachFoodTests-\(UUID())"))
        let old = ChatMessage(role: .assistant, content: "Try oatmeal.", timestamp: Date().addingTimeInterval(-10 * 86_400))
        #expect(CoachFoodStore(defaults: defaults).unreadReplies(in: [old]).isEmpty)
    }

    @Test func fromCoachIsInTheDefaultAddMenu() {
        #expect(AddMenuConfig.forkDefault.groups.first?.methods.contains(.fromCoach) == true)
    }
}
