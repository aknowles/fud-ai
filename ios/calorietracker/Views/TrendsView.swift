import Charts
import SwiftUI

/// Progress card that opens Trends.
struct TrendsEntryCard: View {
    var body: some View {
        NavigationLink {
            TrendsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3)
                    .foregroundStyle(AppColors.calorie)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trends")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Compare nutrients, water, weight and steps over time, with symptoms marked")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .progressCardStyle()
        }
        .buttonStyle(.plain)
    }
}

/// Up to two series over a range of days, on two axes when their units differ, with a rolling
/// average, goal lines, a band above a limit and symptom markers. Tap a day for its numbers.
struct TrendsView: View {
    @Environment(FoodStore.self) private var foodStore
    @Environment(WaterStore.self) private var waterStore
    @Environment(WeightStore.self) private var weightStore
    @Environment(HealthKitManager.self) private var healthKitManager
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()
    @AppStorage("weightUnit") private var weightUnitRaw = "lbs"
    @AppStorage(WaterSettings.unitKey) private var waterUnitRaw = WaterUnit.defaultUnit.rawValue
    @AppStorage(WaterSettings.dailyGoalKey) private var waterGoalMl = WaterSettings.defaultDailyGoalMl
    @AppStorage(Hydration.countDrinksKey) private var countDrinks = true
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false

    @State private var presetID: String?
    @State private var primary: TrendMetric = .calories
    @State private var secondary: TrendMetric?
    @State private var markerKinds: Set<SymptomKind> = []
    @State private var rangeDays = 30
    @State private var customRange = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var selectedDay: Date?
    @State private var steps: [Date: Int] = [:]
    @State private var showingFoods: NutrientMetric?
    @State private var showingWater = false
    @State private var didApplyDefault = false

