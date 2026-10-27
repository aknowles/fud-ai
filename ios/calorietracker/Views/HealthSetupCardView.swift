import SwiftUI

/// One-time home card inviting the user to set up their health profile; hidden once anything
/// is set or the user says not now.
struct HealthSetupCardView: View {
    static let dismissedKey = "fork.healthSetupDismissed"

    @State private var health = HealthProfileStore.shared
    @AppStorage(dismissedKey) private var dismissed = false
    @State private var isShowingProfile = false

    var body: some View {
        if !dismissed && health.profile.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(AppColors.calorie)
                    Text("Set up your health profile")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                }
                Text("Add conditions such as gout or high blood pressure, medicines, foods to avoid and sensitivities. Coach, Suggestions and the home cards use them. Nothing is on until you choose it.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Set up") { isShowingProfile = true }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.calorie)
                    Button("Not now") { withAnimation { dismissed = true } }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .progressCardStyle()
            .sheet(isPresented: $isShowingProfile) {
                NavigationStack {
                    HealthProfileView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingProfile = false }
                            }
                        }
                }
            }
        }
    }
}
