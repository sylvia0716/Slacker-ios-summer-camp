import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

private func attachmentError(_ error: Error) -> AttachmentOperationError {
    if let mapped = error as? AttachmentOperationError { return mapped }
    let value = error as NSError
    if value.domain == StorageErrorDomain {
        switch StorageErrorCode(rawValue: value.code) {
        case .unauthenticated: return .signedOut
        case .unauthorized: return .permissionDenied
        case .objectNotFound: return .notFound
        default: return .network
        }
    }
    if value.domain == FirestoreErrorDomain {
        switch FirestoreErrorCode.Code(rawValue: value.code) {
        case .unauthenticated: return .signedOut
        case .permissionDenied: return .permissionDenied
        default: return .network
        }
    }
    return .network
}

extension AttachmentDownloadService {
    static func firebase() -> AttachmentDownloadService {
        let storage = Storage.storage()
        return AttachmentDownloadService(client: Client(currentUID: { Auth.auth().currentUser?.uid }, write: { attachment, file, progress in
            do {
                guard let uid = Auth.auth().currentUser?.uid else { throw AttachmentOperationError.signedOut }
                let reference = storage.reference(withPath: try AttachmentFilePolicy.path(for: attachment))
                let metadata = try await reference.getMetadata()
                guard metadata.size > 0, metadata.size <= AttachmentFilePolicy.maximumSize,
                      metadata.size == attachment.byteSize, metadata.contentType == attachment.contentType else {
                    throw AttachmentOperationError.invalidFile
                }
                guard Auth.auth().currentUser?.uid == uid else { throw AttachmentOperationError.accountChanged }
                // Authenticated SDK transfer, not a public token URL.
                _ = try await reference.writeAsync(toFile: file) { value in
                    let fraction = value?.fractionCompleted ?? 0
                    Task { @MainActor in progress(min(max(fraction, 0), 1)) }
                }
            } catch { throw attachmentError(error) }
        }))
    }
}

extension AttachmentDeletionService {
    static func firebase() -> AttachmentDeletionService {
        let storage = Storage.storage()
        let repository = AttachmentRepository()
        return AttachmentDeletionService(client: Client(currentUID: { Auth.auth().currentUser?.uid }, deleteObject: { path in
            do { try await storage.reference(withPath: path).delete() }
            catch { throw attachmentError(error) }
        }, deleteMetadata: { attachment in
            do {
                try await repository.delete(groupID: attachment.groupID, taskID: attachment.taskID, attachmentID: attachment.id)
            } catch { throw attachmentError(error) }
        }))
    }
}
