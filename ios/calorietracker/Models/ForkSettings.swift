import Foundation

/// Fork-level switches that differ from upstream Fud AI.
///
/// This fork sells nothing: no RevenueCat, no hosted Plus/Pro plans, no credit packs,
/// no tip jar. Everything runs on the user's own keys (BYOK) or on-device. The flag
/// stays as a single constant so the upstream code paths remain intact and mergeable.
enum ForkSettings {
    /// When false, RevenueCat is never configured and every paid or hosted option is hidden.
    static let paidFeaturesEnabled = false
}

extension AIMode {
    /// The modes a user can pick. Hosted needs a RevenueCat subscription, so it is
    /// offered only when paid features are on.
    static var availableCases: [AIMode] {
        ForkSettings.paidFeaturesEnabled ? allCases : [.byok]
    }
}

extension VoiceAssistantProviderChoice {
    /// Provider choices the user can pick; the hosted provider needs a subscription.
    nonisolated static var availableCases: [VoiceAssistantProviderChoice] {
        ForkSettings.paidFeaturesEnabled ? allCases : allCases.filter { $0 != .hosted }
    }
}
