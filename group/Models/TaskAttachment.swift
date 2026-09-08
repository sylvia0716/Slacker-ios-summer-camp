import Foundation

/// Firestore 中的任務成果附件；文件 ID 也會寫入 `id` 欄位，方便跨頁面共用。
struct TaskAttachment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let taskID: String
    let groupID: String
    let uploaderID: String
    var title: String
    var detail: String
    var kind: AttachmentKind
    var originalFilename: String?
    var storagePath: String?
    var externalURL: String?
    var contentType: String?
    var byteSize: Int64?
    var status: AttachmentStatus
    var createdAt: Date?

    init(
        id: String = UUID().uuidString,
        taskID: String,
        groupID: String,
        uploaderID: String,
        title: String,
        detail: String = "",
        kind: AttachmentKind,
        originalFilename: String? = nil,
        storagePath: String? = nil,
        externalURL: String? = nil,
        contentType: String? = nil,
        byteSize: Int64? = nil,
        status: AttachmentStatus = .pending,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.groupID = groupID
        self.uploaderID = uploaderID
        self.title = title
        self.detail = detail
        self.kind = kind
        self.originalFilename = originalFilename
        self.storagePath = storagePath
        self.externalURL = externalURL
        self.contentType = contentType
        self.byteSize = byteSize
        self.status = status
        self.createdAt = createdAt
    }
}

enum AttachmentKind: String, Codable, Hashable, Sendable {
    case image
    case pdf
    case presentation
    case document
    case spreadsheet
    case archive
    case externalLink
    case other
}

enum AttachmentStatus: String, Codable, Hashable, Sendable {
    case pending
    case uploading
    case ready
    case failed
}
