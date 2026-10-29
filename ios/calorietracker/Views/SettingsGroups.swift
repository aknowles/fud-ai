import SwiftUI

/// Fork layout for the Settings list (#24): the pages people change most sit at the top,
/// and rarely used ones open from three group rows. Every upstream page stays reachable
/// exactly once, through `ProfileSettingsCategory` values, so the typed navigation path,
/// voice-assistant jumps and deep links keep working.
enum SettingsHubLayout {
    static let topCases: [ProfileSettingsCategory] = [
        .goalsNutrition,
        .healthProfile,
        .medicines,
        .appPreferences,
        .personalInfo,
        .trackingNotifications,
    ]

    static let groupCases: [ProfileSettingsCategory] = [
        .aiGroup,
        .appDataGroup,
        .aboutGroup,
    ]
}

extension ProfileSettingsCategory {
    /// The pages a group row opens; nil for an ordinary page.
    var groupMembers: [ProfileSettingsCategory]? {
        switch self {
        case .aiGroup: [.aiAccess, .aiProviders, .speechToText, .voiceAssistant]
        case .appDataGroup: [.workout, .healthData, .dataManagement]
        case .aboutGroup: ProfileSettingsCategory.appInfoCases
        default: nil
        }
    }

    /// The group whose page lists this one, if any.
    var settingsGroup: ProfileSettingsCategory? {
        SettingsHubLayout.groupCases.first { $0.groupMembers?.contains(self) == true }
    }
}

/// The page a group row opens: its member pages, one row each.
struct SettingsGroupView: View {
    let group: ProfileSettingsCategory

    var body: some View {
        List {
            Section {
                ForEach(group.groupMembers ?? []) { category in
                    ProfileSettingsCategoryRow(category: category)
                }
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle(Text(group.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
