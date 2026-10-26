import SwiftUI

/// Settings → Goals → Other Nutrients → Health Profile: turn conditions on or off, see
/// the goals each one uses and any conflicts between them.
struct HealthProfileView: View {
    @State private var store = HealthProfileStore.shared
    @State private var newAvoidTerm = ""
    @State private var newSensitivityTerm = ""
    @AppStorage(OptionalNutrientGoals.storageKey) private var goalsData = Data()

    private var goals: OptionalNutrientGoals { OptionalNutrientGoals.decoded(from: goalsData) }

    var body: some View {
        List {
            Section {
                ForEach(HealthEntryKind.allCases.filter { !$0.isMedicine }) { kind in
                    entryRow(kind)
                }
            } header: {
                Text("Conditions")
            } footer: {
                Text("Change the numbers under Other Nutrients. Use the values your doctor gives you.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                ForEach(HealthEntryKind.allCases.filter(\.isMedicine)) { kind in
                    entryRow(kind)
                }
            } header: {
                Text("Medicines")
            } footer: {
                Text("Add the medicines you take so Coach and Suggestions account for food interactions. This never changes how you take them; ask your doctor or pharmacist about your own medicines.")
            }
            .listRowBackground(AppColors.appCard)

            avoidSection

            sensitivitySection

            let conflicts = store.profile.conflicts
            if !conflicts.isEmpty {
                Section {
                    ForEach(conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(conflict.nutrient.displayName, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.orange)
                            HStack(alignment: .top, spacing: 12) {
                                conflictSide(title: String(localized: "Raise it"), sources: conflict.raisedBy, systemImage: "arrow.up")
                                conflictSide(title: String(localized: "Limit it"), sources: conflict.limitedBy, systemImage: "arrow.down")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Conflicts")
                } footer: {
                    Text("These conditions pull the same nutrient in opposite directions. Ask your doctor which goal applies; Coach will point the conflict out instead of choosing.")
                }
                .listRowBackground(AppColors.appCard)
            }

            Section {
                Text("This profile guides the Gout card, the DASH scorecard and Coach's advice. It is not medical advice, and Fud AI never suggests starting, stopping or changing a medicine.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Health Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.reload() }
    }

    private func entryRow(_ kind: HealthEntryKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { store.contains(kind) },
                set: { active in withAnimation { store.set(kind, active: active) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.system(.body, design: .rounded, weight: .medium))
                    Text(kind.summary)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(AppColors.calorie)

            if store.contains(kind) {
                let goals = goalSummary(for: kind)
                if !goals.isEmpty {
                    Text(goals)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(AppColors.calorie)
                }
                if !kind.avoidedFoodFlags.isEmpty {
                    Label(String(localized: "Avoid: \(kind.avoidedFoodFlags.map(\.displayName).joined(separator: ", "))"),
                          systemImage: "hand.raised.fill")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.red)
                }
                if kind.supportsDoseTimes {
                    doseControls(kind)
                }
                if kind.supportsCourse {
                    courseControls(kind)
                }
                if let note = kind.setupNote {
                    Label(note, systemImage: "stethoscope")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if kind == .dash {
                    DASHPresetButtons()
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func doseControls(_ kind: HealthEntryKind) -> some View {
        let schedule = store.profile.doseSchedule(for: kind) ?? DoseSchedule()
        Text("Dose times")
            .font(.system(.subheadline, design: .rounded, weight: .medium))
        ForEach(Array(schedule.times.enumerated()), id: \.offset) { index, minutes in
            HStack {
                DatePicker(String(localized: "Dose \(index + 1)"), selection: Binding(
                    get: { Self.date(minutes: minutes) },
                    set: { newDate in
                        var updated = schedule
                        updated.times[index] = Self.minutes(of: newDate)
                        store.setDoseSchedule(DoseSchedule(times: updated.times, mineralsBefore: updated.mineralsBefore,
                                                           mineralsAfter: updated.mineralsAfter), for: kind)
                    }
                ), displayedComponents: .hourAndMinute)
                Button(role: .destructive) {
                    var updated = schedule
                    updated.times.remove(at: index)
                    store.setDoseSchedule(updated.times.isEmpty && updated.mineralsBefore == nil && updated.mineralsAfter == nil
                                          ? nil : updated, for: kind)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
        }
        Button {
            var updated = schedule
            let next = (schedule.times.last.map { $0 + 12 * 60 } ?? 8 * 60) % (24 * 60)
            updated.times.append(next)
            store.setDoseSchedule(DoseSchedule(times: updated.times, mineralsBefore: updated.mineralsBefore,
                                               mineralsAfter: updated.mineralsAfter), for: kind)
        } label: {
            Label("Add dose time", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderless)
        if let minerals = store.profile.doseWindows(for: kind).first(where: { $0.foods == .minerals }), kind == .quinoloneTetracycline {
            Stepper(String(localized: "No minerals \(minerals.minutesBefore / 60) h before"),
                    value: Binding(get: { minerals.minutesBefore / 60 }, set: { hours in
                        var updated = schedule
                        updated.mineralsBefore = hours * 60
                        store.setDoseSchedule(updated, for: kind)
                    }), in: 0...8)
            Stepper(String(localized: "No minerals \(minerals.minutesAfter / 60) h after"),
                    value: Binding(get: { minerals.minutesAfter / 60 }, set: { hours in
                        var updated = schedule
                        updated.mineralsAfter = hours * 60
                        store.setDoseSchedule(updated, for: kind)
                    }), in: 0...8)
            Text("Match the label: ciprofloxacin is 6 h before and 2 h after; doxycycline is often 2 to 3 h either side.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private static func minutes(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    @ViewBuilder
    private func courseControls(_ kind: HealthEntryKind) -> some View {
        let course = store.profile.course(for: kind)
        Toggle("Short course with dates", isOn: Binding(
            get: { course != nil },
            set: { on in
                let start = Date()
                let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
                store.setCourse(on ? HealthCourse(start: start, end: end) : nil, for: kind)
            }
        ))
        .font(.system(.subheadline, design: .rounded))
        .tint(AppColors.calorie)
        if let course {
            DatePicker("Starts", selection: Binding(
                get: { course.start },
                set: { store.setCourse(HealthCourse(start: $0, end: max($0, course.end)), for: kind) }
            ), displayedComponents: .date)
            DatePicker("Ends", selection: Binding(
                get: { course.end },
                set: { store.setCourse(HealthCourse(start: course.start, end: $0), for: kind) }
            ), in: course.start..., displayedComponents: .date)
            Text(courseStatus(kind, course))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func courseStatus(_ kind: HealthEntryKind, _ course: HealthCourse) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let last = course.lastDay(tailDays: kind.courseTailDays, calendar: calendar)
        let lastText = last.formatted(date: .abbreviated, time: .omitted)
        if today < calendar.startOfDay(for: course.start) {
            return String(localized: "Starts \(course.start.formatted(date: .abbreviated, time: .omitted)); its rules are off until then.")
        }
        if today <= last {
            return String(localized: "Its rules apply through \(lastText).")
        }
        return String(localized: "Course ended; its rules are off.")
    }

    private var avoidSection: some View {
        Section {
            Toggle("Celiac disease (gluten)", isOn: avoidBinding(\.celiac))
                .tint(AppColors.calorie)
            Toggle("Lactose intolerance", isOn: avoidBinding(\.lactose))
                .tint(AppColors.calorie)
            ForEach(store.profile.avoidList.custom, id: \.self) { term in
                Label(term, systemImage: "hand.raised.fill")
            }
            .onDelete { offsets in
                var list = store.profile.avoidList
                list.custom.remove(atOffsets: offsets)
                store.setAvoidList(list)
            }
            HStack {
                TextField("Add a food, e.g. peanuts", text: $newAvoidTerm)
                    .textInputAutocapitalization(.never)
                    .onSubmit(addAvoidTerm)
                Button("Add", action: addAvoidTerm)
                    .disabled(newAvoidTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Foods to Avoid")
        } footer: {
            Text("Coach and Suggestions steer clear of these and flag options that contain them. Matching uses food names, ingredients and product allergen lists, so it can miss hidden ingredients; always check labels.")
        }
        .listRowBackground(AppColors.appCard)
    }

    private var sensitivitySection: some View {
        let sensitivities = store.profile.sensitivityList
        return Section {
            ForEach(SensitivityKind.allCases) { kind in
                Picker(kind.displayName, selection: Binding(
                    get: { sensitivities.level(for: kind) },
                    set: { level in
                        var updated = store.profile.sensitivityList
                        updated.levels[kind.rawValue] = level
                        store.setSensitivities(updated)
                    }
                )) {
                    Text("Off").tag(SensitivityLevel?.none)
                    ForEach(SensitivityLevel.allCases) { Text($0.displayName).tag(SensitivityLevel?.some($0)) }
                }
                .pickerStyle(.menu)
                if kind == .caffeine, sensitivities.level(for: .caffeine) != nil {
                    Toggle("Cut-off time", isOn: Binding(
                        get: { sensitivities.caffeineCutoffMinutes != nil },
                        set: { on in
                            var updated = store.profile.sensitivityList
                            updated.caffeineCutoffMinutes = on ? 14 * 60 : nil
                            store.setSensitivities(updated)
                        }
                    ))
                    .tint(AppColors.calorie)
                    if let cutoff = sensitivities.caffeineCutoffMinutes {
                        DatePicker("No caffeine after", selection: Binding(
                            get: { Self.date(minutes: cutoff) },
                            set: { date in
                                var updated = store.profile.sensitivityList
                                updated.caffeineCutoffMinutes = Self.minutes(of: date)
                                store.setSensitivities(updated)
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                }
            }
            ForEach(sensitivities.custom) { item in
                HStack {
                    Text(item.term)
                    Spacer()
                    Text(item.level.displayName).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                var updated = store.profile.sensitivityList
                updated.custom.remove(atOffsets: offsets)
                store.setSensitivities(updated)
            }
            HStack {
                TextField("Add your own, e.g. coconut", text: $newSensitivityTerm)
                    .textInputAutocapitalization(.never)
                Menu("Add") {
                    ForEach(SensitivityLevel.allCases) { level in
                        Button(level.displayName) { addSensitivity(level) }
                    }
                }
                .disabled(newSensitivityTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Food Sensitivities")
        } footer: {
            Text("For foods that bother you in larger amounts, unlike allergies. Avoid keeps them out, Limit ranks them lower, Note only tells Coach. The symptom log can suggest triggers.")
        }
        .listRowBackground(AppColors.appCard)
    }

    private func addSensitivity(_ level: SensitivityLevel) {
        let term = newSensitivityTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return }
        var updated = store.profile.sensitivityList
        updated.custom.removeAll { $0.term == term }
        updated.custom.append(CustomSensitivity(term: term, level: level))
        store.setSensitivities(updated)
        newSensitivityTerm = ""
    }

    private func avoidBinding(_ keyPath: WritableKeyPath<AvoidList, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.profile.avoidList[keyPath: keyPath] },
            set: { value in
                var list = store.profile.avoidList
                list[keyPath: keyPath] = value
                store.setAvoidList(list)
            }
        )
    }

    private func addAvoidTerm() {
        let term = newAvoidTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return }
        var list = store.profile.avoidList
        if !list.custom.contains(term) { list.custom.append(term) }
        store.setAvoidList(list)
        newAvoidTerm = ""
    }

    private func goalSummary(for kind: HealthEntryKind) -> String {
        kind.rules.map { rule in
            switch rule.direction {
            case .limit: return "\(rule.nutrient.displayName) \(String(localized: "max")) \(goals.goal(for: rule.nutrient)) \(rule.nutrient.unit)"
            case .target: return "\(rule.nutrient.displayName) \(String(localized: "min")) \(goals.goal(for: rule.nutrient)) \(rule.nutrient.unit)"
            case .steady: return "\(rule.nutrient.displayName) \(String(localized: "steady"))"
            }
        }
        .joined(separator: " · ")
    }

    private func conflictSide(title: String, sources: [String], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption, design: .rounded, weight: .semibold))
            Text(sources.joined(separator: ", "))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
