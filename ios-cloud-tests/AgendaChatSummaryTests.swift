import Foundation
import Testing
@testable import GroupCloudData

@Suite(.serialized) @MainActor
struct AgendaChatSummaryTests {
    @Test func summaryFollowsViewerLanguageAndKeepsMissingPreparationExplicit() throws {
        let settings = AppLanguageSettings.shared, original = settings.preference
        defer { settings.preference = original }
        let summary = AgendaChatSummary(topic: "Demo", meetingAtMillis: 1_790_751_600_000, duration: 20,
                                        preparedNames: ["Mia", "Sam"], missingNames: ["Alex"],
                                        discussionTitles: ["Confirm scope"], discussionTitlesZhHant: ["確認範圍"])
        settings.preference = .traditionalChinese
        #expect(summary.localizedText.contains("會前提醒"))
        #expect(summary.localizedText.contains("2/3"))
        #expect(summary.localizedText.contains("尚未提交筆記或附件：Alex"))
        #expect(summary.localizedText.contains("確認範圍"))
        #expect(!summary.localizedText.contains("\n"))
        settings.preference = .english
        #expect(summary.localizedText.contains("Meeting reminder"))
        #expect(summary.localizedText.contains("Still missing a note or attachment: Alex"))
        #expect(summary.localizedText.contains("Confirm scope"))
        let restored = try JSONDecoder().decode(AgendaChatSummary.self, from: JSONEncoder().encode(summary))
        #expect(restored.localizedText == summary.localizedText)
    }

    @Test func allPreparedDoesNotInventMissingAttachments() {
        let settings = AppLanguageSettings.shared, original = settings.preference
        defer { settings.preference = original }
        settings.preference = .traditionalChinese
        let summary = AgendaChatSummary(topic: "Demo", meetingAtMillis: 1_790_751_600_000, duration: 20,
                                        preparedNames: ["Mia"], missingNames: [], discussionTitles: [], discussionTitlesZhHant: [])
        #expect(summary.localizedText.contains("全員已完成會前準備"))
        #expect(!summary.localizedText.contains("尚未提交"))
        #expect(!summary.localizedText.contains("討論重點"))
    }
}
