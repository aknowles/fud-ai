import Foundation
import Testing
@testable import calorietracker

@MainActor
struct MedicinePrivacyTests {
    private let medicines = HealthEntryKind.allCases.filter(\.isMedicine)

    /// Every drug name the medicine entries and their guidance mention.
    private let drugWords = [
        "prednisone", "corticosteroid", "colchicine", "allopurinol", "simvastatin", "lovastatin", "rosuvastatin",
        "pravastatin", "statin", "ace inhibitor", "arb", "spironolactone", "metformin", "glp-1", "semaglutide",
        "tirzepatide", "maoi", "linezolid", "warfarin", "apixaban", "rivaroxaban", "metronidazole", "tinidazole",
        "ciprofloxacin", "levofloxacin", "doxycycline", "minocycline", "antibiotic", "levothyroxine",
    ]

    private func lines(share: Bool) -> [String] {
        HealthContextPrompt.lines(foods: [], goals: .defaults, profile: HealthProfile(entries: [.gout] + medicines),
                                  plan: [], symptoms: [], onHand: [], tastes: FoodTastes(), calorieGoal: 2_000,
                                  activityBonus: 0, shareMedicineNames: share)
    }

    @Test func everyMedicineHasNameFreeGuidanceAndConditionsDoNot() {
        for kind in HealthEntryKind.allCases {
            #expect((kind.namelessGuidance != nil) == kind.isMedicine, "\(kind)")
        }
    }

    @Test func withNamesOffTheAISeesNoMedicineOrDrugName() {
        let text = lines(share: false).joined(separator: "\n").lowercased()
        for word in drugWords {
            #expect(text.range(of: "\\b\(word)\\b", options: .regularExpression) == nil, "Leaked \(word)")
        }
        for kind in medicines {
            #expect(!text.contains(kind.displayName.lowercased()), "Leaked \(kind.displayName)")
        }
        #expect(text.contains("medicine 1: takes a medicine that raises blood sugar"))
        #expect(text.contains("never guess which drug they are"))
        // Conditions keep their names.
        #expect(text.contains("gout:"))
    }

    @Test func withNamesOnTheAISeesThemAsBefore() {
        let text = lines(share: true).joined(separator: "\n").lowercased()
        #expect(text.contains("takes warfarin"))
        #expect(!text.contains("medicine 1"))
    }

    @Test func anonymizingReplacesDisplayAndDoseNames() {
        let out = MedicinePrivacy.anonymized(
            ["- Warfarin course: today.", "- Ciprofloxacin, levofloxacin, doxycycline or minocycline doses at 8:00.", "antibiotic window"],
            medicines: [.warfarin, .quinoloneTetracycline]
        )
        #expect(out == ["- Medicine 1 course: today.", "- Medicine 2 doses at 8:00.", "Medicine 2 window"])
    }

    @Test func theLockStartsOffAndNamesShowWhenUnlocked() throws {
        let defaults = try #require(UserDefaults(suiteName: "MedicinePrivacyTests-\(UUID())"))
        let lock = MedicineLock(defaults: defaults)
        #expect(!lock.isLocked)
        #expect(!lock.hidesNames)
        #expect(!lock.needsUnlock)
        defaults.set(true, forKey: MedicineLock.lockedKey)
        let locked = MedicineLock(defaults: defaults)
        #expect(locked.hidesNames)
        #expect(locked.needsUnlock)
    }
}
