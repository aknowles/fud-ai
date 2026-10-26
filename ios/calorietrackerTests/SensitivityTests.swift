import Foundation
import Testing
@testable import calorietracker

/// Graded food sensitivities: matching, levels, the caffeine cut-off, and how Coach,
/// Suggestions and the profile store see them.
@MainActor
struct SensitivityTests {
    private let calendar = Calendar.current
    private func at(_ hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now)! }

    private func food(_ name: String, caffeine: Double? = nil, at time: Date? = nil) -> FoodEntry {
        FoodEntry(name: name, calories: 300, protein: 10, carbs: 30, fat: 10, timestamp: time ?? at(12), source: .manual,
                  caffeine: caffeine)
    }

    @Test func builtInGroupsMatchWithExemptionsAndLookAlikes() {
        #expect(Sensitivities.tags(for: ["Garlic bread"]) .contains(.fructans))
        #expect(!Sensitivities.tags(for: ["Gluten-free bread"]).contains(.fructans))
        #expect(Sensitivities.tags(for: ["Black bean burrito"]).contains(.gos))
        #expect(Sensitivities.tags(for: ["Spicy chicken curry"]).contains(.reflux))
        #expect(Sensitivities.tags(for: ["Baked potato"]).contains(.nightshades))
        #expect(!Sensitivities.tags(for: ["Sweet potato mash"]).contains(.nightshades))
        #expect(!Sensitivities.tags(for: ["Lactose-free milk"]).contains(.lactose))
        #expect(Sensitivities.tags(for: ["Sugar-free gum"]).contains(.polyols))
        #expect(Sensitivities.tags(for: ["Salami sandwich"]).contains(.histamine))
    }

    @Test func onlyTheUsersSensitivitiesMatchAtTheirLevel() {
        let mine = Sensitivities(levels: ["fructans": .limit, "reflux": .avoid, "nightshades": .note],
                                 custom: [CustomSensitivity(term: "coconut", level: .limit)])

        #expect(mine.matches(for: food("Garlic shrimp with coconut rice")) == [
            .init(label: "fructans", level: .limit), .init(label: "coconut", level: .limit),
        ])
        #expect(mine.matches(for: food("Spicy salsa")) == [.init(label: "reflux triggers", level: .avoid),
                                                           .init(label: "nightshades", level: .note)])
        #expect(mine.matches(for: food("Black bean soup")).isEmpty)
        #expect(mine.matches(for: food("Plain rice"), extraTags: ["onion"]) == [.init(label: "fructans", level: .limit)])
    }

    @Test func caffeineCountsOnlyAfterTheCutOff() {
        let mine = Sensitivities(levels: ["caffeine": .avoid], caffeineCutoffMinutes: 14 * 60)

        #expect(mine.matches(for: food("Latte", at: at(9))).isEmpty)
        #expect(mine.matches(for: food("Latte", at: at(16))) == [.init(label: "caffeine after the cut-off", level: .avoid)])
        #expect(mine.matches(for: food("Mystery soda", caffeine: 40, at: at(17))) == [.init(label: "caffeine after the cut-off", level: .avoid)])
        #expect(mine.matches(for: food("Decaf latte", at: at(16))).isEmpty)

        let anyTime = Sensitivities(levels: ["caffeine": .limit])
        #expect(anyTime.matches(for: food("Espresso", at: at(9))) == [.init(label: "caffeine", level: .limit)])
    }

    @Test func suggestionsRankLimitedFoodsLowerAndNeverPickAvoidedOnes() {
        let profile = HealthProfile(sensitivities: Sensitivities(levels: ["fructans": .limit, "reflux": .avoid]))
        let options = [
            SuggestionOption(entry: food("Spicy wings"), reason: "", tweak: nil),
            SuggestionOption(entry: food("Onion soup"), reason: "", tweak: nil),
            SuggestionOption(entry: food("Grilled salmon"), reason: "", tweak: nil),
        ]

        let ranked = SuggestionRanking.ranked(SuggestionRanking.evaluate(options, today: [], calorieGoal: 2_000,
                                                                         goals: .defaults, profile: profile))

        #expect(ranked.first?.entry.name == "Grilled salmon")
        #expect(ranked.first { $0.entry.name == "Onion soup" }?.flags == [.sensitivity("fructans", .limit)])
        #expect(SuggestionFlag.sensitivity("reflux triggers", .avoid).isHardStop)
        #expect(!SuggestionFlag.sensitivity("fructans", .limit).isHardStop)
    }

    @Test func coachHearsTheSensitivitiesAndTodaysHits() {
        let profile = HealthProfile(sensitivities: Sensitivities(levels: ["fructans": .limit, "histamine": .avoid],
                                                                 custom: [CustomSensitivity(term: "coconut", level: .note)]))

        let lines = HealthContextPrompt.lines(foods: [food("Garlic bread")], goals: .defaults, profile: profile, plan: [], now: at(13))

        #expect(lines.contains("- Food sensitivities (not allergies): avoid histamine; go easy on fructans; note coconut. Weigh them when suggesting food."))
        #expect(lines.contains("- Logged today with a sensitivity: Garlic bread (fructans)."))
    }

    @Test func sensitivitiesPersistAndOldProfilesDecode() throws {
        let suite = "SensitivityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HealthProfileStore(defaults: defaults)
        let mine = Sensitivities(levels: ["gos": .limit], caffeineCutoffMinutes: 840)

        store.setSensitivities(mine)
        #expect(HealthProfileStore(defaults: defaults).profile.sensitivities == mine)

        let old = try JSONDecoder().decode(HealthProfile.self, from: Data(#"{"entries":["gout"]}"#.utf8))
        #expect(old.sensitivityList.isEmpty)
    }
}
