import Foundation

/// A server-authored snapshot at reminder time; viewers render it in their selected language.
struct AgendaChatSummary: Codable {
    let topic: String
    let meetingAtMillis: Double
    let duration: Int
    let preparedNames: [String]
    let missingNames: [String]
    let discussionTitles: [String]
    let discussionTitlesZhHant: [String]

    var localizedText: String {
        let date = Date(timeIntervalSince1970: meetingAtMillis / 1_000)
            .formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))
        var parts = [L10n.format("會前提醒：「{0}」將於 {1} 開始，預計 {2} 分鐘。", topic, date, String(duration))]
        if !preparedNames.isEmpty {
            parts.append(L10n.format("會前資料已提交 {0}/{1} 人（{2}）。",
                                     String(preparedNames.count), String(preparedNames.count + missingNames.count), names(preparedNames)))
        }
        parts.append(missingNames.isEmpty
                     ? L10n.text("全員已完成會前準備。")
                     : L10n.format("尚未提交筆記或附件：{0}。", names(missingNames)))
        let titles = AppLanguageSettings.shared.language == .traditionalChinese ? discussionTitlesZhHant : discussionTitles
        if !titles.isEmpty {
            parts.append(L10n.format("討論重點：{0}。", titles.formatted(.list(type: .and).locale(L10n.locale))))
        }
        return parts.joined(separator: " ")
    }

    private func names(_ names: [String]) -> String {
        let visible = Array(names.prefix(4)).formatted(.list(type: .and).locale(L10n.locale))
        return names.count > 4 ? L10n.format("{0}等 {1} 人", visible, String(names.count)) : visible
    }
}
