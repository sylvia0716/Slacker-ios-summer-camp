import Foundation

enum AttachmentOperationError: LocalizedError, Equatable {
    case signedOut, accountChanged, permissionDenied, notFound, invalidFile, network, localFile
    case metadataPending(String)
    var errorDescription: String? {
        switch self {
        case .signedOut: "請先登入再操作附件。"
        case .accountChanged: "帳號已變更，請重新操作。"
        case .permissionDenied: "目前帳號沒有操作此附件的權限。"
        case .notFound: "雲端檔案已不存在。"
        case .invalidFile: "附件格式或路徑不正確，或檔案超過 20 MB。"
        case .network: "連線失敗，請確認網路後重試。"
        case .localFile: "無法儲存本機預覽檔案，請確認可用空間後重試。"
        case .metadataPending(let reason): "雲端檔案已刪除，但附件資料尚未刪除。\(reason) 請重試完成清理。"
        }
    }
}

enum AttachmentFilePolicy {
    static let maximumSize: Int64 = 20 * 1024 * 1024
    static func path(for attachment: TaskAttachment) throws -> String {
        let ids = [attachment.groupID, attachment.taskID, attachment.id]
        guard ids.allSatisfy({ UUID(uuidString: $0) != nil }),
              let path = attachment.storagePath else { throw AttachmentOperationError.invalidFile }
        let prefix = "groups/\(attachment.groupID)/tasks/\(attachment.taskID)/attachments/\(attachment.id)/"
        guard path.hasPrefix(prefix) else { throw AttachmentOperationError.invalidFile }
        let name = String(path.dropFirst(prefix.count))
        guard name.range(of: "^[a-z0-9][a-z0-9-]{0,47}-[a-f0-9]{8}\\.(jpg|jpeg|png|pdf|docx|xlsx|pptx|zip)$", options: .regularExpression) != nil else {
            throw AttachmentOperationError.invalidFile
        }
        return path
    }

    static func fileExtension(for attachment: TaskAttachment) throws -> String {
        let path = try path(for: attachment)
        let ext = (path as NSString).pathExtension
        let allowed: [String: [String]] = [
            "jpg": ["image/jpeg"], "jpeg": ["image/jpeg"], "png": ["image/png"],
            "pdf": ["application/pdf"],
            "docx": ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"],
            "xlsx": ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"],
            "pptx": ["application/vnd.openxmlformats-officedocument.presentationml.presentation"],
            "zip": ["application/zip", "application/x-zip-compressed"]
        ]
        guard let contentType = attachment.contentType,
              allowed[ext]?.contains(contentType) == true,
              let size = attachment.byteSize, size > 0, size <= maximumSize else { throw AttachmentOperationError.invalidFile }
        return ext
    }
}
