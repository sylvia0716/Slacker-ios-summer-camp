import Foundation

/// A tick the user made on the widget that the app still has to push to the backend.
///
/// The widget extension cannot talk to Firebase, so completing a subtask from the Home
/// Screen is recorded here and replayed by the app the next time it becomes active.
struct WidgetTodoAction: Codable, Equatable {
    let subtaskID: UUID
    let taskID: UUID
    let requestedAt: Date

    /// Pending ticks are hidden from the widget. Stop hiding after a while so a tick that can
    /// never be replayed (task deleted while offline, say) stops hiding a real to-do.
    static let expiry: TimeInterval = 15 * 60

    /// How long the app still replays a tick. Much longer than `expiry`, so opening the app
    /// late does not lose a completion the user made on the Home Screen.
    static let replayExpiry: TimeInterval = 7 * 24 * 60 * 60

    func isStale(at date: Date = .now, after interval: TimeInterval = Self.expiry) -> Bool {
        date.timeIntervalSince(requestedAt) > interval
    }
}

/// Pending widget ticks, stored in the App Group so both processes see the same queue.
///
/// Each tick lives under its own key, so the app and the widget never rewrite each other's
/// entries and a tick made while the app is replaying cannot be lost.
enum WidgetTodoActionQueue {
    private static let keyPrefix = WidgetSharedConfig.todoActionQueueKey + "."

    static func pending() -> [WidgetTodoAction] {
        guard let defaults = WidgetSharedConfig.defaults else { return [] }
        return defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(keyPrefix) }
            .compactMap { ($0.value as? Data).flatMap { try? JSONDecoder().decode(WidgetTodoAction.self, from: $0) } }
    }

    /// Subtasks the app should treat as already completed, so a republished snapshot does not
    /// resurrect a row the user already ticked off on the Home Screen.
    static func pendingSubtaskIDs(at date: Date = .now) -> Set<UUID> {
        Set(pending().filter { !$0.isStale(at: date) }.map(\.subtaskID))
    }

    /// Called from the widget. Re-ticking the same subtask keeps the original timestamp so a
    /// repeated tap cannot extend the window in which the row stays hidden.
    static func enqueue(_ action: WidgetTodoAction) {
        guard let defaults = WidgetSharedConfig.defaults else { return }
        let key = keyPrefix + action.subtaskID.uuidString
        guard defaults.data(forKey: key) == nil,
              let data = try? JSONEncoder().encode(action) else { return }
        defaults.set(data, forKey: key)
    }

    static func remove(subtaskIDs: Set<UUID>) {
        guard let defaults = WidgetSharedConfig.defaults else { return }
        for id in subtaskIDs {
            defaults.removeObject(forKey: keyPrefix + id.uuidString)
        }
    }
}
