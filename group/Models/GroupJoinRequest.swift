import Foundation

enum GroupJoinRequestStatus: Hashable {
    case pending
    case approved
    case rejected
}

struct ApplicantProjectRecord: Identifiable, Hashable {
    let id: UUID
    let name: String
    let completedAt: Date
    let overallScore: Double
}

struct ApplicantBattleReport: Hashable {
    let projectCount: Int
    let reviewCount: Int
    let taskCompletionScore: Double
    let discussionScore: Double
    let collaborationScore: Double
    let ideaScore: Double
    let reliabilityScore: Double
    let negativeRecordCount: Int
    let projects: [ApplicantProjectRecord]

    var overallScore: Double {
        (taskCompletionScore + discussionScore + collaborationScore + ideaScore + reliabilityScore) / 5
    }
}

struct GroupJoinRequest: Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let applicantID: UUID
    let requestedAt: Date
    let report: ApplicantBattleReport
    var status: GroupJoinRequestStatus
}
