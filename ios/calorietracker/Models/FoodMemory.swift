import Foundation
import Observation
import SwiftUI

/// A standing correction to AI food estimates, e.g. "for omelets: use egg whites instead of
/// whole eggs". `match` is a lowercase dish term; empty means it applies to every food.
nonisolated struct FoodMemoryRule: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var match: String
    var instruction: String

    init(id: UUID = UUID(), match: String, instruction: String) {
        self.id = id
        self.match = match.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Food memory: the user's corrections, sent with every food-analysis and Coach request through
/// the AI Provider user context so estimates start from the user's version of a dish.
nonisolated enum FoodMemory {
    static let storageKey = "fork.foodMemory"

    static func rules(from defaults: UserDefaults = .standard) -> [FoodMemoryRule] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([FoodMemoryRule].self, from: data)) ?? []
    }

    /// The prompt section for the rules, or "" when there are none.
    static func promptText(from defaults: UserDefaults = .standard) -> String {
        let rules = rules(from: defaults).filter { !$0.instruction.isEmpty }
        guard !rules.isEmpty else { return "" }
        let lines = rules.map { rule in
            rule.match.isEmpty ? "- Always: \(rule.instruction)" : "- For \(rule.match): \(rule.instruction)"
        }
        return (["Food memory (the user's standing corrections to food estimates; apply each one whenever the food matches, and estimate the corrected ingredients and nutrition):"]
            + lines).joined(separator: "\n")
    }

    /// The instruction for swapping one ingredient for another, e.g. "Use egg whites instead of eggs."
    static func swapInstruction(from original: String, to replacement: String) -> String {
        "Use \(replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) instead of \(original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())."
    }
}

@Observable
final class FoodMemoryStore {
    static let shared = FoodMemoryStore()

    private(set) var rules: [FoodMemoryRule] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = FoodMemory.rules(from: defaults)
    }

    func add(_ rule: FoodMemoryRule) {
        guard !rule.instruction.isEmpty else { return }
        rules.removeAll { $0.match == rule.match && $0.instruction.lowercased() == rule.instruction.lowercased() }
        rules.append(rule)
        save()
    }

    func update(_ rule: FoodMemoryRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func remove(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: FoodMemory.storageKey)
        }
    }
}
