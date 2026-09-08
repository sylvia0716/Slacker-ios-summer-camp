import Foundation

/// No uploader/leader comparison here. Each backend write is authorized by its Rules.
@MainActor
final class AttachmentDeletionService {
    struct Client {
        var currentUID: () -> String?
        var deleteObject: (String) async throws -> Void
        var deleteMetadata: (TaskAttachment) async throws -> Void
    }
    private let client: Client
    init(client: Client) { self.client = client }

    func delete(_ attachment: TaskAttachment) async throws {
        guard let uid = client.currentUID() else { throw AttachmentOperationError.signedOut }
        var objectRemoved = false
        if attachment.kind != .externalLink {
            let path = try AttachmentFilePolicy.path(for: attachment)
            do { try await client.deleteObject(path) }
            catch AttachmentOperationError.notFound { /* Idempotent retry after partial success. */ }
            objectRemoved = true
        } else if attachment.storagePath != nil {
            throw AttachmentOperationError.invalidFile
        }
        do {
            guard client.currentUID() == uid else { throw AttachmentOperationError.accountChanged }
            try Task.checkCancellation()
            try await client.deleteMetadata(attachment)
        } catch {
            if objectRemoved {
                let reason = (error as? AttachmentOperationError)?.localizedDescription ?? AttachmentOperationError.network.localizedDescription
                throw AttachmentOperationError.metadataPending(reason)
            }
            throw error
        }
    }
}
