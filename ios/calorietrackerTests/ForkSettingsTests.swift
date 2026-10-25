import Foundation
import Testing
@testable import calorietracker

/// This fork sells nothing: with paid features off, every hosted or purchasable option
/// disappears and the AI mode is pinned to BYOK even if an older install stored "hosted".
struct ForkSettingsTests {
    @Test func paidFeaturesAreOff() {
        #expect(ForkSettings.paidFeaturesEnabled == false)
    }

    @Test func onlyBYOKIsOfferedAsAnAIMode() {
        #expect(AIMode.availableCases == [.byok])
    }

    @Test func hostedVoiceProviderIsNotOffered() {
        #expect(!VoiceAssistantProviderChoice.availableCases.contains(.hosted))
        #expect(VoiceAssistantProviderChoice.availableCases.contains(.automatic))
        #expect(VoiceAssistantProviderChoice.availableCases.contains(.gemini))
    }

    @Test func storedHostedModeFallsBackToBYOK() {
        let key = "aiAccessMode"
        let previous = UserDefaults.standard.string(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(AIMode.hosted.rawValue, forKey: key)

        #expect(AIModeSettings.mode == .byok)
        #expect(AIModeSettings.isHosted == false)
    }
}
