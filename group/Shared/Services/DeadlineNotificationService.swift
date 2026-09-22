import Foundation
import OSLog
import UserNotifications

@MainActor
final class DeadlineNotificationService {
    static let shared = DeadlineNotificationService()
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "con.sylvia.group", category: "DeadlineReminders")
    private var updateTask: Task<Void, Never>?

    /// A nil plan preserves this account's existing schedule while cloud data is loading/offline.
    func update(uid: String?, enabled: Bool, plan: [DeadlineReminder]?, categories: NotificationCategories = .init()) {
        let previous = updateTask
        previous?.cancel()
        updateTask = Task {
            // Serialize writes: an older in-flight add must finish before a newer update removes it.
            await previous?.value
            guard !Task.isCancelled else { return }
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            let owned = pending.filter { $0.identifier.hasPrefix(DeadlineReminderPlan.identifierPrefix) }
            func allows(_ request: UNNotificationRequest) -> Bool {
                categories.allowsReminder(isReview: request.content.userInfo["destination"] as? String == "peerReview",
                                          isTask: request.content.userInfo["taskID"] != nil)
            }
            let obsolete = owned.filter {
                !enabled || !allows($0) || uid == nil || $0.content.userInfo["recipientUID"] as? String != uid
            }
            center.removePendingNotificationRequests(withIdentifiers: obsolete.map(\.identifier))

            let delivered = await center.deliveredNotifications()
            guard !Task.isCancelled else { return }
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
                $0.request.identifier.hasPrefix(DeadlineReminderPlan.identifierPrefix)
                    && (!enabled || !allows($0.request) || uid == nil || $0.request.content.userInfo["recipientUID"] as? String != uid)
            }.map { $0.request.identifier })
            guard enabled, let uid, let plan else { return }

            let settings = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                center.removePendingNotificationRequests(withIdentifiers: owned.map(\.identifier))
                return
            }

            // Keep a bounded queue of the nearest reminders and leave room for poke notifications.
            let otherCount = pending.count - owned.count
            let desired = Array(plan.filter { $0.fireDate > .now && categories.allowsReminder(isReview: $0.opensPeerReview, isTask: $0.taskID != nil) }.prefix(max(0, 60 - otherCount)))
            let desiredIDs = Set(desired.map(\.id))
            center.removePendingNotificationRequests(withIdentifiers: owned.filter {
                !desiredIDs.contains($0.identifier)
            }.map(\.identifier))

            for reminder in desired {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                content.userInfo = ["recipientUID": uid, "groupID": reminder.groupID.uuidString,
                                    "fireTimestamp": reminder.fireDate.timeIntervalSince1970]
                if let taskID = reminder.taskID { content.userInfo["taskID"] = taskID.uuidString }
                if reminder.opensPeerReview { content.userInfo["destination"] = "peerReview" }
                if let existing = owned.first(where: { $0.identifier == reminder.id }),
                   existing.content.title == content.title, existing.content.body == content.body,
                   existing.content.userInfo["fireTimestamp"] as? Double == reminder.fireDate.timeIntervalSince1970 {
                    continue
                }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
                var triggerDate = components
                triggerDate.timeZone = calendar.timeZone
                let request = UNNotificationRequest(identifier: reminder.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false))
                do { try await center.add(request) }
                catch { logger.error("Could not schedule deadline reminder: \(error.localizedDescription, privacy: .public)") }
            }
            logger.info("Reconciled \(desired.count) deadline reminders")
        }
    }
}
