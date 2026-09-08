import Foundation

/// 任務中最小的可完成單位；完成狀態會自動推進個人與群組進度。
struct Subtask: Identifiable, Hashable, Codable {
    /// 子任務唯一識別碼。
    let id: UUID
    /// 顯示給負責人勾選的子任務名稱。
    var title: String
    /// 是否已完成；只有任務負責人應該能修改。
    var isComplete: Bool
    /// 此子任務占母任務進度的比重，建議所有子任務加總為 100。
    var weight: Int
}
