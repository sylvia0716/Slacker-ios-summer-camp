import Foundation

/// 任務負責人送出的成果資料；MVP 先使用檔名或連結，不串接真實雲端上傳。
struct Deliverable: Identifiable, Hashable {
    /// 成果唯一識別碼。
    let id: UUID
    /// 顯示給組員與驗收者的成果名稱或檔名。
    var title: String
    /// 成果連結；尚未串雲端時可為 nil。
    var url: URL?
    /// 送出成果的時間。
    var submittedAt: Date
    /// 是否已由任務負責人或組長驗收。
    var isApproved: Bool
}
