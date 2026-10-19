import SwiftUI
import HealthKit

/// Logic behind onboarding's welcome-back screen for people who used Fud AI
/// before (a reinstall or a data wipe).
enum ReturningUser {
    /// Set just before a welcome-back iCloud restore and read once by the
    /// app's onboarding-completion hook, so the restored settings are kept
    /// instead of being overwritten with new-install defaults.
    static var onboardingCompletedByRestore = false

    /// Read once per launch: a BYOK key left in the Keychain by an earlier install.
    private static let launchHadSavedAPIKey: Bool = AIProvider.allCases.contains {
        $0.requiresAPIKey && AIProviderSettings.apiKey(for: $0) != nil
    }

    /// Whether onboarding opens on the welcome-back screen. Test launches never
    /// read the Keychain; they ask for the screen with `--ui-testing-returning`.
    static var opensWelcomeBack: Bool {
        opensWelcomeBack(
            isRunningTests: SimulatorTestEnvironment.isRunningTests,
            forcedByTest: SimulatorTestEnvironment.forcesReturningUserWelcome,
            hasSavedAPIKey: { launchHadSavedAPIKey }
        )
    }

    static func opensWelcomeBack(isRunningTests: Bool, forcedByTest: Bool, hasSavedAPIKey: () -> Bool) -> Bool {
        isRunningTests ? forcedByTest : hasSavedAPIKey()
    }

    // MARK: - Apple Health import

    /// Profile values read back from Apple Health, before clamping to the wizard's wheels.
    struct HealthPrefill: Equatable {
        var gender: Gender?
        var birthday: Date?
        var heightCm: Double?
        var weightKg: Double?
        var bodyFatFraction: Double?
    }

    struct HealthImport: Equatable {
        var summary: String
        var prefill: HealthPrefill
    }

    struct HealthImportCounts: Equatable {
        var meals = 0
        var weighIns = 0
        var bodyFatReadings = 0
        var workouts = 0

        /// What an import added, given the store counts before and after it.
        static func added(from before: HealthImportCounts, to after: HealthImportCounts) -> HealthImportCounts {
            HealthImportCounts(
                meals: max(0, after.meals - before.meals),
                weighIns: max(0, after.weighIns - before.weighIns),
                bodyFatReadings: max(0, after.bodyFatReadings - before.bodyFatReadings),
                workouts: max(0, after.workouts - before.workouts)
            )
        }
    }

    /// "Imported 120 meals and 45 weigh-ins.", or nil when nothing came back.
    static func importSummary(
        _ counts: HealthImportCounts,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String? {
        var parts: [String] = []
        if counts.meals > 0 {
            parts.append(String(localized: "\(counts.meals) meals", bundle: bundle, locale: locale,
                                comment: "Part of the Apple Health import summary: food log entries brought back."))
        }
        if counts.weighIns > 0 {
            parts.append(String(localized: "\(counts.weighIns) weigh-ins", bundle: bundle, locale: locale,
                                comment: "Part of the Apple Health import summary: weight entries brought back."))
        }
        if counts.bodyFatReadings > 0 {
            parts.append(String(localized: "\(counts.bodyFatReadings) body-fat readings", bundle: bundle, locale: locale,
                                comment: "Part of the Apple Health import summary: body-fat entries brought back."))
        }
        if counts.workouts > 0 {
            parts.append(String(localized: "calories for \(counts.workouts) workouts", bundle: bundle, locale: locale,
                                comment: "Part of the Apple Health import summary: workout calorie burns brought back."))
        }
        guard !parts.isEmpty else { return nil }
        let formatter = ListFormatter()
        formatter.locale = locale
        let list = formatter.string(from: parts) ?? parts.joined(separator: ", ")
        return String(localized: "Imported \(list).", bundle: bundle, locale: locale,
                      comment: "Apple Health import summary. The argument is a list such as “120 meals and 45 weigh-ins”.")
    }

    // MARK: - Wizard wheels

    struct HeightWheels: Equatable {
        var cm: Int
        var feet: Int
        var inches: Int
    }

    struct WeightWheels: Equatable {
        var kgWhole: Int
        var kgTenth: Int
        var lbsWhole: Int
        var lbsTenth: Int
    }

    /// Both height layouts, clamped to the wheels: 100–250 cm and 3 ft 0 in – 8 ft 11 in.
    static func heightWheels(cm: Double) -> HeightWheels? {
        guard cm.isFinite, cm > 0 else { return nil }
        let wholeCm = Int(min(max(cm, 100), 250).rounded())
        let totalInches = Int(min(max(cm / 2.54, 36), 107).rounded())
        return HeightWheels(cm: wholeCm, feet: totalInches / 12, inches: totalInches % 12)
    }

    /// Both weight units as whole + tenth wheels, clamped to 30.0–250.9 kg and 60.0–500.9 lbs.
    static func weightWheels(kg: Double) -> WeightWheels? {
        guard kg.isFinite, kg > 0 else { return nil }
        let kgTenths = Int((min(max(kg, 30), 250.9) * 10).rounded())
        let lbsTenths = Int((min(max(kg / 0.453592, 60), 500.9) * 10).rounded())
        return WeightWheels(
            kgWhole: kgTenths / 10, kgTenth: kgTenths % 10,
            lbsWhole: lbsTenths / 10, lbsTenth: lbsTenths % 10
        )
    }

    /// Health stores body fat as a 0–1 fraction; the wheel is whole percents 3–60.
    static func bodyFatWheel(fraction: Double) -> Int? {
        guard fraction.isFinite, fraction > 0 else { return nil }
        return Int(min(max(fraction * 100, 3), 60).rounded())
    }

    /// The birthday picker stops at today.
    static func birthdayWheel(_ date: Date, now: Date = Date()) -> Date {
        min(date, now)
    }

    /// Only male and female map to the wizard; "other" and "not set" keep its choice.
    static func gender(for sex: HKBiologicalSex?) -> Gender? {
        switch sex {
        case .male?: .male
        case .female?: .female
        default: nil
        }
    }
}

/// Onboarding's first screen for returning users: restore an iCloud backup,
/// import what Fud AI saved to Apple Health, or start fresh. Nothing touches
/// the network, iCloud or Health until the user taps a choice.
struct ReturningUserView: View {
    /// Result line of a Health import made earlier in this onboarding.
    let healthImportSummary: String?
    @Binding var hasCompletedOnboarding: Bool
    let onHealthImported: (ReturningUser.HealthImport) -> Void
    /// Continues with the normal setup steps.
    let onStartSetup: () -> Void

