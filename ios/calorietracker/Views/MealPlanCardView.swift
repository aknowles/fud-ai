import SwiftUI

/// Home card for meal planning: today's next planned meals with one-tap logging, or, early in
/// a week with nothing planned, a two-tap menu import (tap, snap the menu).
struct MealPlanCardView: View {
    let date: Date

    @Environment(FoodStore.self) private var foodStore
    @State private var plan = MealPlanStore.shared
    @AppStorage("fork.mealPlanCardDismissedWeek") private var dismissedWeek: Double = 0
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case week
        case importPhoto(UIImage)
        case importText

        var id: String {
            switch self {
            case .week: "week"
            case .importPhoto: "photo"
            case .importText: "text"
            }
        }
    }

    private var calendar: Calendar { .current }
    private var weekStart: Date { calendar.mondayOfWeek(containing: .now) }

    var body: some View {
        let isToday = calendar.isDateInToday(date)
        let logged = foodStore.entries(for: date)
        let pending = isToday ? plan.meals(on: date).filter { !$0.isLogged(in: logged) } : []
        let weekPlanned = (0..<7).contains { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart).map { !plan.meals(on: $0).isEmpty } ?? false
        }
        let earlyInWeek = (calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: .now)).day ?? 7) < 3
        let offerImport = isToday && !weekPlanned && earlyInWeek && dismissedWeek != weekStart.timeIntervalSince1970

        if !pending.isEmpty || offerImport {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.calorie)
                    Text("Meal plan")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Spacer()
                    if weekPlanned {
                        Button("Week") { sheet = .week }
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .buttonStyle(.borderless)
                    }
                }
                if !pending.isEmpty {
                    ForEach(pending.prefix(2)) { meal in
                        if let chosen = meal.chosen {
                            HStack(spacing: 10) {
                                Text(chosen.entry.emoji ?? "🍽️").font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chosen.entry.name)
                                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    Text("\(meal.mealType.displayName)\(meal.source.map { " · \($0)" } ?? "")\(meal.isSuggestion ? " · ✨" : "") · \(chosen.entry.calories) kcal")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Log") { log(chosen.entry, meal: meal.mealType) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppColors.calorie)
                            }
                        }
                    }
                } else {
                    Text("Got this week's cafe menu? Snap it to see the best choice each day.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button { showCamera = true } label: {
                            Label("Camera", systemImage: "camera")
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.calorie)
                        Button("Photo or text") { sheet = .importText }
                            .lineLimit(1)
                            .buttonStyle(.bordered)
                    }
                    Button("Not this week") { withAnimation { dismissedWeek = weekStart.timeIntervalSince1970 } }
                        .font(.system(.caption, design: .rounded))
                        .buttonStyle(.borderless)
                }
            }
            .padding()
            .progressCardStyle()
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                // Present the import only once the camera is gone.
                if let image = capturedImage {
                    capturedImage = nil
                    sheet = .importPhoto(image)
                }
            }) {
                CameraView(image: $capturedImage, onCancel: { showCamera = false }).ignoresSafeArea()
            }
            .onChange(of: capturedImage) { _, image in
                if image != nil { showCamera = false }
            }
            .sheet(item: $sheet) { which in
                NavigationStack {
                    switch which {
                    case .week:
                        WeekPlanView(onLog: { entry in log(entry, meal: entry.mealType); sheet = nil })
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { sheet = nil } } }
                    case .importPhoto(let image):
                        ImportMenuView(weekStart: weekStart, initialPhoto: image, onImported: { DispatchQueue.main.async { sheet = .week } })
                    case .importText:
                        ImportMenuView(weekStart: weekStart, onImported: { DispatchQueue.main.async { sheet = .week } })
                    }
                }
            }
        }
    }

    private func log(_ entry: FoodEntry, meal: MealType) {
        withAnimation { _ = foodStore.addEntry(entry.duplicatedForLogging(at: Date(), mealType: meal)) }
    }
}
