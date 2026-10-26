import SwiftUI

/// Symptoms the user logged, and foods that show up before them more often than usual.
struct SymptomLogView: View {
    @Environment(FoodStore.self) private var foodStore
    @State private var store = SymptomStore.shared
    @State private var health = HealthProfileStore.shared
    @State private var isAdding = false

    var body: some View {
        let findings = TriggerAnalysis.findings(symptoms: store.symptoms, entries: foodStore.entries)
        List {
            Section {
                if findings.isEmpty {
                    Text("Log each symptom when it happens. After about three of the same kind, foods that keep showing up beforehand appear here.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(findings.prefix(8).enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(finding.feature.label.prefix(1).uppercased() + finding.feature.label.dropFirst())
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text(finding.evidence)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        triggerAction(finding)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Possible triggers")
            } footer: {
                Text("Patterns, not proof: one-off coincidences are common. Try limiting a trigger for a couple of weeks and see whether the symptom eases.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                if store.symptoms.isEmpty {
                    Text("No symptoms logged yet.").foregroundStyle(.secondary)
                }
                ForEach(store.symptoms.prefix(100)) { symptom in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(symptom.name)
                            .font(.system(.body, design: .rounded, weight: .medium))
                        Text("\(symptom.date.formatted(date: .abbreviated, time: .shortened)) · \(severityName(symptom.severity))\(symptom.note.map { " · \($0)" } ?? "")")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { store.remove(store.symptoms[index].id) }
                }
            } header: {
                Text("Logged symptoms")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Symptom Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: { Label("Log a symptom", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack { AddSymptomView() }
        }
        .onAppear { store.reload() }
    }

    @ViewBuilder
    private func triggerAction(_ finding: TriggerFinding) -> some View {
        let sensitivities = health.profile.sensitivityList
        switch finding.feature {
        case .sensitivity(let kind):
            if let level = sensitivities.level(for: kind) {
                Text(String(localized: "Already set to \(level.displayName.lowercased())."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button(String(localized: "Limit \(kind.label)")) {
                    var updated = sensitivities
                    updated.levels[kind.rawValue] = .limit
                    health.setSensitivities(updated)
                }
                .buttonStyle(.borderless)
            }
        case .food(let name):
            if sensitivities.custom.contains(where: { $0.term == name }) {
                Text("Already on your list.").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(String(localized: "Limit \(name)")) {
                    var updated = sensitivities
                    updated.custom.append(CustomSensitivity(term: name, level: .limit))
                    health.setSensitivities(updated)
                }
                .buttonStyle(.borderless)
            }
        case .lateMeal, .alcohol, .highPurines:
            Text("Coach sees this pattern.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func severityName(_ severity: Int) -> String {
        switch severity {
        case 1: String(localized: "Mild")
        case 3: String(localized: "Severe")
        default: String(localized: "Moderate")
        }
    }
}

struct AddSymptomView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SymptomKind = .bloating
    @State private var customName = ""
    @State private var date = Date()
    @State private var severity = 2
    @State private var note = ""

    var body: some View {
        Form {
            Picker("Symptom", selection: $kind) {
                ForEach(SymptomKind.allCases) { Text($0.displayName).tag($0) }
            }
            if kind == .other {
                TextField("Name", text: $customName)
            }
            DatePicker("When", selection: $date, in: ...Date())
            Picker("How bad", selection: $severity) {
                Text("Mild").tag(1)
                Text("Moderate").tag(2)
                Text("Severe").tag(3)
            }
            .pickerStyle(.segmented)
            TextField("Note (optional)", text: $note, axis: .vertical)
        }
        .navigationTitle("Log a Symptom")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    SymptomStore.shared.add(Symptom(date: date, kind: kind, customName: kind == .other ? trimmedName : nil,
                                                    severity: severity, note: trimmedNote.isEmpty ? nil : trimmedNote))
                    dismiss()
                }
                .disabled(kind == .other && customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
