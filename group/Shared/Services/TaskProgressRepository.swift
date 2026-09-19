import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class TaskProgressRepository {
    func update(groupID: String, taskID: String, action: String, subtaskID: String? = nil,
                isComplete: Bool? = nil, attachmentID: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw AttachmentOperationError.signedOut }
        if action == "setSubtask" {
            guard let subtaskID, let id = UUID(uuidString: subtaskID), let isComplete else {
                throw TaskMutationError.invalidData
            }
            try await TaskMutationRepository().setSubtaskCompletion(
                expectedUserID: uid, groupID: groupID, taskID: taskID,
                subtaskID: id, isComplete: isComplete
            )
            return
        }
        var data: [String: Any] = ["groupID": groupID, "taskID": taskID, "action": action]
        if let subtaskID { data["subtaskID"] = subtaskID }
        if let isComplete { data["isComplete"] = isComplete }
        if let attachmentID { data["attachmentID"] = attachmentID }
        do {
            _ = try await Functions.functions(region: "asia-east1").httpsCallable("confirmTaskAttachment").call(data)
        } catch {
            let ns = error as NSError
            switch FunctionsErrorCode(rawValue: ns.code) {
            case .permissionDenied: throw TaskProgressError.permission
            case .failedPrecondition: throw TaskProgressError.changed
            case .notFound, .unimplemented: throw TaskProgressError.unavailable
            case .unauthenticated: throw AttachmentOperationError.signedOut
            default: throw AttachmentOperationError.network
            }
        }
    }
}

enum TaskProgressError: LocalizedError {
    case permission, changed, unavailable
    var errorDescription: String? {
        switch self {
        case .permission: "目前帳號沒有更新此任務的權限。"
        case .changed: "請先完成所有子任務；若成果已更換，請重新整理後確認。"
        case .unavailable: "任務同步服務尚未就緒，請稍後再試。"
        }
    }
}

/// Keeps members and tasks in one consistent mapping; cached snapshots never cross account boundaries.
@MainActor
final class GroupProgressSubscription {
    private var registrations: [ListenerRegistration] = []
    private var members: [CloudDocument<CloudMemberDocument>]?
    private var tasks: [CloudDocument<CloudTaskDocument>]?

    init(summary: CloudGroupSummary, uid: String, receive: @escaping (Result<LoadedCloudGroup, Error>) -> Void) {
        let ref = Firestore.firestore().collection("groups").document(summary.pathID)
        func emit() {
            guard let members, let tasks else { return }
            receive(Result { try GroupRepository.map(summary, members: members, tasks: tasks, currentUID: uid) })
        }
        registrations.append(ref.collection("members").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.members = nil; receive(.failure(error)); return }
                guard let snap, !snap.metadata.isFromCache else { return }
                do { self.members = try snap.documents.map { CloudDocument(id: $0.documentID, value: try $0.data(as: CloudMemberDocument.self)) }; emit() }
                catch { receive(.failure(error)) }
            }
        })
        registrations.append(ref.collection("tasks").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.tasks = nil; receive(.failure(error)); return }
                guard let snap, !snap.metadata.isFromCache else { return }
                do { self.tasks = try snap.documents.map { CloudDocument(id: $0.documentID, value: try $0.data(as: CloudTaskDocument.self)) }; emit() }
                catch { receive(.failure(error)) }
            }
        })
    }
    func stop() { registrations.forEach { $0.remove() }; registrations = []; members = nil; tasks = nil }
}
