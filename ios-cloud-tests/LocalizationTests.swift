import Foundation
import Testing
@testable import GroupCloudData

struct LocalizationTests {
    @Test func resolvesSupportedSystemLanguagesInOrder() {
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-Hant-TW", "en-US"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["en-GB", "zh-Hant"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: ["ja-JP", "zh-Hans"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["fr-FR"]) == .english)
    }

    @Test func preferencePersistsAndCanReturnToSystem() throws {
        let suite = "localization-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppLanguageSettings(defaults: defaults)
        #expect(settings.preference == .system)
        settings.preference = .english
        #expect(settings.language == .english)
        #expect(AppLanguageSettings(defaults: defaults).preference == .english)
        settings.preference = .traditionalChinese
        #expect(settings.language == .traditionalChinese)
        settings.preference = .system
        #expect(settings.language == .systemDefault)
        #expect(AppLanguageSettings(defaults: defaults).preference == .system)
    }

    @Test func translatesOnlyInterfaceTemplateAndPreservesUserInput() {
        let title = "English task 中文 {1} 👩🏽‍💻"
        let name = "Alex 小宇 {0}"
        let template = AppLanguage.english.text("已發布新任務「{0}」", table: "Localizable")
        #expect(template != "已發布新任務「{0}」")
        #expect(L10n.interpolate(template, arguments: [title]).contains(title))
        #expect(L10n.interpolate("{1}: {0} / {1}", arguments: [title, name]) == "\(name): \(title) / \(name)")
        #expect(AppLanguage.traditionalChinese.text("設定", table: "Localizable") == "設定")
        #expect(AppLanguage.english.text("設定", table: "Localizable") == "Settings")
    }

    @Test func catalogsHaveMatchingKeysAndInterpolationSlots() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func catalog(_ language: String) throws -> [String: String] {
            let data = try Data(contentsOf: root.appendingPathComponent("group/Resources/\(language).lproj/Localizable.strings"))
            return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let chinese = try catalog("zh-Hant")
        let english = try catalog("en")
        #expect(Set(chinese.keys) == Set(english.keys))
        let regex = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func slots(_ value: String) -> [String] {
            regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                String(value[Range($0.range, in: value)!])
            }.sorted()
        }
        for (key, value) in chinese {
            let translation = try #require(english[key])
            #expect(!translation.isEmpty, "Empty translation: \(key)")
            #expect(slots(value) == slots(translation), "Mismatched placeholders: \(key)")
        }
    }
}
