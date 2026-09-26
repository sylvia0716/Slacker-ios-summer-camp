import Foundation
import Testing
@testable import GroupCloudData

@Suite(.serialized)
@MainActor
struct SmartAgendaLocalizationTests {
    private func agenda(fixture: Bool = false, bilingual: Bool = false, materials: [String: Any] = [:], overrides: [String: Any] = [:]) throws -> SmartAgenda {
        var stage: [String: Any] = ["start": 0, "end": 4,
            "title": "Review prepared materials", "goal": "Confirm the opening, runtime and missing files"]
        if bilingual {
            stage["titleZhHant"] = "檢視雲端資料"
            stage["goalZhHant"] = "確認三項決議"
        }
        var data: [String: Any] = ["topic": "[Test] Finalize Our Demo", "meetingAt": 1790751600,
            "duration": 20, "meetingRevision": "meeting", "inputRevision": "input",
            "materials": materials, "memberUIDs": ["one"], "preparedUIDs": ["one"],
            "stages": [stage], "planState": "ready", "planSource": fixture ? "sample" : "openai"]
        if fixture { data["testFixture"] = "smart-agenda-2026-09-26" }
        data.merge(overrides) { _, new in new }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(SmartAgenda.self, from: JSONSerialization.data(withJSONObject: data))
    }