    @Environment(CloudBackupService.self) private var backup
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(FoodStore.self) private var foodStore
    @Environment(WeightStore.self) private var weightStore
    @Environment(BodyFatStore.self) private var bodyFatStore
    @Environment(StrengthWorkoutStore.self) private var strengthWorkoutStore

    private enum Activity {
        case checkingICloud, restoring, importingHealth

        var text: String {
            switch self {
            case .checkingICloud: String(localized: "Checking iCloud…")
            case .restoring: String(localized: "Restoring…")
            case .importingHealth: String(localized: "Importing from Apple Health…")
            }
        }
    }

    @State private var activity: Activity?
    @State private var message: String?
    @State private var backupDate: Date?
    @State private var showRestoreConfirm = false
    @State private var showUnfinishedSetup = false

    private var isBusy: Bool { activity != nil || backup.busy }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header

                    VStack(spacing: 12) {
                        choiceCard(
                            icon: "icloud.and.arrow.down",
                            title: String(localized: "Restore from iCloud"),
                            detail: String(localized: "Your full backup: diary, photos, workouts, and settings, if you turned on iCloud Backup before.")
                        ) {
                            Task { await checkICloud() }
                        }

                        if let healthImportSummary {
                            importedCard(summary: healthImportSummary)
                        } else {
                            choiceCard(
                                icon: "heart.fill",
                                title: String(localized: "Import from Apple Health"),
                                detail: String(localized: "Meals, weight, body fat, and workout calories Fud AI saved to Health. You'll finish a short setup after.")
                            ) {
                                Task { await importFromHealth() }
                            }
                        }
                    }

