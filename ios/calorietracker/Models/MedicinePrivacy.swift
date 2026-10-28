import Foundation
import LocalAuthentication
import Observation
import UIKit

/// The optional Face ID or passcode lock on the Medicines screen. While it is on, Home,
/// Suggestions and meal plans say "your medicine" instead of the name. Unlocking lasts until
/// the app goes to the background.
@Observable
final class MedicineLock {
    static let lockedKey = "fork.medicines.locked"
    static let shared = MedicineLock()

    private(set) var isLocked: Bool
    /// Unlocked for this visit to the app.
    private(set) var isUnlocked = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLocked = defaults.bool(forKey: Self.lockedKey)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isUnlocked = false }
        }
    }

    /// Names are hidden outside the Medicines screen whenever the lock is on.
    var hidesNames: Bool { isLocked }
    /// The Medicines screen needs unlocking first.
    var needsUnlock: Bool { isLocked && !isUnlocked }

    /// Can this device ask for Face ID, Touch ID or the passcode?
    var canAuthenticate: Bool {
        if Self.skipsAuthentication { return true }
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    @discardableResult
    func unlock() async -> Bool {
        guard await authenticate(reason: String(localized: "Unlock your medicines")) else { return false }
        isUnlocked = true
        return true
    }

    /// Turning the lock on or off both need the owner.
    @discardableResult
    func setLocked(_ locked: Bool) async -> Bool {
        guard await authenticate(reason: locked ? String(localized: "Lock your medicines") : String(localized: "Turn off the medicines lock"))
        else { return false }
        isLocked = locked
        isUnlocked = true
        defaults.set(locked, forKey: Self.lockedKey)
        return true
    }

    private func authenticate(reason: String) async -> Bool {
        if Self.skipsAuthentication { return true }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// UI tests on the simulator have no Face ID; Debug UI-testing launches skip the prompt.
    private static var skipsAuthentication: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }
}

/// What medicine names show and what the AI is told.
enum MedicinePrivacy {
    static let shareNamesKey = "fork.medicines.shareNamesWithAI"

    /// Coach, Suggestions and menu import get medicine names unless the user turns this off;
    /// with it off they get only the food rules.
    static var sharesNamesWithAI: Bool {
        UserDefaults.standard.object(forKey: shareNamesKey) as? Bool ?? true
    }

    /// The name to show outside the Medicines screen.
    static func visibleName(_ kind: HealthEntryKind) -> String {
        kind.isMedicine && MedicineLock.shared.hidesNames ? String(localized: "Your medicine") : kind.displayName
    }

    /// The dose name to show outside the Medicines screen, lowercase, e.g. "antibiotic".
    static func visibleDoseName(_ kind: HealthEntryKind) -> String {
        kind.isMedicine && MedicineLock.shared.hidesNames ? String(localized: "medicine") : kind.doseName
    }

    /// A rule's source as shown in conflicts: medicine names hidden while locked.
    static func visibleSource(_ source: String) -> String {
        guard MedicineLock.shared.hidesNames,
              HealthEntryKind.allCases.contains(where: { $0.isMedicine && $0.displayName == source })
        else { return source }
        return String(localized: "Your medicine")
    }

    /// Prompt lines with every medicine name (and the other drug names in its display name)
    /// replaced by "Medicine 1", "Medicine 2", in the order of `medicines`.
    static func anonymized(_ lines: [String], medicines: [HealthEntryKind]) -> [String] {
        var replacements: [(String, String)] = []
        for (index, kind) in medicines.enumerated() {
            let label = "Medicine \(index + 1)"
            replacements.append((kind.displayName, label))
            if kind.doseName != kind.displayName { replacements.append((kind.doseName, label)) }
        }
        // Longest first, so "Simvastatin or lovastatin" goes before any shorter overlap.
        replacements.sort { $0.0.count > $1.0.count }
        return lines.map { line in
            replacements.reduce(line) { text, pair in
                text.replacingOccurrences(of: pair.0, with: pair.1, options: [.caseInsensitive])
            }
        }
    }
}

extension HealthEntryKind {
    /// The medicine's food guidance without naming it or any other drug, for when the user
    /// keeps medicine names from the AI. Nil for conditions.
    var namelessGuidance: String? {
        switch self {
        case .prednisone:
            "takes a medicine that raises blood sugar, appetite, salt and water retention and blood pressure, and thins bones. Keep sodium and added sugar down, keep calcium and vitamin D up, and take it with food."
        case .colchicine, .grapefruitStatin:
            "takes a medicine that grapefruit and grapefruit juice can raise to unsafe levels; never suggest them."
        case .allopurinol:
            "takes a medicine that calls for plenty of fluids through the day."
        case .otherStatin:
            "takes a cholesterol medicine without a grapefruit interaction; heart-healthy eating still helps."
        case .potassiumRaising:
            "takes a medicine that raises blood potassium. Do not push high-potassium foods beyond their goal, and never suggest potassium-chloride salt substitutes or potassium supplements."
        case .metformin:
            "takes a medicine that calls for low alcohol and can lower vitamin B12 over time, so B12 foods (meat, fish, eggs, dairy, fortified cereal) help."
        case .glp1:
            "takes a medicine that slows digestion and lowers appetite: suggest smaller meals, lower-fat choices, protein first to keep muscle, and enough fluids."
        case .maoi:
            "takes a medicine that reacts dangerously with high-tyramine foods (aged cheese, cured or fermented meats, soy sauce, miso, sauerkraut, kimchi, tap beer, yeast extract, overripe or spoiled foods); never suggest them."
        case .warfarin:
            "takes a medicine that needs a steady amount of vitamin K from day to day, not avoiding greens. Warn about big swings in greens. Keep alcohol low and avoid large amounts of cranberry juice."
        case .metronidazole:
            "takes a medicine that rules out all alcohol, including foods and sauces cooked with wine or beer and kombucha, during the course and for 3 days after it ends; never suggest them."
        case .quinoloneTetracycline:
            "takes a medicine that dairy, calcium, iron, magnesium and zinc (including antacids, supplements and fortified foods) bind, so keep them out of the window around each dose listed below."
        case .levothyroxine:
            "takes a medicine that needs an empty stomach: nothing to eat for 30 minutes after a dose, no coffee for an hour, and calcium, iron and soy kept 4 hours away, as listed below."
        case .gout, .dash, .diabetes, .heartHealth, .kidneyDisease, .kidneyStones:
            nil
        }
    }
}
