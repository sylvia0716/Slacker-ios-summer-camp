import Foundation

/// Reads the latest to-do summary written by the main app through the App Group.
/// The payload types live in `WidgetShared` so this side cannot drift from the writer.
enum WidgetSnapshotStore {
    static func loadTodo(at date: Date = .now) -> WidgetTodoLoad {
        guard let data = WidgetSharedConfig.defaults?.data(forKey: WidgetSharedConfig.todoSnapshotKey)
        else { return .missing }
        guard let snapshot = try? JSONDecoder().decode(WidgetTodoSnapshot.self, from: data)
        else { return .unreadable }
        guard snapshot.schemaVersion <= WidgetTodoSnapshot.currentSchemaVersion
        else { return .unreadable }

        // Hide rows the user already ticked on the Home Screen but the app has not replayed yet.
        let pending = WidgetTodoActionQueue.pendingSubtaskIDs(at: date)
        guard !pending.isEmpty else { return .loaded(snapshot) }
        let items = snapshot.items.filter { !pending.contains($0.id) }
        let hidden = snapshot.items.count - items.count
        return .loaded(WidgetTodoSnapshot(count: max(0, snapshot.count - hidden), items: items))
    }
}

/// Uses the app override when selected; otherwise respects device language order.
enum WidgetLanguage {
    static var isChinese: Bool {
        let preference = WidgetSharedConfig.defaults?
            .string(forKey: WidgetSharedConfig.languagePreferenceKey)
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
