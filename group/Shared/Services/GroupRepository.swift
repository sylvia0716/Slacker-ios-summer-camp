import Foundation

/// One boundary for listing and hydrating groups. Injected reads also permit offline tests.
@MainActor
final class GroupRepository {
    struct Reads {
        var currentUID: () -> String?
        var summaries: () async throws -> [CloudGroupSummary]
        var members: (String) async throws -> [CloudDocument<CloudMemberDocument>]
        var tasks: (String) async throws -> [CloudDocument<CloudTaskDocument>]
    }
    private let reads: Reads
    init(reads: Reads) { self.reads = reads }

    func load() async throws -> [LoadedCloudGroup] {
        guard let uid = reads.currentUID() else { throw GroupLoadError.signedOut }
        let summaries = try await reads.summaries()
        guard Set(summaries.map(\.id)).count == summaries.count else { throw GroupLoadError.invalidData }
        var result: [LoadedCloudGroup] = []
        for summary in summaries {
            try check(uid)
            let members = try await reads.members(summary.pathID)
            try check(uid)
            let tasks = try await reads.tasks(summary.pathID)
            try check(uid)
            result.append(try Self.map(summary, members: members, tasks: tasks, currentUID: uid))
        }
        try check(uid)
        let taskIDs = result.flatMap(\.tasks).map(\.id)
        guard Set(taskIDs).count == taskIDs.count else { throw GroupLoadError.invalidData }
        return result
    }

    private func check(_ uid: String) throws {
        try Task.checkCancellation()
        guard reads.currentUID() == uid else { throw GroupLoadError.accountChanged }
    }

    static func map(_ summary: CloudGroupSummary,
                    members documents: [CloudDocument<CloudMemberDocument>],
                    tasks taskDocuments: [CloudDocument<CloudTaskDocument>],
                    currentUID: String) throws -> LoadedCloudGroup {
        guard UUID(uuidString: summary.pathID) == summary.id,
              !summary.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              documents.contains(where: { $0.id == currentUID && $0.value.userID == currentUID }) else {
            throw GroupLoadError.invalidData
        }
        guard Set(documents.map(\.id)).count == documents.count else { throw GroupLoadError.invalidData }
        let members = try documents.map { document in
            let data = document.value
            guard !data.userID.isEmpty, document.id == data.userID else { throw GroupLoadError.invalidData }
            return Member(id: FirebaseMemberIdentity.uiID(for: data.userID),
                          name: data.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? data.displayName! : L10n.format("成員 {0}", String(describing: data.userID.prefix(8))),
                          role: data.role, avatarSymbol: data.avatarSymbol ?? "person.fill", firebaseUID: data.userID)
        }
        let tasks = try mapTasks(
            groupID: summary.id,
            pathID: summary.pathID,
            documents: taskDocuments,
            members: members
        )
        let group = Group(id: summary.id, name: summary.name, deadline: summary.deadline,
                          memberIDs: members.map(\.id), taskIDs: tasks.map(\.id), inviteCode: summary.inviteCode,
                          firestoreDocumentID: summary.pathID,
                          memberRoles: Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.role) }))
        return LoadedCloudGroup(group: group, members: members, tasks: tasks)
    }

    static func mapTasks(
        groupID: UUID,
        pathID: String,
        documents taskDocuments: [CloudDocument<CloudTaskDocument>],
        members: [Member]
    ) throws -> [ProjectTask] {
        let byUID = Dictionary(uniqueKeysWithValues: members.compactMap { member in
            member.firebaseUID.map { ($0, member.id) }
        })
        func memberID(_ uid: String?) throws -> UUID? {
            guard let uid else { return nil }
            // A former member may still be referenced by historical tasks.
            return byUID[uid]
        }
        let tasks = try taskDocuments.map { document in
            let data = document.value
            guard let id = UUID(uuidString: document.id),
                  data.groupID == nil || data.groupID == pathID,
                  !data.title.isEmpty, (data.weight ?? 1) > 0 else { throw GroupLoadError.invalidData }
            let subtasks = data.subtasks ?? []
            guard Set(subtasks.map(\.id)).count == subtasks.count,
                  subtasks.allSatisfy({ $0.weight > 0 }) else { throw GroupLoadError.invalidData }
            return ProjectTask(id: id, groupID: groupID, title: data.title, detail: data.detail ?? "",
                               weight: data.weight ?? 1, ownerMemberID: try memberID(data.ownerMemberID),
                               subtasks: subtasks, deliverable: nil, deadline: data.deadline ?? .distantFuture,
                               createdByMemberID: try memberID(data.createdByMemberID),
                               createdAt: data.createdAt ?? .distantPast,
                               firestoreDocumentID: document.id, firestoreGroupID: pathID,
                               confirmedAttachmentID: data.confirmedAttachmentID,
                               confirmedMemberUIDs: data.confirmedMemberUIDs ?? [], cloudStatus: data.status)
        }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw GroupLoadError.invalidData }
        return tasks
    }
}
