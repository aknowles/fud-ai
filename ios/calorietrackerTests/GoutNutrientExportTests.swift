import Foundation
import Testing
@testable import calorietracker

/// Purines and alcohol have no HealthKit type, so the diary export is their only way out
/// of the app. They get explicit, unit-labeled fields in JSON, CSV and Markdown.
@MainActor
struct GoutNutrientExportTests {
    private let day = Date(timeIntervalSince1970: 1_752_840_000)

    @Test func jsonCarriesPurinesInMilligramsAndAlcoholInGrams() throws {
        let export = try #require(DiaryExporter.build(from: day, to: day, format: .json, entries: [entry()], profile: profile()))
        let root = try #require(JSONSerialization.jsonObject(with: export.data) as? [String: Any])
        let item = try #require(firstItem(in: root))

        #expect(item["purines_mg"] as? Double == 345.5)
        #expect(item["alcohol_g"] as? Double == 14)
    }

    @Test func jsonLeavesTheFieldsOutWhenAnEntryHasNoValues() throws {
        let plain = FoodEntry(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, timestamp: day, source: .manual)
        let export = try #require(DiaryExporter.build(from: day, to: day, format: .json, entries: [plain], profile: profile()))
        let root = try #require(JSONSerialization.jsonObject(with: export.data) as? [String: Any])
        let item = try #require(firstItem(in: root))

        #expect(item["purines_mg"] == nil)
        #expect(item["alcohol_g"] == nil)
    }

    @Test func csvAppendsTheTwoColumnsAfterTheExistingOnes() throws {
        let export = try #require(DiaryExporter.build(from: day, to: day, format: .csv, entries: [entry()], profile: profile()))
        let lines = String(decoding: export.data, as: UTF8.self).split(separator: "\n").map(String.init)
        let headers = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let values = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)

        #expect(headers.suffix(2) == ["purines_mg", "alcohol_g"])
        #expect(headers.count == values.count)
        #expect(values[headers.count - 2] == "345.5")
        #expect(values[headers.count - 1] == "14.0")
        // Water rows keep the same width as food rows.
        for line in lines.dropFirst() {
            #expect(line.split(separator: ",", omittingEmptySubsequences: false).count == headers.count, "\(line)")
        }
    }

    @Test func markdownLabelsTheUnits() throws {
        let export = try #require(DiaryExporter.build(from: day, to: day, format: .markdown, entries: [entry()], profile: profile()))
        let markdown = String(decoding: export.data, as: UTF8.self)

        #expect(markdown.contains("| Purines (mg) | Alcohol (g) |"))
        #expect(markdown.contains("| 345.5 | 14.0 |"))
    }

    private func entry() -> FoodEntry {
        FoodEntry(
            name: "Sardines and a beer",
            calories: 350,
            protein: 25,
            carbs: 12,
            fat: 11,
            timestamp: day,
            source: .snapFood,
            supplementalNutrients: ["purines": 345.46, "alcohol": 14],
            servingSizeGrams: 450
        )
    }

    private func firstItem(in root: [String: Any]) -> [String: Any]? {
        let days = root["days"] as? [[String: Any]]
        let meals = days?.first?["meals"] as? [[String: Any]]
        let items = meals?.first?["items"] as? [[String: Any]]
        return items?.first
    }

    private func profile() -> UserProfile {
        UserProfile(
            name: "Exporter",
            gender: .male,
            birthday: Date(timeIntervalSince1970: 0),
            heightCm: 175,
            weightKg: 70,
            activityLevel: .moderate,
            goal: .maintain,
            bodyFatPercentage: nil,
            goalBodyFatPercentage: nil,
            useBodyFatInBMR: nil,
            weeklyChangeKg: nil,
            goalWeightKg: nil,
            customCalories: 2_000,
            customProtein: 120,
            customFat: 60,
            customCarbs: 200,
            autoBalanceMacro: nil
        )
    }
}
