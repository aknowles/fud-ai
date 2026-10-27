import Foundation
import Observation

/// What the user enjoys, never wants, and treats worth planning for. Taste, not health: dislikes
/// are quietly left out of picks without a warning, and likes win among options that fit.
struct FoodTastes: Codable {
    /// Terms matched by whole word, e.g. "salmon", "spicy", "greek yogurt".
    var likes: [String] = []
    var dislikes: [String] = []
    /// Saved foods the user enjoys as treats, without photos.
    var treats: [FoodEntry] = []
    /// Show the Home card when a treat fits.
    var treatCard = true

    init(likes: [String] = [], dislikes: [String] = [], treats: [FoodEntry] = [], treatCard: Bool = true) {
        self.likes = likes
        self.dislikes = dislikes
        self.treats = treats
        self.treatCard = treatCard
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        likes = try container.decodeIfPresent([String].self, forKey: .likes) ?? []
        dislikes = try container.decodeIfPresent([String].self, forKey: .dislikes) ?? []
        treats = try container.decodeIfPresent([FoodEntry].self, forKey: .treats) ?? []
        treatCard = try container.decodeIfPresent(Bool.self, forKey: .treatCard) ?? true
    }

    var isEmpty: Bool { likes.isEmpty && dislikes.isEmpty && treats.isEmpty }

    /// The liked terms `entry` (and the AI's `contains` list) matches.
    func likedTerms(in entry: FoodEntry, contains: [String] = []) -> [String] {
        Self.matches(likes, entry: entry, contains: contains)
    }

    func dislikedTerms(in entry: FoodEntry, contains: [String] = []) -> [String] {
        Self.matches(dislikes, entry: entry, contains: contains)
    }

    func isDisliked(_ entry: FoodEntry, contains: [String] = []) -> Bool {
        !dislikedTerms(in: entry, contains: contains).isEmpty
    }

    func isTreat(_ entry: FoodEntry) -> Bool {
        treats.contains { $0.favoriteKey == entry.favoriteKey }
    }

    /// Whole-word matches on the name, ingredients and product details, as the avoid list does.
    private static func matches(_ terms: [String], entry: FoodEntry, contains: [String]) -> [String] {
        guard !terms.isEmpty else { return [] }
        let texts = [entry.name] + entry.ingredients.map(\.name) + [entry.productMetadata?.ingredientsText].compactMap { $0 }
        return AvoidList(custom: terms).matches(texts: texts, allergens: contains)
    }

    /// A trimmed, lowercased term, or nil when it is empty or already listed.
    static func cleaned(_ term: String, existing: [String]) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !existing.contains(trimmed) else { return nil }
        return trimmed
    }
}

/// When a treat fits: the last few logged days were inside the calorie goal and every limit,
/// and today still has room for the treat under all of them, with no avoid-list, medicine or
/// sensitivity clash. Based only on the numbers; nothing is "earned".
enum TreatRoom {
    /// Recent logged days looked at, at most, within the last week.
    static let recentDays = 3
    /// A recent day may run this far over the calorie goal and still count as on track.
    static let calorieSlack = 1.1

    static func recentDaysOnTrack(
        entries: [FoodEntry],
        before now: Date,
        calorieGoal: Int,
        goals: OptionalNutrientGoals,
        profile: HealthProfile,
        calendar: Calendar = .current
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let days = (1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .map { day in entries.filter { calendar.isDate($0.timestamp, inSameDayAs: day) } }
            .filter { !$0.isEmpty }
            .prefix(recentDays)
        guard days.count >= 2 else { return false }
        let limits = SuggestionRanking.orderedLimits(in: profile)
        return days.allSatisfy { day in
            let calories = day.reduce(0) { $0 + $1.calories }
            if calorieGoal > 0, Double(calories) > Double(calorieGoal) * calorieSlack { return false }
            return limits.allSatisfy { nutrient in
                let goal = goals.goal(for: nutrient)
                return goal <= 0 || day.total(of: nutrient) <= Double(goal)
            }
        }
    }

    /// The treats that fit today, in the user's order; none unless recent days were on track.
    static func fitting(
        _ treats: [FoodEntry],
        entries: [FoodEntry],
        now: Date,
        calorieGoal: Int,
        goals: OptionalNutrientGoals,
        profile: HealthProfile,
        calendar: Calendar = .current
    ) -> [FoodEntry] {
        guard !treats.isEmpty,
              recentDaysOnTrack(entries: entries, before: now, calorieGoal: calorieGoal, goals: goals,
                                profile: profile, calendar: calendar)
        else { return [] }
        let today = entries.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let options = treats.map { SuggestionOption(entry: $0, reason: "", tweak: nil) }
        return SuggestionRanking.evaluate(options, today: today, calorieGoal: calorieGoal, goals: goals, profile: profile)
            .filter(\.flags.isEmpty)
            .map(\.entry)
    }
}

extension SuggestionRanking {
    /// Disliked options are dropped (unless every option is disliked), then options that break
    /// no goal come first with liked ones leading, then the rest, each in the AI's order.
    static func ranked(_ options: [SuggestionOption], tastes: FoodTastes) -> [SuggestionOption] {
        let kept = options.filter { !tastes.isDisliked($0.entry, contains: $0.contains) }
        let pool = kept.isEmpty ? options : kept
        let clean = pool.filter { $0.flags.isEmpty }
        let liked = clean.filter { !tastes.likedTerms(in: $0.entry, contains: $0.contains).isEmpty }
        let likedIDs = Set(liked.map(\.id))
        return liked + clean.filter { !likedIDs.contains($0.id) } + pool.filter { !$0.flags.isEmpty }
    }

