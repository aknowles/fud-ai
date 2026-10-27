import Foundation

/// How Coach (chat and the voice assistant) talks. Tone only: facts, health and medicine
/// guidance and safety rules never change with it.
enum CoachPersonality: String, CaseIterable, Identifiable {
    case standard
    case encouraging
    case straightTalking
    case sassy
    case calm
    case drillSergeant
    case playful
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .encouraging: String(localized: "Encouraging")
        case .straightTalking: String(localized: "Straight-talking")
        case .sassy: String(localized: "Sassy")
        case .calm: String(localized: "Calm")
        case .drillSergeant: String(localized: "Drill sergeant")
        case .playful: String(localized: "Playful and flirty")
        case .custom: String(localized: "Custom")
        }
    }

    /// What it sounds like, for the picker.
    var sample: String {
        switch self {
        case .standard: String(localized: "You have 650 kcal left today; a lean protein and vegetables at dinner fits well.")
        case .encouraging: String(localized: "Look at you, protein in early! One more veggie at dinner and today's a win.")
        case .straightTalking: String(localized: "650 kcal left. Grilled chicken and greens at dinner. Skip the fries.")
        case .sassy: String(localized: "Pizza again? Bold. Let's at least make it the veggie one, champ.")
        case .calm: String(localized: "You're doing fine. There's room for a gentle, simple dinner tonight. No rush.")
        case .drillSergeant: String(localized: "Six-fifty left, recruit. Protein. Vegetables. Water. Move!")
        case .playful: String(localized: "Well hello, protein goal crusher. Save a little room tonight for something delicious and green.")
        case .custom: String(localized: "Your own style, in your words.")
        }
    }

    /// The style instruction for the prompt; nil keeps Coach's built-in tone.
    var promptStyle: String? {
        switch self {
        case .standard:
            nil
        case .encouraging:
            "Warm cheerleader: celebrate every win, frame misses as easy fixes, use lots of positive reinforcement, never guilt."
        case .straightTalking:
            "Direct and no-nonsense: state the facts and the one thing to do; skip pep talk, filler and hedging."
        case .sassy:
            "Playfully sassy and witty: light teasing, dry humor and eye-roll energy about questionable choices, but always kind underneath."
        case .calm:
            "Calm, gentle and mindful: unhurried, reassuring and non-judgmental, paying attention to how the user feels."
        case .drillSergeant:
            "Tough-love drill sergeant: short, punchy commands, high standards and motivational intensity, never cruel."
        case .playful:
            "Smooth, playful and flirtatious charm with a warm, sultry delivery: compliments and gentle teasing, always tasteful and never sexual or explicit."
        case .custom:
            nil
        }
    }

    /// Suggested voices for the live voice assistant, by provider, where one fits.
    var suggestedVoices: [LiveProvider: String] {
        switch self {
        case .standard, .custom: [:]
        case .encouraging: [.gemini: "Puck", .openai: "coral"]
        case .straightTalking: [.gemini: "Kore", .openai: "cedar"]
        case .sassy: [.gemini: "Leda", .openai: "shimmer"]
        case .calm: [.gemini: "Sulafat", .openai: "sage"]
        case .drillSergeant: [.gemini: "Orus", .openai: "ash"]
        case .playful: [.gemini: "Despina", .openai: "ballad"]
        }
    }
}

enum CoachIntensity: Int, CaseIterable, Identifiable {
    case subtle = 1
    case normal = 2
    case strong = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .subtle: String(localized: "Subtle")
        case .normal: String(localized: "Normal")
        case .strong: String(localized: "Strong")
        }
    }
}

/// The user's chosen Coach style and the prompt section built from it.
enum CoachStyle {
    static let personalityKey = "fork.coach.personality"
    static let customStyleKey = "fork.coach.customStyle"
    static let intensityKey = "fork.coach.intensity"

    static func personality(_ defaults: UserDefaults = .standard) -> CoachPersonality {
        defaults.string(forKey: personalityKey).flatMap(CoachPersonality.init) ?? .standard
    }

    static func intensity(_ defaults: UserDefaults = .standard) -> CoachIntensity {
        CoachIntensity(rawValue: defaults.integer(forKey: intensityKey)) ?? .normal
    }

    /// Prompt lines for the chosen style, or none for Standard (Coach's built-in tone).
    static func promptLines(_ defaults: UserDefaults = .standard) -> [String] {
        let personality = personality(defaults)
        let custom = defaults.string(forKey: customStyleKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let style = personality == .custom ? (custom.isEmpty ? nil : custom) : personality.promptStyle else { return [] }
        let strength = switch intensity(defaults) {
        case .subtle: "Apply it lightly; mostly keep a neutral tone."
        case .normal: "Apply it clearly."
        case .strong: "Lean into it fully."
        }
        return [
            "",
            "## Personality",
            "Talk in this style, which replaces the tone described above while keeping the length rules: \(style) \(strength)",
            "Whatever the style: numbers, health conditions, medicines and safety guidance stay accurate and plain; never shame the user about weight, body or eating; if the user seems distressed or mentions disordered eating, drop the persona and respond with care.",
        ]
    }

    /// Sets each provider's live voice to the personality's suggestion, where it has one.
    static func applySuggestedVoices(for personality: CoachPersonality, settings: VoiceAssistantSettings = VoiceAssistantSettings()) {
        for (provider, voice) in personality.suggestedVoices {
            settings.setVoice(voice, for: provider)
        }
    }
}
