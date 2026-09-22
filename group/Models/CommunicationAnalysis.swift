import Foundation

/// Apple Intelligence 產生的專案協作分析；聊天室與團隊戰報共用同一份結果。
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
    /// AI 根據任務與討論證據產生的五項專案指標；舊版溝通分析可能沒有這些欄位。
    let taskCompletionScore: Int?
    let discussionScore: Int?
    let collaborationScore: Int?
    let problemSolvingScore: Int?
    let reliabilityScore: Int?

    init(
        id: UUID,
        groupID: UUID,
        score: Int,
        summary: String,
        strength: String,
        suggestion: String,
        updatedAt: Date,
        taskCompletionScore: Int? = nil,
        discussionScore: Int? = nil,
        collaborationScore: Int? = nil,
        problemSolvingScore: Int? = nil,
        reliabilityScore: Int? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.score = score
        self.summary = summary
        self.strength = strength
        self.suggestion = suggestion
        self.updatedAt = updatedAt
        self.taskCompletionScore = taskCompletionScore
        self.discussionScore = discussionScore
        self.collaborationScore = collaborationScore
        self.problemSolvingScore = problemSolvingScore
        self.reliabilityScore = reliabilityScore
    }
}

enum ProjectAIAnalysisError: LocalizedError {
    case groupNotFound
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .groupNotFound: L10n.text("找不到這個專案的分析資料。")
        case .syncFailed: L10n.text("AI 專案分析已產生，但無法同步給其他成員，請確認網路後重試。")
        }
    }
}
