import Testing
@testable import calorietracker

/// The short Settings list (#24): every page is reachable exactly once, from the top of
/// the list or from one group row, and the most-used pages come first.
struct SettingsGroupsTests {
    private var pages: [ProfileSettingsCategory] {
        ProfileSettingsCategory.allCases.filter { $0.groupMembers == nil }
    }

    @Test func everyPageIsReachableExactlyOnce() {
        let reachable = SettingsHubLayout.topCases
            + SettingsHubLayout.groupCases.flatMap { $0.groupMembers ?? [] }
        #expect(reachable.count == pages.count)
        #expect(Set(reachable) == Set(pages))
    }

    @Test func topLevelIsShortAndLeadsWithTheMostUsedPages() {
        let rows = SettingsHubLayout.topCases.count + SettingsHubLayout.groupCases.count
        #expect(rows == 9)
        #expect(Array(SettingsHubLayout.topCases.prefix(4)) == [.goalsNutrition, .healthProfile, .medicines, .appPreferences])
    }

    @Test func groupsHoldAIAppDataAndAbout() {
        #expect(ProfileSettingsCategory.aiGroup.groupMembers == [.aiAccess, .aiProviders, .speechToText, .voiceAssistant])
        #expect(ProfileSettingsCategory.appDataGroup.groupMembers == [.workout, .healthData, .dataManagement])
        #expect(ProfileSettingsCategory.aboutGroup.groupMembers == ProfileSettingsCategory.appInfoCases)
        #expect(ProfileSettingsCategory.speechToText.settingsGroup == .aiGroup)
        #expect(ProfileSettingsCategory.legal.settingsGroup == .aboutGroup)
        #expect(ProfileSettingsCategory.goalsNutrition.settingsGroup == nil)
    }

    @Test func groupRowsAreNotVoiceAssistantSections() {
        for group in SettingsHubLayout.groupCases {
            #expect(group.voiceAssistantSection == nil)
            #expect(group.aboutCategory == nil)
        }
    }
}