    /// The AI's pick unless it was dropped as disliked, or a liked option that breaks no goal
    /// exists and the pick is not liked; then the first option.
    static func tastePick(_ pick: SuggestionOption.ID?, in ranked: [SuggestionOption], tastes: FoodTastes) -> SuggestionOption.ID? {
        guard let pick else { return nil }
        guard let picked = ranked.first(where: { $0.id == pick }) else { return ranked.first?.id }
        let pickLiked = !tastes.likedTerms(in: picked.entry, contains: picked.contains).isEmpty
        if let first = ranked.first, first.flags.isEmpty, !pickLiked,
           !tastes.likedTerms(in: first.entry, contains: first.contains).isEmpty {
            return first.id
        }
        return pick
    }
}

extension PlannedMeal {
    /// Moves the AI's suggestion off a disliked option, onto a liked one where one exists.
    mutating func applyTastes(_ tastes: FoodTastes) {
        guard chosenID == nil, !tastes.isEmpty else { return }
        let kept = options.filter { !tastes.isDisliked($0.entry, contains: $0.contains) }
        guard !kept.isEmpty else { return }
        let liked = kept.first { !tastes.likedTerms(in: $0.entry, contains: $0.contains).isEmpty }
        if let current = options.first(where: { $0.id == suggestedID }),
           !tastes.isDisliked(current.entry, contains: current.contains),
           liked == nil || !tastes.likedTerms(in: current.entry, contains: current.contains).isEmpty {
            return
        }
        suggestedID = (liked ?? kept.first)?.id
    }
}

@Observable
final class FoodTastesStore {
    static let storageKey = "fork.foodTastes"
    static let shared = FoodTastesStore()

    private(set) var tastes = FoodTastes()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        tastes = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(FoodTastes.self, from: $0) } ?? FoodTastes()
    }

    func addLike(_ term: String) {
        guard let term = FoodTastes.cleaned(term, existing: tastes.likes) else { return }
        tastes.dislikes.removeAll { $0 == term }
        tastes.likes.append(term)
        save()
    }

    func addDislike(_ term: String) {
        guard let term = FoodTastes.cleaned(term, existing: tastes.dislikes) else { return }
        tastes.likes.removeAll { $0 == term }
        tastes.dislikes.append(term)
        save()
    }

    func removeLikes(at offsets: IndexSet) {
        tastes.likes = tastes.likes.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save()
    }

    func removeDislikes(at offsets: IndexSet) {
        tastes.dislikes = tastes.dislikes.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save()
    }

    /// Adds a photo-free copy of `entry` as a treat, or removes it if it is one already.
    func toggleTreat(_ entry: FoodEntry) {
        if let index = tastes.treats.firstIndex(where: { $0.favoriteKey == entry.favoriteKey }) {
            tastes.treats.remove(at: index)
        } else {
            tastes.treats.append(FoodCollectionStore.template(from: entry))
        }
        save()
    }

    func removeTreats(at offsets: IndexSet) {
        tastes.treats = tastes.treats.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        save()
    }

    func setTreatCard(_ isOn: Bool) {
        tastes.treatCard = isOn
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tastes) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
