import Foundation
import Observation

enum SymptomKind: String, Codable, CaseIterable, Identifiable {
    case bloating, gas, diarrhea, constipation, stomachPain, heartburn, nausea
    case headache, migraine, rash, goutFlare, fatigue, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bloating: String(localized: "Bloating")
        case .gas: String(localized: "Gas")
        case .diarrhea: String(localized: "Diarrhea")
        case .constipation: String(localized: "Constipation")
        case .stomachPain: String(localized: "Stomach pain")
        case .heartburn: String(localized: "Heartburn or reflux")
        case .nausea: String(localized: "Nausea")
        case .headache: String(localized: "Headache")
        case .migraine: String(localized: "Migraine")
        case .rash: String(localized: "Rash or hives")
        case .goutFlare: String(localized: "Gout flare")
        case .fatigue: String(localized: "Fatigue")
        case .other: String(localized: "Other")
        }
    }

    var promptName: String {
        switch self {
        case .stomachPain: "stomach pain"
        case .heartburn: "heartburn"
        case .goutFlare: "gout flare"
        case .rash: "rash or hives"
        default: rawValue
        }
    }

    /// How far back food can plausibly matter for this symptom.
    var lookbackHours: Int {
        switch self {
        case .heartburn: 4
        case .rash: 6
        case .bloating, .gas, .stomachPain, .nausea, .fatigue: 12
        case .diarrhea, .constipation, .headache, .migraine, .other: 24
        case .goutFlare: 48
        }
    }
}

struct Symptom: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var kind: SymptomKind
    /// The user's own name when `kind` is `.other`.
    var customName: String?
    /// 1 mild, 2 moderate, 3 severe.
    var severity: Int = 2
    var note: String?

    var name: String { kind == .other ? (customName ?? kind.displayName) : kind.displayName }
    /// Symptoms of the same kind and name are analyzed together.
    var groupKey: String { kind == .other ? "other:" + (customName ?? "").lowercased() : kind.rawValue }
}

/// Something about the food eaten before a symptom.
enum TriggerFeature: Hashable {
    case sensitivity(SensitivityKind)
    case lateMeal
    case alcohol
    case highPurines
    case food(String)

    var label: String {
        switch self {
        case .sensitivity(let kind): kind.label
        case .lateMeal: "late meals (after 8 PM)"
        case .alcohol: "alcohol"
        case .highPurines: "high-purine meals"
        case .food(let name): name
        }
    }

    static let lateMealHour = 20
    static let highPurineMilligrams: Double = 150

    static func features(of entry: FoodEntry, calendar: Calendar = .current) -> Set<TriggerFeature> {
        let texts = [entry.name] + entry.ingredients.map(\.name)
        var found = Set(Sensitivities.tags(for: texts).map(TriggerFeature.sensitivity))
        if calendar.component(.hour, from: entry.timestamp) >= lateMealHour { found.insert(.lateMeal) }
        if entry.foodFlags.contains(.alcohol) { found.insert(.alcohol) }
        if (entry.amount(of: .purines) ?? 0) >= highPurineMilligrams { found.insert(.highPurines) }
        found.insert(.food(entry.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)))
        return found
    }
}

/// A feature that shows up before a symptom much more often than at other times.
struct TriggerFinding: Equatable {
    let feature: TriggerFeature
    let symptomKey: String
    let symptomName: String
    let hits: Int
    let episodes: Int
    /// Share of ordinary windows of the same length that contained the feature.
    let baseRate: Double

    var rate: Double { Double(hits) / Double(max(episodes, 1)) }

    var evidence: String {
        String(localized: "Before \(hits) of \(episodes) \(symptomName.lowercased()) episodes, vs \(Int((baseRate * 100).rounded()))% of other times")
    }
}

enum TriggerAnalysis {
    static let minimumEpisodes = 3
    static let minimumRate = 0.6
    static let minimumLift = 0.3
    /// Hours of the day at which ordinary windows end, for the base rate.
    static let baselineHours = [9, 13, 17, 21]

    static func findings(symptoms: [Symptom], entries: [FoodEntry], calendar: Calendar = .current) -> [TriggerFinding] {
        let features = entries.map { ($0.timestamp, TriggerFeature.features(of: $0, calendar: calendar)) }
        func present(in start: Date, _ end: Date) -> Set<TriggerFeature> {
            features.filter { $0.0 >= start && $0.0 < end }.reduce(into: Set()) { $0.formUnion($1.1) }
        }
        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0.timestamp) }).sorted()

        var results: [TriggerFinding] = []
        for (key, episodes) in Dictionary(grouping: symptoms, by: \.groupKey) where episodes.count >= minimumEpisodes {
            let hours = episodes[0].kind.lookbackHours
            let window = TimeInterval(hours * 3600)
            var hits: [TriggerFeature: Int] = [:]
            for episode in episodes {
                for feature in present(in: episode.date.addingTimeInterval(-window), episode.date) { hits[feature, default: 0] += 1 }
            }
            let episodeDates = episodes.map(\.date)
            let baseline = loggedDays.flatMap { day in
                baselineHours.compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
            }.filter { end in !episodeDates.contains { abs($0.timeIntervalSince(end)) < window } }
            let baselineSets = baseline.map { present(in: $0.addingTimeInterval(-window), $0) }

            for (feature, count) in hits where count >= minimumEpisodes {
                let base = baselineSets.isEmpty ? 0 : Double(baselineSets.filter { $0.contains(feature) }.count) / Double(baselineSets.count)
                let finding = TriggerFinding(feature: feature, symptomKey: key, symptomName: episodes[0].name,
                                             hits: count, episodes: episodes.count, baseRate: base)
                if finding.rate >= minimumRate, finding.rate - base >= minimumLift { results.append(finding) }
            }
        }
        return results.sorted { ($0.rate - $0.baseRate, $0.hits) > ($1.rate - $1.baseRate, $1.hits) }
    }
}

@Observable
final class SymptomStore {
    static let storageKey = "fork.symptoms"
    static let shared = SymptomStore()
    static let keepDays = 365

    private(set) var symptoms: [Symptom] = []
    private let blob: PersistedBlobGuard

    init(defaults: UserDefaults = .standard, corruptBackupDirectory: URL? = nil) {
        blob = PersistedBlobGuard(defaults: defaults, key: Self.storageKey, backupDirectory: corruptBackupDirectory)
        reload()
    }

    func reload(now: Date = Date()) {
        switch blob.loadList(Symptom.self) {
        case .missing: symptoms = []
        case .decoded(let decoded, _):
            let cutoff = now.addingTimeInterval(-TimeInterval(Self.keepDays) * 86_400)
            symptoms = decoded.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
        case .corrupt: break
        }
    }

    func add(_ symptom: Symptom) {
        guard !blob.isWriteBlocked else { return }
        symptoms.append(symptom)
        symptoms.sort { $0.date > $1.date }
        blob.save(symptoms)
    }

    func remove(_ id: UUID) {
        guard !blob.isWriteBlocked else { return }
        symptoms.removeAll { $0.id == id }
        blob.save(symptoms)
    }
}
