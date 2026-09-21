import Foundation

/// 成員在群組中的權限；組長可驗收成果，成員可更新自己負責的任務。
enum MemberRole: String, Codable, Hashable {
    case leader
    case member

    /// 顯示於成員卡片的繁體中文角色名稱。
    var title: String {
        switch self {
        case .leader: L10n.text("組長")
        case .member: L10n.text("組員")
        }
    }
}

/// 一位加入群組的使用者；個人進度由其負責任務的子任務自動計算。
struct Member: Identifiable, Hashable {
    /// 成員唯一識別碼，任務用它指定負責人。
    let id: UUID
    /// 顯示在成員卡片和聊天室的名稱。
    var name: String
    /// 成員在群組中的權限。
    var role: MemberRole
    /// 頭像的 SF Symbol 名稱；MVP 不需要真實圖片上傳。
    var avatarSymbol: String
    /// Firebase 身分；UI UUID 不能作為後端授權 UID。
    var firebaseUID: String? = nil
}
