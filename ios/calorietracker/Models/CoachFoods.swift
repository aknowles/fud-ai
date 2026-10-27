import Foundation
import Observation

/// A food from the Coach chat that the user may want to log: one Coach suggested, or one the
/// user said they ate or plan to eat.
struct CoachFood: Codable, Identifiable {
    var id = UUID()
    var messageID: UUID
    var entry: FoodEntry
    var foundAt: Date
}

/// Reads foods out of chat messages in one AI call, after the fact, so Coach itself needs no
/// food tools and every provider works the same.
enum CoachFoodExtractor {
    static let maxFoods = 12
    static let maxCharactersPerMessage = 1_500

    /// The conversation as numbered lines; only messages in `newIDs` are read for foods.
    static func prompt(messages: [ChatMessage], newIDs: Set<UUID>) -> String {
        var lines = [
            "Below is the user's recent chat with their nutrition coach. List the specific foods and drinks in the messages marked NEW that the user may want to log: ones the coach suggested or recommended, and ones the user said they ate, are eating or plan to eat.",
            "Skip vague categories (\"more vegetables\"), foods the coach advised against, and foods only mentioned in passing. One entry per distinct food, with nutrition for one typical serving as described in the chat.",
            "",
            "## Chat",
        ]
        for (index, message) in messages.enumerated() {
            let marker = newIDs.contains(message.id) ? " NEW" : ""
            let who = message.role == .user ? "User" : "Coach"
            lines.append("M\(index + 1)\(marker) \(who): \(message.content.prefix(maxCharactersPerMessage))")
        }
        lines += [
            "",
            "## Answer",
            "Respond ONLY with JSON: {\"foods\":[{\"message\":\"M1\",\"food\":FOOD}, ...]} where FOOD is \(FoodSuggestionService.foodShape)",
            "- message is the label of the NEW message the food comes from. At most \(maxFoods) foods; {\"foods\":[]} when there are none.",
        ]
        return lines.joined(separator: "\n")
    }

    static func parse(_ text: String, messages: [ChatMessage], newIDs: Set<UUID>, now: Date = Date()) throws -> [CoachFood] {
        guard let data = GeminiService.extractJSON(from: text).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]]
        else { throw CollectionScanService.ScanError.invalidResponse }
        var seen = Set<String>()
        return foods.prefix(maxFoods).compactMap { raw -> CoachFood? in
            guard let label = raw["message"] as? String, label.hasPrefix("M"),
                  let number = Int(label.dropFirst()), messages.indices.contains(number - 1),
                  newIDs.contains(messages[number - 1].id),
                  let food = raw["food"] as? [String: Any],
                  let analysis = FoodSuggestionService.foodAnalysis(from: food),
                  seen.insert(analysis.name.lowercased()).inserted
            else { return nil }
            let entry = VoiceAssistantFoodBuilder.entry(from: analysis, images: [], source: .textInput, servings: 1,
                                                        timestamp: now, mealType: .currentMeal)
            return CoachFood(messageID: messages[number - 1].id, entry: entry, foundAt: now)
        }
    }
}

/// Foods found in the Coach chat, newest first, kept for a few weeks for the + menu's
/// From Coach list. Messages already read are remembered so each is read once.
@Observable
final class CoachFoodStore {
    static let storageKey = "fork.coachFoods"
    static let shared = CoachFoodStore()
    /// Chat this far back is read for foods.
    static let lookbackDays = 7
    /// Foods are kept this long.
    static let keepDays = 30
    static let maxKept = 40

    private struct Stored: Codable {
        var foods: [CoachFood] = []
        var readMessageIDs: [UUID] = []
    }

    private(set) var foods: [CoachFood] = []
    private var readMessageIDs: Set<UUID> = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        foods = stored.foods
        readMessageIDs = Set(stored.readMessageIDs)
    }

    func foods(from messageID: UUID) -> [CoachFood] {
        foods.filter { $0.messageID == messageID }
    }

    func hasRead(_ messageID: UUID) -> Bool { readMessageIDs.contains(messageID) }

    /// Coach replies from the last week not read yet, oldest first.
    func unreadReplies(in messages: [ChatMessage], now: Date = Date(), calendar: Calendar = .current) -> [ChatMessage] {
        let cutoff = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now) ?? now
        return messages.filter { $0.role == .assistant && $0.timestamp >= cutoff && !readMessageIDs.contains($0.id) }
    }

    /// Records the foods found in `messageIDs` (possibly none), newest first without repeats.
    func record(_ found: [CoachFood], reading messageIDs: [UUID], now: Date = Date(), calendar: Calendar = .current) {
        readMessageIDs.formUnion(messageIDs)
        let names = Set(found.map { $0.entry.name.lowercased() })
        foods = found.sorted { $0.foundAt > $1.foundAt } + foods.filter { !names.contains($0.entry.name.lowercased()) }
        let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: now) ?? now
        foods = Array(foods.filter { $0.foundAt >= cutoff }.prefix(Self.maxKept))
        save()
    }

    func remove(_ id: UUID) {
        foods.removeAll { $0.id == id }
        save()
    }

    /// Reads `targets` (with the conversation around them) for foods and records them.
    @discardableResult
    func read(_ targets: [ChatMessage], conversation: [ChatMessage], now: Date = Date()) async throws -> [CoachFood] {
        guard !targets.isEmpty else { return [] }
        let ids = Set(targets.map(\.id))
        // The targets plus the few messages before the earliest, for context.
        let firstIndex = conversation.firstIndex { ids.contains($0.id) } ?? 0
        let lastIndex = conversation.lastIndex { ids.contains($0.id) } ?? conversation.count - 1
        let window = Array(conversation[max(0, firstIndex - 4)...max(lastIndex, firstIndex)].suffix(24))
        let text = try await GeminiService.callAI(prompt: CoachFoodExtractor.prompt(messages: window, newIDs: ids), image: nil)
        let found = try CoachFoodExtractor.parse(text, messages: window, newIDs: ids, now: now)
        record(found, reading: Array(ids), now: now)
        return found
    }

    private func save() {
        let stored = Stored(foods: foods, readMessageIDs: Array(readMessageIDs))
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.storageKey) }
    }
}
