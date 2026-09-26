import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct GroupRepositoryTests {
    let groupID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let taskID = "22222222-2222-4222-8222-222222222222"
    var summary: CloudGroupSummary {
        CloudGroupSummary(id: groupID, name: "Team", deadline: Date(timeIntervalSince1970: 1234), inviteCode: "TEST")
    }
    func member(_ uid: String, role: MemberRole = .member) -> CloudDocument<CloudMemberDocument> {
        CloudDocument(id: uid, value: CloudMemberDocument(userID: uid, role: role, joinedAt: .distantPast))
    }
    func task(owner: String? = "firebase-A") -> CloudDocument<CloudTaskDocument> {
        CloudDocument(id: taskID, value: CloudTaskDocument(title: "Task", ownerMemberID: owner))
    }

    @Test func stableUIDMapping() {
        #expect(FirebaseMemberIdentity.uiID(for: "firebase-A") == FirebaseMemberIdentity.uiID(for: "firebase-A"))
        #expect(FirebaseMemberIdentity.uiID(for: "firebase-A") != FirebaseMemberIdentity.uiID(for: "firebase-B"))
    }
    @Test func mapsTasksAndMembersIntoSharedIDs() throws {
        let result = try GroupRepository.map(summary, members: [member("firebase-A", role: .leader)], tasks: [task()], currentUID: "firebase-A")
        #expect(result.members[0].firebaseUID == "firebase-A")
        #expect(result.tasks[0].ownerMemberID == result.members[0].id)
        #expect(result.group.memberRoles[result.members[0].id] == .leader)
        #expect(result.group.taskIDs == [UUID(uuidString: taskID)!])
        #expect(result.tasks[0].firestoreDocumentID == taskID)
        #expect(result.tasks[0].subtasks.isEmpty)
    }
    @Test func departedOwnerDoesNotBreakRemainingMembersTasks() throws {
        let result = try GroupRepository.map(summary, members: [member("firebase-A")],
            tasks: [task(owner: "departed-member")], currentUID: "firebase-A")
        #expect(result.tasks.count == 1)
        #expect(result.tasks[0].ownerMemberID == nil)
    }
    @Test func rejoinedMemberDoesNotReclaimArchivedTask() throws {
        let archived = CloudTaskDocument(title: "Old task", departureID: "departure",
            departedMemberName: "Member", departedProgress: 25, includedInProgress: false,
            departureReviewed: true)
        let result = try GroupRepository.map(summary, members: [member("firebase-A")],
            tasks: [CloudDocument(id: taskID, value: archived)], currentUID: "firebase-A")
        #expect(result.tasks[0].ownerMemberID == nil)
        #expect(result.tasks[0].progress == 25)
        #expect(result.tasks[0].includedInProgress == false)
        #expect(result.tasks[0].departureReviewed)
        #expect(result.tasks[0].departureID == "departure")
    }

    @Test func mapsElectionAndVotesWithoutInventingLeader() throws {
        var a = member("firebase-A").value
        a.leaderElectionID = "election"
        a.leaderVoteUID = "firebase-B"
        var b = member("firebase-B").value
        b.leaderElectionID = "election"
        b.leaderVoteUID = "departed"
        let result = try GroupRepository.map(summary,
            members: [CloudDocument(id: "firebase-A", value: a), CloudDocument(id: "firebase-B", value: b)],
            tasks: [], currentUID: "firebase-A")
        #expect(result.group.leaderElectionID == "election")
        #expect(result.group.leaderVotes.count == 1)
        #expect(result.group.leaderVotes[FirebaseMemberIdentity.uiID(for: "firebase-A")] == FirebaseMemberIdentity.uiID(for: "firebase-B"))
        #expect(!result.group.memberRoles.values.contains(.leader))
    }

    @Test func rejectsMismatchedMemberDocument() {
        let forged = CloudDocument(id: "firebase-A", value: member("firebase-B").value)
        #expect(throws: GroupLoadError.self) {
            try GroupRepository.map(summary, members: [forged], tasks: [], currentUID: "firebase-A")
        }
    }
    @Test func rejectsInvalidTaskID() {
        #expect(throws: GroupLoadError.self) {
            try GroupRepository.map(summary, members: [member("firebase-A")], tasks: [CloudDocument(id: "fake-task", value: task().value)], currentUID: "firebase-A")
        }
    }
    @Test func decodesFirestoreDocumentShape() throws {
        let json = Data(#"{"title":"Report","ownerMemberID":"firebase-A","status":"pending","subtasks":[]}"#.utf8)
        let value = try JSONDecoder().decode(CloudTaskDocument.self, from: json)
        #expect(value.ownerMemberID == "firebase-A")
        #expect(value.subtasks == [])
    }
    @Test func repositoryReadsOnlyAccessibleGroupsInOrder() async throws {
        var calls: [String] = []
        let repository = GroupRepository(reads: .init(currentUID: { "firebase-A" }, summaries: { calls.append("list"); return [summary] }, members: { id in
            calls.append("members:" + id); return [member("firebase-A")]
        }, tasks: { id in calls.append("tasks:" + id); return [task()] }))
        let result = try await repository.load()
        #expect(result.count == 1)
        #expect(calls == ["list", "members:" + summary.pathID, "tasks:" + summary.pathID])
    }
    @Test func signedOutDoesNotRead() async {
        let repository = GroupRepository(reads: .init(currentUID: { nil }, summaries: { Issue.record("Unexpected read"); return [] }, members: { _ in [] }, tasks: { _ in [] }))
        await #expect(throws: GroupLoadError.self) { try await repository.load() }
    }
    @Test func accountSwitchDiscardsOldRequest() async {
        var uid = "firebase-A"
        let repository = GroupRepository(reads: .init(currentUID: { uid }, summaries: { [summary] }, members: { _ in
            uid = "firebase-B"; return [member("firebase-A")]
        }, tasks: { _ in Issue.record("Old account must not read tasks"); return [] }))
        await #expect(throws: GroupLoadError.self) { try await repository.load() }
    }
    @Test func networkFailureDoesNotProduceFakeTasks() async {
        let repository = GroupRepository(reads: .init(currentUID: { "firebase-A" }, summaries: { [summary] }, members: { _ in [member("firebase-A")] }, tasks: { _ in throw GroupLoadError.network }), wait: { _ in })
        await #expect(throws: GroupLoadError.self) { try await repository.load() }
    }
    @Test func emptyAccessibleListIsEmpty() async throws {
        let repository = GroupRepository(reads: .init(currentUID: { "firebase-A" }, summaries: { [] }, members: { _ in Issue.record("Unexpected read"); return [] }, tasks: { _ in [] }))
        #expect(try await repository.load().isEmpty)
    }
    @Test func fullAttachmentCollectionAndRemoval() throws {
        var attachment = TaskAttachment(id: UUID().uuidString, taskID: taskID, groupID: summary.pathID, uploaderID: "firebase-A", title: "one", kind: .externalLink, status: .ready)
        let second = TaskAttachment(id: UUID().uuidString, taskID: taskID, groupID: summary.pathID, uploaderID: "firebase-A", title: "two", kind: .pdf, status: .failed)
        var snapshot = try CloudAttachmentCollection([attachment, second], groupID: summary.pathID, taskID: taskID)
        #expect(snapshot.attachments.count == 2)
        attachment.title = "updated"
        snapshot = try CloudAttachmentCollection([attachment], groupID: summary.pathID, taskID: taskID)
        #expect(snapshot.latestDeliverable?.title == "updated")
        snapshot = try CloudAttachmentCollection([], groupID: summary.pathID, taskID: taskID)
        #expect(snapshot.attachments.isEmpty)
        #expect(snapshot.latestDeliverable == nil)
    }
    @Test func rejectsCrossTaskAttachment() {
        let attachment = TaskAttachment(taskID: "other-task", groupID: summary.pathID, uploaderID: "firebase-A", title: "wrong", kind: .pdf)
        #expect(throws: GroupLoadError.self) { try CloudAttachmentCollection([attachment], groupID: summary.pathID, taskID: taskID) }
    }

    @Test func preservesDifferentRolesAcrossGroups() throws {
        let first = try GroupRepository.map(summary, members: [member("firebase-A", role: .leader)], tasks: [], currentUID: "firebase-A")
        let other = CloudGroupSummary(id: UUID(), name: "Other", deadline: .distantFuture, inviteCode: "OTHER")
        let second = try GroupRepository.map(other, members: [member("firebase-A")], tasks: [], currentUID: "firebase-A")
        let id = first.members[0].id
        #expect(second.members[0].id == id)
        #expect(first.group.memberRoles[id] == .leader)
        #expect(second.group.memberRoles[id] == .member)
    }

    @Test func preservesOriginalDocumentPathCase() throws {
        let path = "ABCDEFAB-1111-4111-8111-111111111111"
        let summary = CloudGroupSummary(id: UUID(uuidString: path)!, name: "Case", deadline: .distantFuture, inviteCode: "CASE", documentID: path)
        let result = try GroupRepository.map(summary, members: [member("firebase-A")], tasks: [task()], currentUID: "firebase-A")
        #expect(result.group.firestoreDocumentID == path)
        #expect(result.tasks[0].firestoreGroupID == path)
    }

    @Test func rejectsDuplicateGroups() async {
        let repository = GroupRepository(reads: .init(currentUID: { "firebase-A" }, summaries: { [summary, summary] }, members: { _ in [member("firebase-A")] }, tasks: { _ in [] }))
        await #expect(throws: GroupLoadError.self) { try await repository.load() }
    }

    @Test func accountSwitchAfterEmptyListStillRejected() async {
        var uid = "firebase-A"
        let repository = GroupRepository(reads: .init(currentUID: { uid }, summaries: { uid = "firebase-B"; return [] }, members: { _ in [] }, tasks: { _ in [] }))
        await #expect(throws: GroupLoadError.self) { try await repository.load() }
    }

    @Test func cancellationStopsHydration() async {
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let repository = GroupRepository(reads: .init(currentUID: { "firebase-A" }, summaries: { [summary] }, members: { _ in Issue.record("Cancelled request continued"); return [] }, tasks: { _ in [] }))
            await #expect(throws: CancellationError.self) { try await repository.load() }
        }
        await operation.value
    }
}