    private static let secondaryColor = Color(red: 0.55, green: 0.42, blue: 0.95)
    private var calendar: Calendar { .current }
    private var weightInKg: Bool { weightUnitRaw == "kg" }
    private var waterUnit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .defaultUnit }
    private var goals: OptionalNutrientGoals { OptionalNutrientGoals.decoded(from: goalsData) }
    private var profile: HealthProfile { HealthProfileStore.shared.profile.effective(on: Date()) }

    private var days: [Date] {
        if customRange { return TrendData.days(from: min(customStart, customEnd), through: max(customStart, customEnd)) }
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: end) ?? end
        return TrendData.days(from: start, through: end)
    }

    private var sources: TrendData.Sources {
        TrendData.Sources(foodsByDay: TrendData.Sources.grouping(foodStore.entries), water: waterStore.entries,
                          weights: weightStore.entries, steps: steps, goals: goals, weightInKg: weightInKg,
                          waterUnit: waterUnit, countDrinks: countDrinks)
    }

    private func unit(_ metric: TrendMetric) -> String { metric.unit(weightInKg: weightInKg, water: waterUnit) }

    private func goal(_ metric: TrendMetric) -> Double? {
        TrendData.goal(metric, profile: UserProfile.load(), goals: goals, waterGoalMl: waterGoalMl,
                       waterUnit: waterUnit, weightInKg: weightInKg)
    }

    var body: some View {
        let days = days
        let sources = sources
        let primarySeries = TrendData.series(primary, days: days, sources: sources)
        let secondarySeries = secondary.map { TrendData.series($0, days: days, sources: sources) }
        let markers = TrendData.markers(SymptomStore.shared.symptoms, kinds: markerKinds, days: days)
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TrendPreset.ordered(for: profile)) { preset in
                            Button(preset.name) { apply(preset) }
                                .buttonStyle(.bordered)
                                .tint(presetID == preset.id ? AppColors.calorie : .secondary)
                        }
                    }
                }
                Picker("Range", selection: Binding(
                    get: { customRange ? 0 : rangeDays },
                    set: { value in
                        customRange = value == 0
                        if value > 0 { rangeDays = value }
                        selectedDay = nil
                    }
                )) {
                    ForEach(TrendData.rangeChoices, id: \.self) { Text("\($0) days").tag($0) }
                    Text("Custom").tag(0)
                }
                .pickerStyle(.segmented)
                if customRange {
                    DatePicker("From", selection: $customStart, in: ...Date(), displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: ...Date(), displayedComponents: .date)
                }
            }
            .listRowBackground(AppColors.appCard)

            Section {
                chart(primarySeries: primarySeries, secondarySeries: secondarySeries, markers: markers)
                    .frame(height: 260)
                    .padding(.vertical, 6)
                legend
            }
            .listRowBackground(AppColors.appCard)

            if let selectedDay {
                daySection(selectedDay, primarySeries: primarySeries, secondarySeries: secondarySeries, markers: markers)
            }

            Section {
                Picker("Chart", selection: Binding(get: { primary }, set: { primary = $0; presetID = nil })) {
                    ForEach(TrendMetric.all) { Text($0.label).tag($0) }
                }
                Picker("Compare with", selection: Binding(get: { secondary }, set: { secondary = $0; presetID = nil })) {
                    Text("Nothing").tag(TrendMetric?.none)
                    ForEach(TrendMetric.all.filter { $0 != primary }) { Text($0.label).tag(TrendMetric?.some($0)) }
                }
                Menu {
                    ForEach(SymptomKind.allCases) { kind in
                        Button {
                            if markerKinds.contains(kind) { markerKinds.remove(kind) } else { markerKinds.insert(kind) }
                            presetID = nil
                        } label: {
                            if markerKinds.contains(kind) { Label(kind.displayName, systemImage: "checkmark") } else { Text(kind.displayName) }
                        }
                    }
                } label: {
                    LabeledContent("Mark symptoms", value: markerKinds.isEmpty ? String(localized: "None")
                                   : markerKinds.map(\.displayName).sorted().joined(separator: ", "))
                }
            } header: {
                Text("Series")
            } footer: {
                Text(days.count > 31
                     ? "Bars are daily totals, colored by how the day did against its goal; the dashed line is their 7-day average. The comparison shows daily dots and its 7-day average. Days with nothing logged are blank. Tap the chart to see a day."
                     : "Bars are daily totals, colored by how the day did against its goal; the dashed line is the 7-day average. Days with nothing logged are blank. Tap the chart to see a day.")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didApplyDefault else { return }
            didApplyDefault = true
            if let first = TrendPreset.ordered(for: profile).first, profile.contains(.gout) || profile.contains(.dash) {
                apply(first)
            }
        }
        .task(id: stepsTaskKey(days)) { await loadSteps(days) }
        .sheet(item: $showingFoods) { metric in
            if let selectedDay { NutrientContributorsView(metric: metric, date: selectedDay) }
        }
        .sheet(isPresented: $showingWater) {
            if let selectedDay { WaterDetailsView(date: selectedDay) }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(primarySeries: [TrendDay], secondarySeries: [TrendDay]?,
                       markers: [(day: Date, name: String, severity: Int)]) -> some View {
        let primaryGoal = goal(primary)
        let top = TrendData.axisTop(primarySeries, goal: primaryGoal)
        let secondaryGoal = secondary.flatMap(goal)
        let secondaryTop = secondarySeries.map { TrendData.axisTop($0, goal: secondaryGoal) } ?? 1
        let factor = TrendData.scaleFactor(primaryMax: top, secondaryMax: secondaryTop)
        let average = TrendData.rollingAverage(primarySeries)
        let direction = primary.direction(profile: profile)
        let isLine = primary == .weight

        Chart {
            if direction == .limit, let primaryGoal {
                RectangleMark(yStart: .value("Limit", primaryGoal), yEnd: .value("Top", top))
                    .foregroundStyle(TrackTone.bad.color.opacity(0.07))
            }
            ForEach(primarySeries) { point in
                if let value = point.value {
                    if isLine {
                        LineMark(x: .value("Day", point.day, unit: .day), y: .value(primary.label, value), series: .value("Series", "primary"))
                            .foregroundStyle(AppColors.calorie)
                        PointMark(x: .value("Day", point.day, unit: .day), y: .value(primary.label, value))
                            .foregroundStyle(AppColors.calorie)
                            .symbolSize(18)
                    } else {
                        BarMark(x: .value("Day", point.day, unit: .day), y: .value(primary.label, value))
                            .foregroundStyle(barColor(value, goal: primaryGoal, direction: direction))
                            .opacity(selectedDay == nil || selectedDay == point.day ? 1 : 0.45)
                    }
                }
            }
            if !isLine, days.count > TrendData.averageWindow {
                ForEach(average) { point in
                    if let value = point.value {
                        LineMark(x: .value("Day", point.day, unit: .day), y: .value("Average", value), series: .value("Series", "average"))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            if let primaryGoal {
                RuleMark(y: .value("Goal", primaryGoal))
                    .foregroundStyle(AppColors.calorie.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            if let secondarySeries {
                // Over a month or more a daily line zig-zags over the bars; show the days as dots
                // and draw the 7-day average as the line instead.
                let smooth = days.count > 31
                let line = smooth ? TrendData.rollingAverage(secondarySeries) : secondarySeries
                ForEach(line) { point in
                    if let value = point.value {
                        LineMark(x: .value("Day", point.day, unit: .day), y: .value("Compare", value * factor), series: .value("Series", "secondary"))
                            .foregroundStyle(Self.secondaryColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(secondarySeries) { point in
                    if let value = point.value {
                        PointMark(x: .value("Day", point.day, unit: .day), y: .value("Compare", value * factor))
                            .foregroundStyle(Self.secondaryColor.opacity(smooth ? 0.55 : 1))
                            .symbolSize(smooth ? 8 : 14)
                    }
                }
                if let secondaryGoal {
                    RuleMark(y: .value("Compare goal", secondaryGoal * factor))
                        .foregroundStyle(Self.secondaryColor.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            ForEach(markers, id: \.day) { marker in
                RuleMark(x: .value("Day", marker.day, unit: .day))
                    .foregroundStyle(TrackTone.caution.color.opacity(0.35 + 0.2 * Double(marker.severity)))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(position: .top, spacing: 0) {
                        Image(systemName: marker.name == SymptomKind.goutFlare.displayName ? "flame.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(TrackTone.caution.color)
                    }
            }
            if let selectedDay {
                RuleMark(x: .value("Day", selectedDay, unit: .day))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let number = value.as(Double.self) { Text(Self.short(number)) } }
            }
            if secondary != nil {
                AxisMarks(position: .trailing) { value in
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(Self.short(number / factor)).foregroundStyle(Self.secondaryColor)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let frame = proxy.plotFrame.map({ geometry[$0] }) else { return }
                        let x = tap.location.x - frame.origin.x
                        if let date: Date = proxy.value(atX: x) {
                            let day = calendar.startOfDay(for: date)
                            selectedDay = selectedDay == day ? nil : day
                        }
                    })
            }
        }
        .accessibilityLabel("\(primary.label) trend chart")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(primary.label + " (\(unit(primary)))", color: AppColors.calorie)
            if let secondary { legendItem(secondary.label + " (\(unit(secondary)))", color: Self.secondaryColor) }
            if !markerKinds.isEmpty { legendItem(String(localized: "Symptoms"), color: TrackTone.caution.color) }
        }
        .font(.system(.caption, design: .rounded))
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func barColor(_ value: Double, goal: Double?, direction: TrackDirection?) -> Color {
        guard let goal, let direction else { return AppColors.calorie }
        return TrackStyle.make(direction: direction, current: value, goal: goal, unit: "").tone.color
    }

    // MARK: - Day

    @ViewBuilder
    private func daySection(_ day: Date, primarySeries: [TrendDay], secondarySeries: [TrendDay]?,
                            markers: [(day: Date, name: String, severity: Int)]) -> some View {
        Section {
            valueRow(primary, value: primarySeries.first { $0.day == day }?.value)
            if let secondary {
                valueRow(secondary, value: secondarySeries?.first { $0.day == day }?.value)
            }
            let symptoms = SymptomStore.shared.symptoms.filter { calendar.isDate($0.date, inSameDayAs: day) }
            ForEach(symptoms) { symptom in
                Label(symptom.name, systemImage: symptom.kind == .goutFlare ? "flame.fill" : "exclamationmark.circle")
                    .foregroundStyle(TrackTone.caution.color)
            }
            if let metric = primary.nutrientMetric ?? secondary?.nutrientMetric {
                Button { showingFoods = metric } label: {
                    Label(String(localized: "Foods behind \(metric.label.lowercased())"), systemImage: "list.bullet")
                }
            }
            if primary == .water || secondary == .water {
                Button { showingWater = true } label: { Label("Water that day", systemImage: "drop.fill") }
            }
        } header: {
            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        }
        .listRowBackground(AppColors.appCard)
    }

    private func valueRow(_ metric: TrendMetric, value: Double?) -> some View {
        LabeledContent(metric.label) {
            if let value {
                let goal = goal(metric)
                Text("\(Self.short(value)) \(unit(metric))" + (goal.map { " / \(Self.short($0))" } ?? ""))
            } else {
                Text(metric.isFromDiary ? String(localized: "Nothing logged") : String(localized: "No data"))
            }
        }
    }

    // MARK: - Helpers

    private func apply(_ preset: TrendPreset) {
        presetID = preset.id
        primary = preset.primary
        secondary = preset.secondary
        markerKinds = preset.markers
        selectedDay = nil
    }

    private func stepsTaskKey(_ days: [Date]) -> String {
        "\(primary.id)-\(secondary?.id ?? "")-\(days.first?.timeIntervalSince1970 ?? 0)-\(days.count)-\(healthKitEnabled)"
    }

    private func loadSteps(_ days: [Date]) async {
        guard healthKitEnabled, primary == .steps || secondary == .steps, let first = days.first, let last = days.last else { return }
        let fetched = await healthKitManager.fetchDailySteps(from: first, through: last)
        steps = Dictionary(fetched.map { (calendar.startOfDay(for: $0.date), $0.steps) }, uniquingKeysWith: { $1 })
    }

    private static func short(_ value: Double) -> String {
        if value >= 10_000 { return "\(Int((value / 1_000).rounded()))k" }
        if value >= 100 { return String(Int(value.rounded())) }
        return MacroValueFormatter.string((value * 10).rounded() / 10)
    }
}
