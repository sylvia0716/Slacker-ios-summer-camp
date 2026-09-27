import Foundation
import WidgetKit

/// The compact, cross-process payload used by the Home Screen widget.
struct WidgetProgressSnapshot: Codable {
    let groupName: String
    let progress: Int
    let deadline: Date
}

struct WidgetTodoSnapshot: Codable {
    let count: Int
    let items: [WidgetTodoItem]
}

struct WidgetTodoItem: Codable, Identifiable {
    let id: UUID
    let title: String
}

/// Keeps the app's selected group summary available to the widget extension.
enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.con.sylvia.group"
    static let snapshotKey = "widgetProgressSnapshot"
    static let widgetKind = "GroupProgressWidget"
    static let todoSnapshotKey = "widgetTodoSnapshot"
    static let todoWidgetKind = "MyTasksTodoWidget"

    static func updateLanguage() {
        UserDefaults(suiteName: appGroupIdentifier)?.set(
            AppLanguageSettings.shared.preference.rawValue, forKey: "appLanguagePreference")
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: todoWidgetKind)
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

    static func saveTodo(_ snapshot: WidgetTodoSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: todoSnapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: todoWidgetKind)
    }
}
