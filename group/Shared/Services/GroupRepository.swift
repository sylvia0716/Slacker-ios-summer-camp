import Foundation
import OSLog

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
    private let wait: (Duration) async throws -> Void
    private static let logger = Logger(subsystem: "con.sylvia.group", category: "CloudGroups")

    init(reads: Reads, wait: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.reads = reads
        self.wait = wait
    }

    func load() async throws -> [LoadedCloudGroup] {
        guard let uid = reads.currentUID() else { throw GroupLoadError.signedOut }
        var retry = 0
        while true {
            try check(uid)
            do {
                let result = try await loadSnapshot(uid: uid)
                if retry > 0 { Self.logger.info("Group load recovered after \(retry) retries") }
                return result
            } catch {
                // Cancellation/account changes always win, including errors from an old request.
                try check(uid)
                guard CloudReadRetry.isTransient(error), retry < CloudReadRetry.delays.count else { throw error }
                let delay = CloudReadRetry.delays[retry]
                retry += 1
                let code = error as NSError
                Self.logger.notice("Retrying group load \(retry): \(code.domain, privacy: .public)/\(code.code)")
                try await wait(delay)
            }
        }
    }

    private func loadSnapshot(uid: String) async throws -> [LoadedCloudGroup] {
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
                          leaderElectionID: documents.compactMap { $0.value.leaderElectionID }.first,
                          leaderVotes: Dictionary(uniqueKeysWithValues: documents.compactMap { document in
                              guard let vote = document.value.leaderVoteUID,
                                    documents.contains(where: { $0.id == vote }) else { return nil }
                              return (FirebaseMemberIdentity.uiID(for: document.id), FirebaseMemberIdentity.uiID(for: vote))
                          }),
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
                               departureID: data.departureID, departedMemberName: data.departedMemberName,
                               departedProgress: data.departedProgress,
                               includedInProgress: data.includedInProgress ?? true,
                               departureReviewed: data.departureReviewed ?? false,
                               confirmedAttachmentID: data.confirmedAttachmentID,
                               confirmedMemberUIDs: data.confirmedMemberUIDs ?? [], cloudStatus: data.status)
        }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw GroupLoadError.invalidData }
        return tasks
    }
}
