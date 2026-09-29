import Foundation
import Observation

/// One account-scoped source of truth for notification history and read state.
@MainActor @Observable
final class NotificationInboxStore {
    private(set) var items: [InboxNotification] = []
    private(set) var accountID: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var knownIDs: Set<String> = []

    var unreadCount: Int { items.lazy.filter { !$0.isRead }.count }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func changeAccount(to uid: String?) {
        guard uid != accountID else { return }
        accountID = uid
        items = []
        knownIDs = []
        guard let key = storageKey, let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([InboxNotification].self, from: data) else { return }
        items = saved
        knownIDs = Set(saved.map(\.id))
    }

    func receive(_ notifications: [InboxNotification], for uid: String) {
        guard uid == accountID else { return }
        let added = notifications.filter { knownIDs.insert($0.id).inserted }
        guard !added.isEmpty else { return }
        items.append(contentsOf: added)
        items.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
        save()
    }

    func receiveApplications(_ requests: [GroupJoinRequest], incoming: Bool, uid: String) {
        guard uid == accountID else { return }
        // A final decision supersedes the applicant's old "pending" unread badge.
        let completed = Set(requests.filter { $0.status != .pending }.map(\.requestID))
        if !incoming {
            markRead(ids: Set(items.filter {
                $0.kind == .applicationPending && completed.contains($0.relatedID ?? "")
            }.map(\.id)))
        }
        receive(requests.map { .application($0, incoming: incoming) }, for: uid)
    }

    func reconcileAdmissionReviews(groupID: String, pendingIDs: Set<String>, uid: String) {
        guard uid == accountID else { return }
        markRead(ids: Set(items.filter {
            $0.kind == .admissionReview && $0.groupID == groupID
                && !pendingIDs.contains($0.relatedID ?? "")
        }.map(\.id)))
    }

    func receivePoke(count: Int, groupID: String, groupName: String, uid: String, at date: Date = .now) {
        guard count > 10 else { return }
        receive([InboxNotification(id: "poke-threshold.\(groupID)", kind: .pokeThreshold,
                                   groupID: groupID, groupName: groupName, createdAt: date)], for: uid)
    }

    func receiveReminders(_ reminders: [DeadlineReminder], groups: [Group], tasks: [ProjectTask],
                          uid: String, now: Date) {
        let events = reminders.filter { $0.fireDate <= now }.compactMap { reminder -> InboxNotification? in
            guard let group = groups.first(where: { $0.id == reminder.groupID }) else { return nil }
            let kind: InboxNotification.Kind = reminder.opensPeerReview
                ? (reminder.id.hasSuffix(".0") ? .reviewAvailable : .reviewReminder)
                : (reminder.taskID == nil ? .projectDeadline : .taskDeadline)
            let task = tasks.first { $0.id == reminder.taskID }
            return InboxNotification(
                id: "\(reminder.id).\(Int(reminder.fireDate.timeIntervalSince1970))",
                kind: kind, groupID: group.id.uuidString, groupName: group.name,
                subject: task?.title ?? group.name, relatedID: reminder.taskID?.uuidString,
                eventDate: task?.deadline ?? group.deadline, createdAt: reminder.fireDate
            )
        }
        receive(events, for: uid)
    }

    func markRead(id: String) { markRead(ids: [id]) }
    func markAllRead() { markRead(ids: Set(items.map(\.id))) }

    private func markRead(ids: Set<String>) {
        var changed = false
        for index in items.indices where ids.contains(items[index].id) && !items[index].isRead {
            items[index].isRead = true
            changed = true
        }
        if changed { save() }
    }

    private var storageKey: String? { accountID.map { "notifications.inbox.\($0)" } }

    private func save() {
        guard let key = storageKey, let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
}
