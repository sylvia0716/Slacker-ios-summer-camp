import FirebaseAuth
import FirebaseStorage
import Foundation

/// 負責 Storage 與 Firestore 的兩階段成果送出，避免 SwiftUI View 直接操作 Firebase。
final class AttachmentUploadService {
    nonisolated static let maximumFileSize = 20 * 1_024 * 1_024

    private let repository: AttachmentRepository
    private let storage: Storage

    init(
        repository: AttachmentRepository = AttachmentRepository(),
        storage: Storage = Storage.storage()
    ) {
        self.repository = repository
        self.storage = storage
    }

    func upload(
        _ prepared: PreparedAttachment,
        groupID: String,
        taskID: String,
        title: String,
        detail: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> TaskAttachment {
        let userID = try currentUserID()
        try await repository.requireCurrentUserMembership(groupID: groupID, userID: userID)
        guard prepared.data.count <= Self.maximumFileSize else {
            throw AttachmentUploadError.fileTooLarge
        }

        let attachmentID = UUID().uuidString.lowercased()
        let safeFilename = Self.safeFilename(
            originalFilename: prepared.originalFilename,
            attachmentID: attachmentID,
            kind: prepared.kind
        )
        let storagePath = "groups/\(groupID)/tasks/\(taskID)/attachments/\(attachmentID)/\(safeFilename)"
        let reference = storage.reference(withPath: storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = prepared.contentType
        metadata.customMetadata = ["uploaderID": userID]

        do {
            _ = try await reference.putDataAsync(prepared.data, metadata: metadata) { value in
                let fraction = value.map { Double($0.completedUnitCount) / Double(max($0.totalUnitCount, 1)) } ?? 0
                Task { @MainActor in progress(min(max(fraction, 0), 1)) }
            }
        } catch {
            throw AttachmentUploadError.storageUploadFailed
        }

        let attachment = TaskAttachment(
            id: attachmentID,
            taskID: taskID,
            groupID: groupID,
            uploaderID: userID,
            title: title,
            detail: detail,
            kind: prepared.kind,
            originalFilename: prepared.originalFilename,
            storagePath: storagePath,
            contentType: prepared.contentType,
            byteSize: Int64(prepared.data.count),
            status: .ready
        )

        do {
            try await repository.create(attachment)
            progress(1)
            return attachment
        } catch {
            do {
                try await reference.delete()
            } catch {
                throw AttachmentUploadError.orphanCleanupFailed
            }
            throw AttachmentUploadError.metadataSaveFailed
        }
    }

    func submitURL(
        _ urlString: String,
        groupID: String,
        taskID: String,
        title: String,
        detail: String
    ) async throws -> TaskAttachment {
        let userID = try currentUserID()
        try await repository.requireCurrentUserMembership(groupID: groupID, userID: userID)
        guard let components = URLComponents(string: urlString),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false else {
            throw AttachmentUploadError.invalidHTTPSURL
        }

        let attachment = TaskAttachment(
            taskID: taskID,
            groupID: groupID,
            uploaderID: userID,
            title: title,
            detail: detail,
            kind: .externalLink,
            externalURL: urlString,
            status: .ready
        )
        do {
            try await repository.create(attachment)
            return attachment
        } catch let error as AttachmentRepositoryError {
            throw error
        } catch {
            throw AttachmentUploadError.metadataSaveFailed
        }
    }

    private func currentUserID() throws -> String {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw AttachmentUploadError.notAuthenticated
        }
        return userID
    }

    nonisolated static func safeFilename(
        originalFilename: String,
        attachmentID: String,
        kind: AttachmentKind
    ) -> String {
        let suppliedExtension = URL(fileURLWithPath: originalFilename).pathExtension.lowercased()
        let allowedExtensions = ["jpg", "jpeg", "png", "heic", "pdf", "pptx", "docx", "xlsx", "zip"]
        let fileExtension = allowedExtensions.contains(suppliedExtension)
            ? suppliedExtension
            : defaultExtension(for: kind)
        let rawBase = URL(fileURLWithPath: originalFilename).deletingPathExtension().lastPathComponent
        let folded = rawBase.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let allowedCharacters = "abcdefghijklmnopqrstuvwxyz0123456789"
        let safeBase = folded.lowercased().map { character in
            allowedCharacters.contains(character) ? character : "-"
        }
        let normalized = String(safeBase)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let base = String((normalized.isEmpty ? "attachment" : normalized).prefix(48))
        return "\(base)-\(attachmentID.prefix(8)).\(fileExtension)"
    }

    nonisolated private static func defaultExtension(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: "jpg"
        case .pdf: "pdf"
        case .presentation: "pptx"
        case .document: "docx"
        case .spreadsheet: "xlsx"
        case .archive: "zip"
        case .externalLink, .other: "bin"
        }
    }
}

enum AttachmentUploadError: LocalizedError {
    case notAuthenticated
    case fileTooLarge
    case invalidHTTPSURL
    case unsupportedFileType
    case storageUploadFailed
    case metadataSaveFailed
    case orphanCleanupFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "請先登入再上傳成果。"
        case .fileTooLarge:
            "檔案不可超過 20 MB。"
        case .invalidHTTPSURL:
            "請輸入以 https:// 開頭的有效網址。"
        case .unsupportedFileType:
            "僅支援 PNG、JPG、PDF、PPTX、DOCX、XLSX 和 ZIP。"
        case .storageUploadFailed:
            "檔案上傳失敗，請檢查網路後重新嘗試。"
        case .metadataSaveFailed:
            "成果資料儲存失敗，已清除未完成的雲端檔案。"
        case .orphanCleanupFailed:
            "成果資料儲存失敗，且雲端檔案無法自動清除，請稍後再試。"
        }
    }
}
