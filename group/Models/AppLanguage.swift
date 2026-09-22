import Foundation
import Observation

enum AppLanguage: String, CaseIterable {
    case traditionalChinese = "zh-Hant"
    case english = "en"

    static var systemDefault: Self {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }

    static func resolve(preferredLanguages: [String]) -> Self {
        for language in preferredLanguages {
            if language.lowercased().hasPrefix("zh") { return .traditionalChinese }
            if language.lowercased().hasPrefix("en") { return .english }
        }
        return .english
    }

    var firebaseLanguageCode: String { self == .traditionalChinese ? "zh-TW" : "en" }
    var locale: Locale { Locale(identifier: rawValue) }

    func text(_ key: String, table: String = "Authentication") -> String {
#if SWIFT_PACKAGE
        let resources = Bundle.module
#else
        let resources = Bundle.main
#endif
        guard let path = resources.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: table)
    }
}

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case traditionalChinese = "zh-Hant"
    case english = "en"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L10n.text("跟隨系統")
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }
}

@Observable
final class AppLanguageSettings {
    static let shared = AppLanguageSettings()
    private let defaults: UserDefaults
    private var systemLanguage: AppLanguage
    var preference: AppLanguagePreference {
        didSet { defaults.set(preference.rawValue, forKey: "appLanguagePreference") }
    }
    var language: AppLanguage {
        AppLanguage(rawValue: preference.rawValue) ?? systemLanguage
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        systemLanguage = .systemDefault
        preference = AppLanguagePreference(rawValue: defaults.string(forKey: "appLanguagePreference") ?? "") ?? .system
    }
    func refreshSystemLanguage() { systemLanguage = .systemDefault }
}

/// Only app-owned copy is passed here. User content is inserted after translation.
enum L10n {
    static var locale: Locale { AppLanguageSettings.shared.language.locale }
    static func text(_ key: String) -> String {
        AppLanguageSettings.shared.language.text(key, table: "Localizable")
    }
    static func format(_ key: String, _ arguments: String...) -> String {
        interpolate(text(key), arguments: arguments)
    }
    static func interpolate(_ template: String, arguments: [String]) -> String {
        let pattern = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        var result = template
        // Replace back to front, so braces inside user content are never interpreted.
        for match in pattern.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let numberRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[numberRange]), arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }
}
