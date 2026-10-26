import Foundation

/// Shared by the app and the widget extension. Both targets compile this file, so the
/// payload written by `WidgetSnapshotStore` and the payload read by the widget can never
/// drift apart. Changing a field here changes both sides at once — if the shape has to
/// change in a way old data cannot satisfy, bump `currentSchemaVersion`.
struct WidgetTodoSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    /// Total number of unfinished subtasks, which can exceed `items.count`.
    let count: Int
    /// The leading slice the widget is allowed to render.
    let items: [WidgetTodoItem]
    let schemaVersion: Int

    init(count: Int, items: [WidgetTodoItem], schemaVersion: Int = Self.currentSchemaVersion) {
        self.count = count
        self.items = items
        self.schemaVersion = schemaVersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decode(Int.self, forKey: .count)
        items = try container.decode([WidgetTodoItem].self, forKey: .items)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }

    static let empty = WidgetTodoSnapshot(count: 0, items: [])
}

struct WidgetTodoItem: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let taskID: UUID
    let groupName: String
    let taskTitle: String
}

/// Distinguishes "the user genuinely has nothing to do" from "the stored payload could not
/// be read", so the widget never reports an empty to-do list after a decoding failure.
enum WidgetTodoLoad: Equatable {
    case missing
    case unreadable
    case loaded(WidgetTodoSnapshot)

    var snapshot: WidgetTodoSnapshot? {
        guard case let .loaded(snapshot) = self else { return nil }
        return snapshot
    }
}

/// Identifiers shared across the process boundary.
enum WidgetSharedConfig {
    /// Historical spelling — `con` is a typo for `com`, but the identifier is registered with
    /// this value in the provisioning profile, so renaming it requires a Developer Portal
    /// change plus a one-time migration of the stored payload.
    static let appGroupIdentifier = "group.con.sylvia.group"
    static let todoSnapshotKey = "widgetTodoSnapshot"
    static let todoActionQueueKey = "widgetTodoActionQueue"
    static let languagePreferenceKey = "appLanguagePreference"
    static let todoWidgetKind = "MyTasksTodoWidget"

    /// Held onto rather than rebuilt per access: the store is read from `didSet` observers
    /// that fire on every task mutation.
    static let defaults = UserDefaults(suiteName: appGroupIdentifier)
}
