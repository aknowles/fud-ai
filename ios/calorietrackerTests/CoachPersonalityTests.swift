import Foundation
import Testing
@testable import calorietracker

/// Coach personalities change tone only, through a prompt section, and suggest real voices.
@MainActor
struct CoachPersonalityTests {
    private func defaults() -> (UserDefaults, String) {
        let suite = "CoachPersonalityTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func standardAndAnEmptyCustomStyleAddNothing() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(CoachStyle.promptLines(defaults).isEmpty)
        defaults.set(CoachPersonality.custom.rawValue, forKey: CoachStyle.personalityKey)
        defaults.set("   ", forKey: CoachStyle.customStyleKey)
        #expect(CoachStyle.promptLines(defaults).isEmpty)
    }

    @Test func aStyleComesWithItsIntensityAndTheSafetyRule() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(CoachPersonality.sassy.rawValue, forKey: CoachStyle.personalityKey)
        defaults.set(CoachIntensity.strong.rawValue, forKey: CoachStyle.intensityKey)

        let lines = CoachStyle.promptLines(defaults)

        #expect(lines.contains("## Personality"))
        #expect(lines.contains { $0.contains("Playfully sassy") && $0.contains("Lean into it fully.") })
        #expect(lines.contains { $0.contains("never shame the user") && $0.contains("drop the persona") })
    }

    @Test func customStylesUseTheUsersWords() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(CoachPersonality.custom.rawValue, forKey: CoachStyle.personalityKey)
        defaults.set("Talk like a laid-back surfer.", forKey: CoachStyle.customStyleKey)

        #expect(CoachStyle.promptLines(defaults).contains { $0.contains("Talk like a laid-back surfer. Apply it clearly.") })
    }

    @Test func everyPersonaHasAStyleAndRealSuggestedVoices() {
        for personality in CoachPersonality.allCases where personality != .standard && personality != .custom {
            #expect(personality.promptStyle != nil, "\(personality)")
            #expect(!personality.suggestedVoices.isEmpty, "\(personality)")
            for (provider, voice) in personality.suggestedVoices {
                #expect(provider.voices.contains(voice), "\(personality): \(voice) is not a \(provider) voice")
            }
        }
    }

    @Test func applyingSuggestedVoicesSetsEachProvider() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = VoiceAssistantSettings(defaults: defaults)

        CoachStyle.applySuggestedVoices(for: .calm, settings: settings)

        #expect(settings.voice(for: .gemini) == "Sulafat")
        #expect(settings.voice(for: .openai) == "sage")
        #expect(settings.voice(for: .xai) == LiveProvider.xai.defaultVoice)
    }
}