    @Test func generationWaitingAndLeasesExpireWithoutAnotherSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let queued = try agenda(overrides: ["stages": [], "planState": "waiting", "updatedAt": 900])
        #expect(queued.isGenerating(at: now))
        #expect(!queued.isGenerating(at: now.addingTimeInterval(81)))
        let running = try agenda(overrides: ["stages": [], "planState": "generating", "generation": ["expiresAt": 1020]])
        #expect(running.isGenerating(at: now))
        #expect(!running.isGenerating(at: now.addingTimeInterval(20)))
        let failed = try agenda(overrides: ["stages": [], "planState": "failed", "generation": ["expiresAt": 1020]])
        #expect(!failed.isGenerating(at: now))
        let old = try agenda(overrides: ["stages": [], "planState": "waiting"])
        #expect(!old.isGenerating(at: now))
        let unprepared = try agenda(overrides: ["stages": [], "preparedUIDs": [], "planState": "waiting", "updatedAt": 1000])
        #expect(!unprepared.isGenerating(at: now))
    }

    @Test func legacyAndNewEntriesKeepTheirOwnersAndStableOrder() throws {
        let material: [String: Any] = ["note": "Original", "revision": "one", "membershipVersion": "legacy"]
        let first = material.merging(["ownerUID": "one", "note": "First extra", "createdAtMillis": 100]) { _, new in new }
        let second = material.merging(["ownerUID": "one", "note": "Second extra", "createdAtMillis": 200]) { _, new in new }
        let value = try agenda(materials: ["one": material, "two": material, "entry-a": first, "entry-b": second])
        #expect(value.materials(for: "one").map(\.id) == ["one", "entry-a", "entry-b"])
        #expect(value.materials(for: "one").map(\.material.note) == ["Original", "First extra", "Second extra"])
        #expect(value.materials(for: "two").map(\.id) == ["two"])
        #expect(value.materials(for: "outsider").isEmpty)
        #expect(value.preparedUIDs.count == 1)
    }

    @Test func existingCloudFixtureSwitchesWithoutRewritingItsData() throws {
        let settings = AppLanguageSettings.shared, original = settings.preference
        defer { settings.preference = original }
        let sample = try agenda(fixture: true)
        settings.preference = .traditionalChinese
        #expect(sample.testFixture == "smart-agenda-2026-09-26")
        #expect(settings.language == .traditionalChinese)
        #expect(AppLanguage.traditionalChinese.text("[Test] Finalize Our Demo", table: "Localizable") == "[測試] 確認最終展示內容")
        #expect(sample.displayTopic == "[測試] 確認最終展示內容")
        #expect(sample.displayTitle(sample.stages[0]) == "檢視會前資料")
        #expect(sample.displayNote("Check the opening and runtime.") == "確認開場內容與展示片長。")
        #expect(sample.stages[0].time == "0–4 分鐘")
        #expect(sample.summary.contains("20 分鐘"))
        #expect(!sample.summary.contains("Sep"))
        #expect(L10n.format("{0}/{1} 人已準備", "3", "4") == "3/4 人已準備")
        settings.preference = .english
        #expect(sample.displayTopic == "[Test] Finalize Our Demo")
        #expect(sample.displayTitle(sample.stages[0]) == "Review prepared materials")
        #expect(sample.stages[0].time == "0–4 min")
        #expect(sample.summary.contains("Sep"))
        #expect(sample.summary.contains("20 min"))
        #expect(L10n.format("{0}/{1} 人已準備", "3", "4") == "3/4 prepared")
        #expect(sample.topic == "[Test] Finalize Our Demo")
    }

    @Test func memberContentIsPreservedAndBilingualPlansFollowTheViewer() throws {
        let settings = AppLanguageSettings.shared, original = settings.preference
        defer { settings.preference = original }
        let cloud = try agenda(bilingual: true)
        settings.preference = .traditionalChinese
        #expect(cloud.displayTopic == cloud.topic)
        #expect(cloud.displayNote("Check the opening and runtime.") == "Check the opening and runtime.")
        #expect(cloud.displayTitle(cloud.stages[0]) == "檢視雲端資料")
        #expect(cloud.displayGoal(cloud.stages[0]) == "確認三項決議")
        settings.preference = .english
        #expect(cloud.displayTitle(cloud.stages[0]) == "Review prepared materials")
        #expect(cloud.displayGoal(cloud.stages[0]) == "Confirm the opening, runtime and missing files")
        settings.preference = .system
        #expect(settings.language == AppLanguage.systemDefault)
        #expect(cloud.stages[0].start == 0 && cloud.stages[0].end == 4)
    }

    @Test func savingAnUnchangedLocalizedEditorPreservesCloudText() throws {
        let settings = AppLanguageSettings.shared, original = settings.preference
        defer { settings.preference = original }
        settings.preference = .traditionalChinese
        let sample = try agenda(fixture: true)
        let topic = sample.editableTopic
        let note = sample.editableNote("Check the opening and runtime.")
        #expect(topic.displayed == "[測試] 確認最終展示內容")
        #expect(note.displayed == "確認開場內容與展示片長。")
        #expect(topic.valueToSave(topic.displayed) == sample.topic)
        #expect(note.valueToSave("  \(note.displayed)\n") == "Check the opening and runtime.")
        #expect(topic.valueToSave("新會議主題") == "新會議主題")
        #expect(note.valueToSave("") == "")
        // The editor's baseline must stay fixed if the system language changes while it is open.
        settings.preference = .english
        #expect(topic.valueToSave(topic.displayed) == sample.topic)
        #expect(note.valueToSave(note.displayed) == note.original)
    }

    @Test func editingRealMemberContentNeverTranslatesWhatIsSaved() throws {
        let settings = AppLanguageSettings.shared, original = settings.preference
        defer { settings.preference = original }
        settings.preference = .traditionalChinese
        let cloud = try agenda()
        let note = cloud.editableNote("Check the opening and runtime.")
        #expect(note.displayed == note.original)
        #expect(note.valueToSave(note.displayed) == note.original)
        #expect(note.valueToSave("確認開場") == "確認開場")
    }

    @Test func meetingLinksDecodeWithoutChangingPreparationAndRejectUnsafeDestinations() throws {
        #expect(try agenda().meetingLinks.isEmpty)
        let link: [String: Any] = ["title": "", "url": "https://example.com/room", "ownerUID": "one", "createdAtMillis": 200, "revision": "r1"]
        let earlier = link.merging(["title": "共用白板", "createdAtMillis": 100]) { _, new in new }
        let value = try agenda(overrides: ["links": ["later": link, "first": earlier]])
        #expect(value.meetingLinks.map(\.id) == ["first", "later"])
        #expect(value.meetingLinks[1].link.displayTitle == "example.com")
        #expect(value.preparedUIDs == ["one"])
        for url in ["javascript:alert(1)", "file:///tmp/test", "data:text/html,test", "https://user:pass@example.com", "https://exa mple.com", "example.com"] {
            #expect(SmartAgenda.MeetingLink.validURL(url) == nil)
        }
        #expect(SmartAgenda.MeetingLink.validURL(" https://example.com/room?code=123 \n")?.absoluteString == "https://example.com/room?code=123")
    }
}
