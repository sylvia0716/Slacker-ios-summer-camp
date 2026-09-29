import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct NotificationInboxTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func request(_ status: GroupJoinRequest.Status = .pending,
                         requestID: String = "request-1") -> GroupJoinRequest {
        GroupJoinRequest(requestID: requestID, groupID: "group-1", groupName: "Project",
                         applicantID: "applicant", applicantName: "Alex", requestedAt: now,
                         status: status, reviewedAt: status == .pending ? nil : now.addingTimeInterval(60))
    }

    private func withStore(_ body: (NotificationInboxStore, UserDefaults) throws -> Void) rethrows {
        let suite = "NotificationInboxTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationInboxStore(defaults: defaults)
        store.changeAccount(to: "A")
        try body(store, defaults)
    }

    @Test func repeatedSnapshotsAndRelaunchPreserveReadState() {
        withStore { store, defaults in
            store.receiveApplications([request()], incoming: false, uid: "A")
            #expect(store.unreadCount == 1)
            store.markRead(id: store.items[0].id)
            store.receiveApplications([request()], incoming: false, uid: "A")
            #expect(store.items.count == 1)
            #expect(store.unreadCount == 0)
            let restored = NotificationInboxStore(defaults: defaults)
            restored.changeAccount(to: "A")
            restored.receiveApplications([request()], incoming: false, uid: "A")
            #expect(restored.items.count == 1)
            #expect(restored.unreadCount == 0)
        }
    }

    @Test func decisionsAndReapplicationsEachNotifyOnce() {
        withStore { store, _ in
            store.receiveApplications([request()], incoming: false, uid: "A")
            store.receiveApplications([request(.rejected)], incoming: false, uid: "A")
            #expect(store.items.count == 2)
            #expect(store.unreadCount == 1)
            #expect(store.items.first?.kind == .applicationRejected)
            #expect(store.items.first?.createdAt == now.addingTimeInterval(60))
            store.markAllRead()
            store.receiveApplications([request(.pending, requestID: "request-2")], incoming: false, uid: "A")
            #expect(store.items.count == 3)
            #expect(store.unreadCount == 1)
            store.receiveApplications([request(.approved, requestID: "request-2")], incoming: false, uid: "A")
            #expect(store.items.count == 4)
            #expect(store.unreadCount == 1)
        }
    }

    @Test func accountSwitchRejectsLateCallbacksAndRestoresTheRightHistory() {
        withStore { store, _ in
            store.receiveApplications([request()], incoming: false, uid: "A")
            store.markAllRead()
            store.changeAccount(to: "B")
            #expect(store.items.isEmpty)
            store.receiveApplications([request(.approved)], incoming: false, uid: "A")
            #expect(store.items.isEmpty)
            store.receiveApplications([request()], incoming: true, uid: "B")
            #expect(store.items.first?.kind == .admissionReview)
            store.changeAccount(to: nil)
            #expect(store.items.isEmpty)
            store.changeAccount(to: "A")
            #expect(store.items.count == 1)
            #expect(store.items.first?.kind == .applicationPending)
            #expect(store.unreadCount == 0)
        }
    }

    @Test func pokeThresholdStartsAtElevenAndDoesNotRepeat() {
        withStore { store, _ in
            for count in [1, 9, 10] {
                store.receivePoke(count: count, groupID: "one", groupName: "Project", uid: "A", at: now)
            }
            #expect(store.items.isEmpty)
            store.receivePoke(count: 11, groupID: "one", groupName: "Project", uid: "A", at: now)
            store.markAllRead()
            for count in [11, 12, 20, 100] {
                store.receivePoke(count: count, groupID: "one", groupName: "Project", uid: "A", at: now)
            }
            #expect(store.items.count == 1)
            #expect(store.unreadCount == 0)
            store.receivePoke(count: 11, groupID: "two", groupName: "Other", uid: "A", at: now)
            #expect(store.items.count == 2)
            #expect(store.unreadCount == 1)
        }
    }

    @Test func deadlineRefreshOnlyAddsDueRemindersAndReschedulingCanNotifyAgain() {
        withStore { store, _ in
            let memberID = UUID()
            let group = Group(id: UUID(), name: "Project", deadline: now.addingTimeInterval(3600),
                              memberIDs: [memberID], taskIDs: [], inviteCode: "TEST01")
            func reminder(_ fireDate: Date) -> DeadlineReminder {
                DeadlineReminder(id: "deadline-reminder.A.project.1", title: "", body: "",
                                 fireDate: fireDate, groupID: group.id, taskID: nil)
            }
            let due = reminder(now)
            let future = reminder(now.addingTimeInterval(60))
            store.receiveReminders([future], groups: [group], tasks: [], uid: "A", now: now)
            #expect(store.items.isEmpty)
            store.receiveReminders([due], groups: [group], tasks: [], uid: "A", now: now)
            store.markAllRead()
            store.receiveReminders([due], groups: [group], tasks: [], uid: "A", now: now)
            #expect(store.items.count == 1)
            #expect(store.unreadCount == 0)
            store.receiveReminders([future], groups: [group], tasks: [], uid: "A", now: future.fireDate)
            #expect(store.items.count == 2)
            #expect(store.unreadCount == 1)
        }
    }

    @Test func meetingReminderReplayDoesNotMakeReadItemUnread() {
        withStore { store, _ in
            let item = InboxNotification(id: "meeting.group.server-event", kind: .meeting,
                groupID: "group", groupName: "Project", subject: "Planning",
                eventDate: now.addingTimeInterval(1800), createdAt: now)
            store.receive([item, item], for: "A")
            store.markAllRead()
            store.receive([item], for: "A")
            #expect(store.items.count == 1)
            #expect(store.unreadCount == 0)
            let rescheduled = InboxNotification(id: "meeting.group.rescheduled-event", kind: .meeting,
                groupID: "group", groupName: "Project", subject: "Planning",
                eventDate: now.addingTimeInterval(3600), createdAt: now)
            store.receive([rescheduled], for: "A")
            #expect(store.unreadCount == 1)
        }
    }

    @Test func handledApplicationsClearOnlyTheirOwnGroupsUnreadBadge() {
        withStore { store, _ in
            store.receiveApplications([request()], incoming: true, uid: "A")
            let other = GroupJoinRequest(requestID: "other", groupID: "group-2", groupName: "Other",
                applicantID: "applicant", applicantName: "Alex", requestedAt: now, status: .pending)
            store.receiveApplications([other], incoming: true, uid: "A")
            store.reconcileAdmissionReviews(groupID: "group-1", pendingIDs: [], uid: "A")
            #expect(store.unreadCount == 1)
            #expect(store.items.first(where: { $0.groupID == "group-1" })?.isRead == true)
            #expect(store.items.first(where: { $0.groupID == "group-2" })?.isRead == false)
            store.reconcileAdmissionReviews(groupID: "group-2", pendingIDs: [], uid: "old-account")
            #expect(store.unreadCount == 1)
        }
    }
}
