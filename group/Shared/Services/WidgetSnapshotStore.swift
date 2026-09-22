import Foundation
import WidgetKit

/// The compact, cross-process payload used by the Home Screen widget.
struct WidgetProgressSnapshot: Codable {
    let groupName: String
    let progress: Int
    let deadline: Date
}

/// Keeps the app's selected group summary available to the widget extension.
enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.con.sylvia.group"
    static let snapshotKey = "widgetProgressSnapshot"
    static let widgetKind = "GroupProgressWidget"

    static func updateLanguage() {
        UserDefaults(suiteName: appGroupIdentifier)?.set(
            AppLanguageSettings.shared.preference.rawValue, forKey: "appLanguagePreference")
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func save(_ snapshot: WidgetProgressSnapshot?) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        } else {
            defaults.removeObject(forKey: snapshotKey)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
