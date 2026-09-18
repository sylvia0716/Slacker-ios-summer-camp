import Foundation

/// Notification-only completion receipts; does not store scores or comments.
@MainActor
final class ReviewReminderState {
    static let shared = ReviewReminderState()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func recordCompletion(uid: String, groupID: UUID, revieweeIDs: Set<UUID>) {
        defaults.set(revieweeIDs.map(\.uuidString), forKey: key(uid, groupID))
    }

    func isComplete(uid: String, groupID: UUID, revieweeIDs: Set<UUID>) -> Bool {
        let completed = Set((defaults.stringArray(forKey: key(uid, groupID)) ?? []).compactMap(UUID.init(uuidString:)))
        return revieweeIDs.isSubset(of: completed)
    }

    func clear(uid: String, groupID: UUID) { defaults.removeObject(forKey: key(uid, groupID)) }

    private func key(_ uid: String, _ groupID: UUID) -> String {
        "reviewReminder.completed.\(uid).\(groupID.uuidString)"
    }
}
