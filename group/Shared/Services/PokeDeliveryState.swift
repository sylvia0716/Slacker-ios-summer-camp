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
