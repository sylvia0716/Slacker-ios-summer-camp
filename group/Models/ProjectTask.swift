import Foundation

/// 正式任務的生命週期狀態。
enum ProjectTaskStatus: String, Codable, Hashable, CaseIterable {
    case pending
    case inProgress
    case submitted
    case completed

    var title: String {
        switch self {
        case .pending: "待開始"
        case .inProgress: "已開始"
        case .submitted: "待驗收"
        case .completed: "已完成"
        }
    }
}

/// 群組中的一項主要工作，例如文獻回顧、競品分析或簡報統整。
struct ProjectTask: Identifiable, Hashable {
    /// 任務唯一識別碼。
    let id: UUID
    /// 任務所屬群組，讓「我的任務」能連回正確群組。
    let groupID: UUID
    /// 顯示給使用者的任務名稱。
    var title: String
    /// 簡短說明此任務的交付內容。
    var detail: String
    /// 任務在群組總進度中的比重。
    var weight: Int
    /// 負責成員 ID；尚未認領時為 nil。
    var ownerMemberID: UUID?
    /// 可勾選完成的工作清單，是所有進度計算的唯一來源。
    var subtasks: [Subtask]
    /// 任務完成時送出的成果；nil 代表尚未交付。
    var deliverable: Deliverable?
    /// 任務截止時間；舊資料未指定時不限制截止時間。
    var deadline: Date = .distantFuture
    /// 建立任務的成員；舊資料未指定時為 nil。
    var createdByMemberID: UUID? = nil
    /// 任務建立時間。
    var createdAt: Date = .now
    var firestoreDocumentID: String? = nil
    var firestoreGroupID: String? = nil
    var confirmedAttachmentID: String? = nil
    var confirmedMemberUIDs: [String] = []
    var cloudStatus: ProjectTaskStatus? = nil

    /// 依子任務權重算出的任務完成百分比，不應直接手動設定。
    var progress: Int {
        let totalWeight = subtasks.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return cloudStatus == .completed && deliverable != nil ? 100 : 0 }
        let completedWeight = subtasks.filter(\.isComplete).reduce(0) { $0 + $1.weight }
        return completedWeight * 100 / totalWeight
    }

    /// 子任務全部完成時，主任務即完成；成果交付不影響完成狀態。
    var isCompleted: Bool {
        progress == 100
    }

    /// 任務狀態以子任務進度為唯一來源，避免儲存值與畫面狀態不同步。
    var status: ProjectTaskStatus {
        isCompleted ? .completed : .inProgress
    }
}
