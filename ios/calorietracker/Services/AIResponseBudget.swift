import Foundation

/// Fork: some answers are long by nature. A week of cafe meals with full nutrition runs to
/// several thousand tokens, and the app-wide reply cap (`AIProviderSettings.maxResponseTokens`,
/// 1,024 by default) cuts it off, so the import failed after a compact retry. A caller raises
/// the floor for its own requests only; a higher user setting still wins.
enum AIResponseBudget {
    @TaskLocal static var minimumTokens = 0

    /// A whole week of menu days, each with its options and nutrition.
    static let menuImport = 8_192
    /// A ranked list of Suggestions with nutrition for each.
    static let suggestions = 4_096

    /// Runs `body` with replies allowed at least `tokens` long.
    static func withMinimum<T>(_ tokens: Int, _ body: () async throws -> T) async rethrows -> T {
        try await $minimumTokens.withValue(max(tokens, minimumTokens), operation: body)
    }
}
