import Foundation

/// An application is separate from membership until the group leader approves it.
struct GroupJoinRequest: Identifiable, Equatable {
    enum Status: String, Codable {
        case pending, approved, rejected

        var title: String {
            switch self {
            case .pending: L10n.text("待審核")
            case .approved: L10n.text("已核准")
            case .rejected: L10n.text("未通過審核")
            }
        }
    }

    let requestID: String
    let groupID: String
    let groupName: String
    let applicantID: String
    let applicantName: String
    let requestedAt: Date
    var status: Status

    var id: String { "\(groupID)/\(applicantID)" }
}
