import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct ReviewReminderTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let memberID = UUID()
    let teammateID = UUID()

    func group(hours: Double = 48) -> Group {
        Group(id: UUID(), name: "期末專案", deadline: now.addingTimeInterval(hours * 3600),
              memberIDs: [memberID, teammateID], taskIDs: [], inviteCode: "TEST01")
    }

    func reviews(_ group: Group, completed: Set<UUID> = []) -> [DeadlineReminder] {
        DeadlineReminderPlan.make(groups: [group], tasks: [], memberID: memberID,
            uid: "A", now: now, completedReviewGroupIDs: completed).filter(\.opensPeerReview)
    }

    @Test func openingAndOneFollowUpOnly() {
        let group = group()
        let result = reviews(group)
        #expect(result.map(\.fireDate) == [group.deadline, group.deadline.addingTimeInterval(86400)])
        #expect(result.allSatisfy { $0.groupID == group.id && $0.taskID == nil })
        #expect(reviews(self.group(hours: -2)).count == 1)
        #expect(reviews(self.group(hours: -25)).isEmpty)
    }

    @Test func completionAndMembershipExcludeReminders() {
        var group = group()
        #expect(reviews(group, completed: [group.id]).isEmpty)
        group.memberIDs = [memberID]
        #expect(reviews(group).isEmpty)
        group.memberIDs = [teammateID]
        #expect(reviews(group).isEmpty)
    }

    @Test func deadlineEditsReplaceExistingIdentifiers() {
        var group = group()
        let old = reviews(group)
        group.deadline = group.deadline.addingTimeInterval(3600)
        let new = reviews(group)
        #expect(old.map(\.id) == new.map(\.id))
        #expect(new[0].fireDate == old[0].fireDate.addingTimeInterval(3600))
    }

    @Test func completionSurvivesRestartButIsIsolatedByAccountAndGroup() {
        let suite = "ReviewReminderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let group = group()
        ReviewReminderState(defaults: defaults).recordCompletion(uid: "A", groupID: group.id, revieweeIDs: [teammateID])
        let restored = ReviewReminderState(defaults: defaults)
        #expect(restored.isComplete(uid: "A", groupID: group.id, revieweeIDs: [teammateID]))
        #expect(!restored.isComplete(uid: "B", groupID: group.id, revieweeIDs: [teammateID]))
        #expect(!restored.isComplete(uid: "A", groupID: UUID(), revieweeIDs: [teammateID]))
        #expect(!restored.isComplete(uid: "A", groupID: group.id, revieweeIDs: [teammateID, UUID()]))
        restored.clear(uid: "A", groupID: group.id)
        #expect(!restored.isComplete(uid: "A", groupID: group.id, revieweeIDs: [teammateID]))
    }

    @Test func destinationRequiresReviewPayload() {
        let id = UUID()
        let payload: [AnyHashable: Any] = ["destination": "peerReview", "recipientUID": "A", "groupID": id.uuidString]
        let destination = ReviewNotificationDestination(userInfo: payload)
        #expect(destination?.uid == "A")
        #expect(destination?.groupID == id)
        #expect(ReviewNotificationDestination(userInfo: ["groupID": id.uuidString]) == nil)
        #expect(ReviewNotificationDestination(userInfo: ["destination": "peerReview", "recipientUID": "A", "groupID": "bad"]) == nil)
        #expect(ReviewNotificationRoute(groupID: id) != ReviewNotificationRoute(groupID: id))
    }
}
