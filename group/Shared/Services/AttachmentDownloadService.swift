import Foundation

@MainActor
final class AttachmentDownloadService {
    struct Client {
        var currentUID: () -> String?
        var write: (TaskAttachment, URL, @escaping @MainActor (Double) -> Void) async throws -> Void
    }
    private let client: Client
    init(client: Client) { self.client = client }

    func download(_ attachment: TaskAttachment, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        guard let uid = client.currentUID() else { throw AttachmentOperationError.signedOut }
        let ext = try AttachmentFilePolicy.fileExtension(for: attachment)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("group-bomb-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("attachment." + ext)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { throw AttachmentOperationError.localFile }
        do {
            try Task.checkCancellation()
            try await client.write(attachment, file, progress)
            guard client.currentUID() == uid else { throw AttachmentOperationError.accountChanged }
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0,
                  Int64(size) == attachment.byteSize, Int64(size) <= AttachmentFilePolicy.maximumSize else {
                throw AttachmentOperationError.invalidFile
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            progress(1)
            return file
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func removeLocalFile(_ url: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("group-bomb-attachments").standardizedFileURL.path + "/"
        guard url.isFileURL, url.standardizedFileURL.path.hasPrefix(root) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
