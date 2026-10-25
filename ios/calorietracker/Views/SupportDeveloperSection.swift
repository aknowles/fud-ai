import SwiftUI

/// Replaces the in-app tip jar in this fork. In-app purchases pay whoever signs the app,
/// so a fork build cannot tip the original developer through StoreKit. These links are
/// the channels upstream publishes in its own `.github/FUNDING.yml`.
struct SupportDeveloperSection: View {
    static let gitHubSponsors = URL(string: "https://github.com/sponsors/apoorvdarshan")!
    static let koFi = URL(string: "https://ko-fi.com/apoorvdarshan")!

    var body: some View {
        Section {
            Link(destination: Self.gitHubSponsors) {
                row(title: "GitHub Sponsors", systemImage: "heart.fill")
            }
            Link(destination: Self.koFi) {
                row(title: "Ko-fi", systemImage: "cup.and.saucer.fill")
            }
        } header: {
            Text("Support the original developer")
        } footer: {
            Text("Fud AI is built by Apoorv Darshan. This build has no in-app tips; these links go to the developer's own sponsorship pages.")
        }
        .listRowBackground(AppColors.appCard)
    }

    private func row(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.calorie)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
