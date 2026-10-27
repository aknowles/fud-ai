import Foundation
import UIKit

/// Reads a photo of what is on hand somewhere (a snack drawer, office pantry, vending machine,
/// fridge or shelf) into foods with nutrition, for adding to a collection.
enum CollectionScanService {
    /// Foods accepted from one photo, at most.
    static let maxItems = 20

    enum ScanError: Error { case invalidResponse, noFoods }

    static func scan(_ image: UIImage, now: Date = Date()) async throws -> [FoodEntry] {
        let text = try await GeminiService.callAI(prompt: prompt, image: image)
        return try parse(text, now: now)
    }

    static var prompt: String {
        [
            "This photo shows foods available somewhere the user goes often, such as a snack drawer, office pantry, vending machine, fridge or shelf.",
            "List each distinct food or drink you can identify, once per product (not once per unit), with nutrition for one typical serving as eaten: one bar, one bag, one piece of fruit, one can or bottle.",
            "Use brand names and nutrition labels when you can read them. Skip anything you can't identify.",
            "Answer with JSON only, in this shape: {\"foods\":[FOOD, ...]} where each FOOD is \(FoodSuggestionService.foodShape)",
            "- At most \(maxItems) foods, the most clearly visible first.",
        ].joined(separator: "\n")
    }

    static func parse(_ text: String, now: Date = Date()) throws -> [FoodEntry] {
        guard let data = GeminiService.extractJSON(from: text).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]]
        else { throw ScanError.invalidResponse }
        var seen = Set<String>()
        let entries = foods.compactMap { FoodSuggestionService.foodAnalysis(from: $0) }
            .filter { seen.insert($0.name.lowercased()).inserted }
            .prefix(maxItems)
            .map { analysis in
                VoiceAssistantFoodBuilder.entry(from: analysis, images: [], source: .snapFood, servings: 1,
                                                timestamp: now, mealType: .snack)
            }
        guard !entries.isEmpty else { throw ScanError.noFoods }
        return Array(entries)
    }
}
