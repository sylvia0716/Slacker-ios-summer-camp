import Foundation

/// 一位群組成員送給另一位成員的匿名互評。
struct PeerReview: Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let reviewerMemberID: UUID
    let revieweeMemberID: UUID
    let taskCompletionScore: Int
    let discussionScore: Int
    let collaborationScore: Int
    let ideaScore: Int
    let reliabilityScore: Int
    let comment: String
    let submittedAt: Date
}

enum PeerReviewSubmissionError: LocalizedError {
    case groupNotFound
    case groupStillActive
    case memberNotInGroup
    case cannotReviewSelf
    case invalidScore
    case duplicateReview

    var errorDescription: String? {
        switch self {
        case .groupNotFound: "找不到目前群組"
        case .groupStillActive: "群組截止後才能送出互評"
        case .memberNotInGroup: "互評雙方都必須是目前群組成員"
        case .cannotReviewSelf: "不可評價自己"
        case .invalidScore: "五個評分項目都必須填寫 1～5 分"
        case .duplicateReview: "你已送出對這位成員的評價"
        }
    }
}
