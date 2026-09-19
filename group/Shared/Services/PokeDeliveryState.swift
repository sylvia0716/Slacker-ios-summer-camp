import Foundation

/// Device-local delivery checkpoints, shared by foreground reception and background refresh.
@MainActor
final class PokeDeliveryState {
    static let shared = PokeDeliveryState()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: "poke.notificationsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "poke.notificationsEnabled") }
    }

    var categories: NotificationCategories {
        get {
            let values = defaults.dictionary(forKey: "notifications.categories") as? [String: Bool] ?? [:]
            return NotificationCategories(pokes: values["pokes"] ?? true,
                tasks: values["tasks"] ?? true, projects: values["projects"] ?? true,
                reviews: values["reviews"] ?? true)
        }
        set {
            defaults.set(["pokes": newValue.pokes, "tasks": newValue.tasks,
                          "projects": newValue.projects, "reviews": newValue.reviews],
                         forKey: "notifications.categories")
        }
    }

    var receivesPokes: Bool { notificationsEnabled && categories.pokes }

    /// The first server snapshot establishes a baseline instead of replaying old history.
    func unseenCount(latestCount: Int, uid: String, groupID: String) -> Int {
        let counts = checkpoints(for: uid)
        guard let previous = counts[groupID] else {
            markHandled(count: latestCount, uid: uid, groupID: groupID)
            return 0
        }
        return max(0, latestCount - previous)
    }

    func markHandled(count: Int, uid: String, groupID: String) {
        var counts = checkpoints(for: uid)
        counts[groupID] = max(counts[groupID] ?? 0, count)
        defaults.set(counts, forKey: "poke.handledCounts.\(uid)")
    }

    private func checkpoints(for uid: String) -> [String: Int] {
        defaults.dictionary(forKey: "poke.handledCounts.\(uid)") as? [String: Int] ?? [:]
    }
}

struct NotificationCategories: Equatable {
    var pokes = true
    var tasks = true
    var projects = true
    var reviews = true

    func allowsReminder(isReview: Bool, isTask: Bool) -> Bool {
        isReview ? reviews : (isTask ? tasks : projects)
    }
}
