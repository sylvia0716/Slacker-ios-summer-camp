import Foundation

/// 一個分組報告小隊；群組名稱、死線、成員與任務關係都集中在這裡。
struct Group: Identifiable, Hashable {
    /// 群組唯一識別碼，供任務、畫面導航與資料查詢使用。
    let id: UUID
    /// 顯示在群組列表與詳細頁上的名稱。
    var name: String
    /// 報告最終交件時間，用來計算倒數。
    var deadline: Date
    /// 目前加入此群組的成員 ID。
    var memberIDs: [UUID]
    /// 屬於此群組的任務 ID。
    var taskIDs: [UUID]
    /// 讓其他人輸入並加入此群組的 MVP 邀請碼。
    var inviteCode: String
    var firestoreDocumentID: String? = nil
    /// 同一位使用者在不同群組可以有不同角色。
    var memberRoles: [UUID: MemberRole] = [:]
}
