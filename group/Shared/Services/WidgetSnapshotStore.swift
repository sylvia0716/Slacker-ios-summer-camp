import Foundation
import WidgetKit

/// Keeps the current user's unfinished subtasks available to the widget extension.
/// The payload types live in `WidgetShared`, which both targets compile.
enum WidgetSnapshotStore {
    /// Removed in favour of the to-do widget; cleared so the old payload stops taking up
    /// space in the shared container.
    private static let retiredProgressSnapshotKey = "widgetProgressSnapshot"

    static func updateLanguage() {
        guard let defaults = WidgetSharedConfig.defaults else { return }
        let preference = AppLanguageSettings.shared.preference.rawValue
        guard defaults.string(forKey: WidgetSharedConfig.languagePreferenceKey) != preference else { return }
        defaults.set(preference, forKey: WidgetSharedConfig.languagePreferenceKey)
        reloadWidget()
    }

    /// Writes the snapshot and reloads the widget only when the payload actually changed.
    /// WidgetKit budgets daily reloads, and the store is written from several `didSet`
    /// observers, so an unconditional reload would burn through that budget.
    static func saveTodo(_ snapshot: WidgetTodoSnapshot) {
        guard let defaults = WidgetSharedConfig.defaults,
              let data = try? JSONEncoder().encode(snapshot) else { return }

        defaults.removeObject(forKey: retiredProgressSnapshotKey)

        // Encoding is deterministic for this payload, so comparing bytes is enough and
        // avoids decoding the stored snapshot on every task mutation.
        guard defaults.data(forKey: WidgetSharedConfig.todoSnapshotKey) != data else { return }

        defaults.set(data, forKey: WidgetSharedConfig.todoSnapshotKey)
        reloadWidget()
    }

    private static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConfig.todoWidgetKind)
    }
}
