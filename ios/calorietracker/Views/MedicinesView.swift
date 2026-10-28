import SwiftUI

/// Settings → Medicines (also linked from the Health Profile). With the lock on it asks for
/// Face ID, Touch ID or the passcode before showing anything.
struct MedicinesView: View {
    @State private var lock = MedicineLock.shared
    @State private var failed = false

    var body: some View {
        if lock.needsUnlock {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColors.calorie)
                Text("Medicines are locked")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("Your medicines still guide Coach and Suggestions; their names stay hidden elsewhere in the app.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { failed = !(await lock.unlock()) }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.calorie)
                if failed {
                    Text("Couldn't unlock. Try again.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.appBackground)
            .navigationTitle("Medicines")
            .navigationBarTitleDisplayMode(.inline)
            .task { if lock.needsUnlock { failed = !(await lock.unlock()) } }
        } else {
            HealthProfileView(page: .medicines)
        }
    }
}

/// The lock and what the AI is told, at the bottom of the Medicines page.
struct MedicinePrivacySection: View {
    @State private var lock = MedicineLock.shared
    @AppStorage(MedicinePrivacy.shareNamesKey) private var shareNames = true
    @State private var lockFailed = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { lock.isLocked },
                set: { newValue in
                    Task { lockFailed = !(await lock.setLocked(newValue)) }
                }
            )) {
                Label("Lock with Face ID", systemImage: "lock.fill")
            }
            .disabled(!lock.canAuthenticate)
            Toggle(isOn: $shareNames) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share medicine names with AI")
                    Text(shareNames
                         ? "Coach, Suggestions and menu import see the names."
                         : "They see only the food rules, e.g. \"a medicine that interacts with grapefruit\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !lock.canAuthenticate {
                Text("Set a passcode on this iPhone to use the lock.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if lockFailed {
                Text("Couldn't confirm it's you, so nothing changed.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("With the lock on, this screen needs Face ID or your passcode, and Home and Suggestions say \"your medicine\" instead of the name. The food rules still apply everywhere. Medicines stay on this iPhone unless you share names with AI.")
        }
        .listRowBackground(AppColors.appCard)
        .tint(AppColors.calorie)
    }
}
