import Foundation

/// 聊天室機器人產生的溝通分析結果；設定頁直接讀取這份資料，不在畫面內另外計分。
struct CommunicationAnalysis: Identifiable, Codable {
    /// 分析結果的唯一識別碼，供聊天訊息與報告列表使用。
    let id: UUID
    /// 此份分析屬於哪個群組。
    let groupID: UUID
    /// 0 到 100 的溝通分數。
    let score: Int
    /// 機器人給團隊的整體判斷。
    let summary: String
    /// 對話中做得好的地方。
    let strength: String
    /// 下一步可改善的溝通行動。
    let suggestion: String
    /// 最近一次分析的時間。
    let updatedAt: Date
}
