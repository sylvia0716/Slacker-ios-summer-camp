import Foundation

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
    let taskID: UUID
    let groupName: String
    let taskTitle: String
}

/// Reads the latest group summary written by the main app through the App Group.
enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.con.sylvia.group"
    static let snapshotKey = "widgetProgressSnapshot"
    static let todoSnapshotKey = "widgetTodoSnapshot"

    static var current: WidgetProgressSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetProgressSnapshot.self, from: data)
    }

    static var currentTodo: WidgetTodoSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: todoSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetTodoSnapshot.self, from: data)
    }
}

/// Uses the app override when selected; otherwise respects device language order.
enum WidgetLanguage {
    static var isChinese: Bool {
        let preference = UserDefaults(suiteName: WidgetSnapshotStore.appGroupIdentifier)?
            .string(forKey: "appLanguagePreference")
        if preference == "zh-Hant" { return true }
        if preference == "en" { return false }
        return Locale.preferredLanguages.first(where: {
            $0.lowercased().hasPrefix("zh") || $0.lowercased().hasPrefix("en")
        })?.lowercased().hasPrefix("zh") ?? false
    }
    static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }
}
