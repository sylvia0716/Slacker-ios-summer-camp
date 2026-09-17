import Foundation

/// Shared in-memory language selection; defaults to the device language at launch.
enum AppLanguage: String, CaseIterable {
    case traditionalChinese = "zh-Hant"
    case english = "en"

    static var systemDefault: Self {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .traditionalChinese : .english
    }

    var firebaseLanguageCode: String { self == .traditionalChinese ? "zh-TW" : "en" }

    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Authentication")
    }
}
