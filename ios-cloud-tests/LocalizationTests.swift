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

    @Test func authenticationSloganFollowsLanguagePreference() throws {
        let suite = "slogan-localization-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppLanguageSettings(defaults: defaults)
        let cases: [(AppLanguagePreference, String)] = [
            (.english, "Less “Oops.” More “Done.”"),
            (.traditionalChinese, "小心雷包就在你身邊"),
            (.english, "Less “Oops.” More “Done.”")
        ]
        for (preference, expected) in cases {
            settings.preference = preference
            #expect(settings.language.text("一起拆彈，一起過關。") == expected)
        }
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

    @Test @MainActor func attachmentErrorsFollowAppLanguageChanges() {
        let settings = AppLanguageSettings.shared
        let original = settings.preference
        defer { settings.preference = original }
        let cases: [(DocumentReadError, String, String)] = [
            (.unsupported, "僅支援 PNG、JPG、PDF、PPTX、DOCX、XLSX 和 ZIP。",
             "Only PNG, JPG, PDF, PPTX, DOCX, XLSX, and ZIP files are supported."),
            (.unsupportedPhoto, "請選擇 PNG 或 JPG 照片。", "Please choose a PNG or JPG photo."),
            (.empty, "檔案沒有可上傳的內容，請重新選擇。", "This file is empty. Please choose another file."),
            (.tooLarge, "檔案不可超過 20 MB。", "Files must be 20 MB or smaller."),
            (.unavailable, "無法讀取檔案，請確認檔案已下載後重試。",
             "Unable to read the file. Make sure it has finished downloading, then try again.")
        ]
        for preference in [AppLanguagePreference.english, .traditionalChinese, .english] {
            settings.preference = preference
            for (error, chinese, english) in cases {
                let expected = preference == .english ? english : chinese
                #expect(error.errorDescription == expected)
                #expect(error.localizedDescription == expected)
            }
        }
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
