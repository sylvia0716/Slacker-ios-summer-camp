import Foundation

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

    /// 依子任務權重算出的任務完成百分比，不應直接手動設定。
    var progress: Int {
        let totalWeight = subtasks.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let completedWeight = subtasks.filter(\.isComplete).reduce(0) { $0 + $1.weight }
        return completedWeight * 100 / totalWeight
    }

    /// 任務是否已完成所有子任務並送出成果。
    var isCompleted: Bool {
        progress == 100 && deliverable != nil
    }
}
