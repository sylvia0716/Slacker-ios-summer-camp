import Foundation

/// 任務負責人送出的成果資料；畫面以這個型別共用本機與 Firebase 附件狀態。
struct Deliverable: Identifiable, Hashable {
    /// 成果唯一識別碼。
    let id: UUID
    /// 顯示給組員與驗收者的成果名稱或檔名。
    var title: String
    /// 成果內容的補充說明。
    var detail: String = ""
    /// 成果連結；尚未串雲端時可為 nil。
    var url: URL?
    /// MVP 儲存在 App Cache 目錄中的成果照片檔名。
    var localImageFilename: String? = nil
    /// Firestore attachments 文件 ID；舊的本機成果可為 nil。
    var attachmentID: String? = nil
    /// Firebase Storage 內的物件路徑；網址成果可為 nil。
    var storagePath: String? = nil
    /// 使用者選取檔案時的原始檔名，只供顯示，不作為 Storage 路徑。
    var originalFilename: String? = nil
    /// 附件 MIME type，供預覽與下載時判斷檔案類型。
    var contentType: String? = nil
    /// 已確認成果進度的群組成員；每位成員最多出現一次。
    var confirmedMemberIDs: [UUID] = []
    /// 送出成果的時間。
    var submittedAt: Date
    /// 是否已由任務負責人或組長驗收。
    var isApproved: Bool
}

extension Deliverable {
    init(attachment: TaskAttachment, localImageFilename: String? = nil) {
        self.init(
            id: UUID(uuidString: attachment.id) ?? UUID(),
            title: attachment.title,
            detail: attachment.detail,
            url: attachment.externalURL.flatMap(URL.init(string:)),
            localImageFilename: localImageFilename,
            attachmentID: attachment.id,
            storagePath: attachment.storagePath,
            originalFilename: attachment.originalFilename,
            contentType: attachment.contentType,
            submittedAt: attachment.createdAt ?? .now,
            isApproved: false
        )
    }
}
