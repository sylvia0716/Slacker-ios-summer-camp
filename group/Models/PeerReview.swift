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

struct PeerReviewSummary: Equatable {
    var participantCount = 0
    var totalReviewCount = 0
    var completedReviewerCount = 0
    var taskCompletionScoreTotal = 0
    var discussionScoreTotal = 0
    var collaborationScoreTotal = 0
    var ideaScoreTotal = 0
    var reliabilityScoreTotal = 0

    func average(total: Int) -> Double {
        guard totalReviewCount > 0 else { return 0 }
        return Double(total) / Double(totalReviewCount)
    }
}

/// A private, per-project snapshot of the scores received by the signed-in user.
struct PersonalPeerReviewProject: Identifiable, Equatable {
    let groupID: String
    let groupName: String
    let completedAt: Date
    let reviewCount: Int
    let acceptedReviewCount: Int
    let excludedReviewCount: Int
    let taskCompletionScoreTotal: Int
    let discussionScoreTotal: Int
    let collaborationScoreTotal: Int
    let ideaScoreTotal: Int
    let reliabilityScoreTotal: Int
    let taskCompletionScore: Double
    let discussionScore: Double
    let collaborationScore: Double
    let ideaScore: Double
    let reliabilityScore: Double

    var id: String { groupID }

    func average(total: Int) -> Double {
        guard reviewCount > 0 else { return 0 }
        return Double(total) / Double(reviewCount)
    }

    var overallAverage: Double {
        (taskCompletionScore + discussionScore + collaborationScore + ideaScore + reliabilityScore) / 5
    }
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
        case .groupNotFound: L10n.text("找不到目前群組")
        case .groupStillActive: L10n.text("群組截止後才能送出互評")
        case .memberNotInGroup: L10n.text("互評雙方都必須是目前群組成員")
        case .cannotReviewSelf: L10n.text("不可評價自己")
        case .invalidScore: L10n.text("五個評分項目都必須填寫 1～5 分")
        case .duplicateReview: L10n.text("你已送出對這位成員的評價")
        }
    }
}