                    if let activity {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(activity.text)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else if let message {
                        Label {
                            Text(message)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.circle")
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AppColors.appCard, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            bottomButton
        }
        .alert(restoreQuestion, isPresented: $showRestoreConfirm) {
            Button("Restore") { Task { await restore() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("iCloud Backup", isPresented: $showUnfinishedSetup) {
            Button("Continue") { onStartSetup() }
        } message: {
            Text("This backup doesn't include a finished setup, so let's finish it now.")
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image("onboardingLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Welcome back")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Bring your meals, weight, and workouts back, or start fresh.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var bottomButton: some View {
        if healthImportSummary != nil {
            Button(action: onStartSetup) {
                Text("Continue setup")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: AppColors.calorieGradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isBusy)
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        } else {
            Button(action: onStartSetup) {
                Text("Start fresh")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.appCard, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isBusy)
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private func choiceCard(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                cardIcon(icon)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(16)
            .background(AppColors.appCard, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(detail))
    }

    private func importedCard(summary: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            cardIcon("checkmark.circle.fill")

            VStack(alignment: .leading, spacing: 6) {
                Text("Import from Apple Health")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppColors.appCard, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func cardIcon(_ systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.calorie.opacity(0.12))
                .frame(width: 48, height: 48)
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.calorie)
        }
        .accessibilityHidden(true)
    }

    private var restoreQuestion: String {
        guard let backupDate else { return String(localized: "Restore backup?") }
        let date = backupDate.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Restore your backup from \(date)?",
                      comment: "Confirmation before restoring an iCloud backup. The argument is the date and time of the backup.")
    }

    // MARK: - Actions

    private func start(_ next: Activity) {
        message = nil
        activity = next
        AccessibilityNotification.Announcement(next.text).post()
    }

    private func finish(with text: String?) {
        activity = nil
        message = text
        if let text { AccessibilityNotification.Announcement(text).post() }
    }

    private func checkICloud() async {
        start(.checkingICloud)
        switch await backup.probeForBackup() {
        case .found(let date):
            finish(with: nil)
            backupDate = date
            showRestoreConfirm = true
        case .notFound:
            finish(with: String(localized: "No iCloud backup found for this Apple ID."))
        case .couldNotCheck(let text):
            finish(with: text)
        }
    }

    private func restore() async {
        start(.restoring)
        ReturningUser.onboardingCompletedByRestore = true
        do {
            try await backup.restoreNow()
        } catch {
            ReturningUser.onboardingCompletedByRestore = false
            finish(with: CloudBackupService.userMessage(for: error))
            return
        }
        // These ran at launch on the empty defaults; the backup brings its own markers.
        UnitPreferenceMigration.runIfNeeded()
        AIProviderSettings.migrateLegacyGeminiModelsIfNeeded()
        SpeechSettings.migrateMatchingPrimaryProviderIfNeeded()
        AIProviderSettings.migrateFallbackBaseURLsIfNeeded()

        // A complete backup restored hasCompletedOnboarding = true, which swaps
        // onboarding for the app on the next render. A backup without a usable
        // profile (taken mid-setup, after a wipe, or by a newer app) must not
        // skip setup; this runs before that render, so the app never shows.
        let finishedSetup = UserProfile.load() != nil
            && UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard !finishedSetup else { return }
        ReturningUser.onboardingCompletedByRestore = false
        hasCompletedOnboarding = false
        finish(with: nil)
        showUnfinishedSetup = true
    }

    private var storeCounts: ReturningUser.HealthImportCounts {
        ReturningUser.HealthImportCounts(
            meals: foodStore.entries.count,
            weighIns: weightStore.entries.count,
            bodyFatReadings: bodyFatStore.entries.count,
            workouts: strengthWorkoutStore.workoutBurnSessions.count
        )
    }

    private func importFromHealth() async {
        start(.importingHealth)
        guard await healthKitManager.requestAuthorization() else {
            finish(with: String(localized: "Couldn't connect to Apple Health. You can try again later in Settings."))
            return
        }
        // The same switch onboarding's Apple Health step sets; it keeps Health in sync afterwards.
        UserDefaults.standard.set(true, forKey: "healthKitEnabled")

        let before = storeCounts
        // Runs while every store is still empty: Fud AI's own weight and
        // body-fat samples only come back (with their original ids) into an
        // empty history, and onboarding seeds a first entry when it finishes.
        let imports: [Task<Void, Never>?] = [
            healthKitManager.restoreFoodEntriesFromHealthKitIfNeeded(
                existingIDs: { [foodStore] in Set(foodStore.entries.map(\.id)) },
                importBatch: { [foodStore] entries in foodStore.mergeWithCloudEntries(entries) }
            ),
            healthKitManager.backfillWeightFromHealthKitIfNeeded { [weightStore] samples in
                weightStore.importHealthSamples(samples, restoreOwnSamplesIfEmpty: true)
            },
            healthKitManager.backfillBodyFatFromHealthKitIfNeeded(
                existing: { [bodyFatStore] in bodyFatStore.entries },
                importBatch: { [bodyFatStore] entries in bodyFatStore.importExternalEntries(entries) }
            ),
            healthKitManager.synchronizeWorkoutBurnsWithHealthKit(
                existing: { [strengthWorkoutStore] in strengthWorkoutStore.workoutBurnSessions },
                mergeBatch: { [strengthWorkoutStore] sessions in
                    strengthWorkoutStore.importWorkoutBurnSessions(sessions)
                }
            ),
        ]
        for task in imports { await task?.value }
        let added = ReturningUser.HealthImportCounts.added(from: before, to: storeCounts)

        let latest = await healthKitManager.fetchLatestBodyMeasurements()
        let prefill = ReturningUser.HealthPrefill(
            gender: ReturningUser.gender(for: latest.sex),
            birthday: latest.dob,
            heightCm: latest.height,
            weightKg: latest.weight,
            bodyFatFraction: latest.bodyFat
        )
        let summary = ReturningUser.importSummary(added)
            ?? String(localized: "Nothing to import from Apple Health yet.")
        finish(with: nil)
        AccessibilityNotification.Announcement(summary).post()
        onHealthImported(ReturningUser.HealthImport(summary: summary, prefill: prefill))
    }
}
