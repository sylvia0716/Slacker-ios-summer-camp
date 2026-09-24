import Foundation
import CryptoKit

struct CloudGroupSummary: Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let deadline: Date
    var settledAt: Date? = nil
    let inviteCode: String
    var documentID: String? = nil
    var pathID: String { documentID ?? id.uuidString.lowercased() }
}

/// Stable, display-only mapping. Never pass this UUID to Firebase Auth or membership paths.
enum FirebaseMemberIdentity {
    static func uiID(for uid: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("group-bomb/member/" + uid).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct CloudMemberDocument: Codable {
    let userID: String
    let role: MemberRole
    let joinedAt: Date
    var displayName: String? = nil
    var avatarSymbol: String? = nil
    var leaderElectionID: String? = nil
    var leaderVoteUID: String? = nil
}

struct CloudTaskDocument: Codable {
    let title: String
    var groupID: String? = nil
    var detail: String? = nil
    var weight: Int? = nil
    /// This field stores Firebase UID, not the old UI/mock UUID.
    var ownerMemberID: String? = nil
    var createdByMemberID: String? = nil
    var subtasks: [Subtask]? = nil
    var deadline: Date? = nil
    var createdAt: Date? = nil
    var status: ProjectTaskStatus? = nil
    var departureID: String? = nil
    var departedMemberName: String? = nil
    var departedProgress: Int? = nil
    var includedInProgress: Bool? = nil
    var departureReviewed: Bool? = nil
    var confirmedAttachmentID: String? = nil
    var confirmedMemberUIDs: [String]? = nil
}

struct CloudDocument<Value> {
    let id: String
    let value: Value
}

struct LoadedCloudGroup {
    let group: Group
    let members: [Member]
    let tasks: [ProjectTask]
}

enum GroupLoadError: LocalizedError {
    case signedOut, accountChanged, invalidData, permissionDenied, network
    var errorDescription: String? {
        switch self {
        case .signedOut: L10n.text("請先登入再載入群組。")
        case .accountChanged: L10n.text("帳號已變更，請重新載入。")
        case .invalidData: L10n.text("群組或任務資料格式不正確，請聯絡群組建立者。")
        case .permissionDenied: L10n.text("目前帳號沒有讀取群組資料的權限。")
        case .network: L10n.text("群組資料載入失敗，請確認網路後重試。")
        }
    }
}
