import FirebaseAuth
import FirebaseFirestore
import Foundation

/// 集中處理附件 metadata 的 Firestore 讀寫；SwiftUI View 不直接存取 Firestore。
final class AttachmentRepository {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    /// 上傳前確認 Firebase Auth 使用者確實存在於群組 members 子集合。
    func requireCurrentUserMembership(groupID: String, userID: String) async throws {
        try validateCurrentUser(as: userID)

        do {
            let snapshot = try await firestore.collection("groups")
                .document(groupID)
                .collection("members")
                .document(userID)
                .getDocument()
            guard snapshot.exists else {
                throw AttachmentRepositoryError.notGroupMember
            }
        } catch let error as AttachmentRepositoryError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw AttachmentRepositoryError.notGroupMember
            }
            throw AttachmentRepositoryError.membershipCheckFailed
        }
    }

    /// 建立附件 metadata。`createdAt` 一律由 Firestore 伺服器填入，忽略呼叫端時間。
    func create(_ attachment: TaskAttachment) async throws {
        try validateCurrentUser(as: attachment.uploaderID)

        try await attachmentReference(
            groupID: attachment.groupID,
            taskID: attachment.taskID,
            attachmentID: attachment.id
        ).setData([
            "id": attachment.id,
            "taskID": attachment.taskID,
            "groupID": attachment.groupID,
            "uploaderID": attachment.uploaderID,
            "title": attachment.title,
            "detail": attachment.detail,
            "kind": attachment.kind.rawValue,
            "originalFilename": attachment.originalFilename.map { $0 as Any } ?? NSNull(),
            "storagePath": attachment.storagePath.map { $0 as Any } ?? NSNull(),
            "externalURL": attachment.externalURL.map { $0 as Any } ?? NSNull(),
            "contentType": attachment.contentType.map { $0 as Any } ?? NSNull(),
            "byteSize": attachment.byteSize.map { $0 as Any } ?? NSNull(),
            "status": attachment.status.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func fetch(groupID: String, taskID: String) async throws -> [TaskAttachment] {
        let snapshot = try await attachmentsCollection(groupID: groupID, taskID: taskID)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return try snapshot.documents.map { try $0.data(as: TaskAttachment.self) }
    }

    /// 即時監聽同一任務的附件；畫面只需訂閱 Repository 回傳的結果。
    @discardableResult
    func listen(
        groupID: String,
        taskID: String,
        onChange: @escaping (Result<[TaskAttachment], Error>) -> Void
    ) -> ListenerRegistration {
        attachmentsCollection(groupID: groupID, taskID: taskID)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }

                do {
                    let attachments = try (snapshot?.documents ?? []).map {
                        try $0.data(as: TaskAttachment.self)
                    }
                    onChange(.success(attachments))
                } catch {
                    onChange(.failure(error))
                }
            }
    }

    func updateStatus(
        _ status: AttachmentStatus,
        groupID: String,
        taskID: String,
        attachmentID: String,
        uploaderID: String
    ) async throws {
        try validateCurrentUser(as: uploaderID)
        try await attachmentReference(
            groupID: groupID,
            taskID: taskID,
            attachmentID: attachmentID
        ).updateData(["status": status.rawValue])
    }

    func delete(
        groupID: String,
        taskID: String,
        attachmentID: String,
        uploaderID: String
    ) async throws {
        try validateCurrentUser(as: uploaderID)
        try await attachmentReference(
            groupID: groupID,
            taskID: taskID,
            attachmentID: attachmentID
        ).delete()
    }

    private func attachmentsCollection(groupID: String, taskID: String) -> CollectionReference {
        firestore.collection("groups")
            .document(groupID)
            .collection("tasks")
            .document(taskID)
            .collection("attachments")
    }

    private func attachmentReference(
        groupID: String,
        taskID: String,
        attachmentID: String
    ) -> DocumentReference {
        attachmentsCollection(groupID: groupID, taskID: taskID).document(attachmentID)
    }

    private func validateCurrentUser(as uploaderID: String) throws {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            throw AttachmentRepositoryError.notAuthenticated
        }
        guard currentUserID == uploaderID else {
            throw AttachmentRepositoryError.uploaderMismatch
        }
    }
}

enum AttachmentRepositoryError: LocalizedError {
    case notAuthenticated
    case uploaderMismatch
    case notGroupMember
    case membershipCheckFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "請先登入再操作成果附件。"
        case .uploaderMismatch:
            "目前帳號與附件上傳者不一致。"
        case .notGroupMember:
            "你不是這個群組的成員，無法上傳成果。"
        case .membershipCheckFailed:
            "目前無法確認群組資格，請檢查網路後再試一次。"
        }
    }
}
