import SwiftUI

/// Home day-view card for medicines with dose windows: foods logged inside a window, and the
/// windows still ahead today. Hidden when there is nothing to show.
struct DoseTimingCardView: View {
    let date: Date

    @Environment(FoodStore.self) private var foodStore
    @State private var health = HealthProfileStore.shared

    private struct Clash: Identifiable {
        let id = UUID()
        let entry: FoodEntry
        let conflict: DoseConflict
    }

    private var clashes: [Clash] {
        foodStore.entries(for: date).flatMap { entry in
            DoseTiming.conflicts(for: entry, profile: health.profile).map { Clash(entry: entry, conflict: $0) }
        }
    }

    private var upcoming: [(kind: HealthEntryKind, dose: Date, rule: DoseWindowRule, start: Date, end: Date)] {
        let now = Date()
        guard Calendar.current.isDate(date, inSameDayAs: now) else { return [] }
        return DoseTiming.upcomingWindows(on: now, after: now, profile: health.profile)
    }

    var body: some View {
        let clashes = clashes
        let upcoming = upcoming
        if !clashes.isEmpty || !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.calorie)
                    Text("Dose timing")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                }
                ForEach(clashes) { clash in
                    Label(clashText(clash), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(upcoming.enumerated()), id: \.offset) { _, window in
                    Text(String(localized: "\(window.kind.doseName.prefix(1).uppercased() + window.kind.doseName.dropFirst()) at \(time(window.dose)): no \(window.rule.foods.displayName) from \(time(window.start)) to \(time(window.end))"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .progressCardStyle()
        }
    }

    private func clashText(_ clash: Clash) -> String {
        let gap = abs(clash.conflict.minutesFromDose)
        let doseTime = time(clash.conflict.dose)
        let name = clash.conflict.kind.doseName
        let relation = clash.conflict.minutesFromDose < 0
            ? String(localized: "\(gap) min before your \(doseTime) \(name) dose")
            : String(localized: "\(gap) min after your \(doseTime) \(name) dose")
        let foods = clash.conflict.foods.displayName
        let sentenceFoods = foods.prefix(1).uppercased() + foods.dropFirst()
        return String(localized: "\(clash.entry.name) at \(time(clash.entry.timestamp)), \(relation). \(sentenceFoods) should wait until \(time(clash.conflict.windowEnd)).")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
