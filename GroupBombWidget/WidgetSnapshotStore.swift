import Foundation

/// The compact, cross-process payload used by the Home Screen widget.
struct WidgetProgressSnapshot: Codable {
    let groupName: String
    let progress: Int
    let deadline: Date
}

/// Reads the latest group summary written by the main app through the App Group.
enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.con.sylvia.group"
    static let snapshotKey = "widgetProgressSnapshot"

    static var current: WidgetProgressSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetProgressSnapshot.self, from: data)
    }
}
