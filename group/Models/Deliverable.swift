import Foundation

/// 任務負責人送出的成果資料；MVP 先使用檔名或連結，不串接真實雲端上傳。
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
    /// 已確認成果進度的群組成員；每位成員最多出現一次。
    var confirmedMemberIDs: [UUID] = []
    /// 送出成果的時間。
    var submittedAt: Date
    /// 是否已由任務負責人或組長驗收。
    var isApproved: Bool
}
