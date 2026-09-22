import Foundation
import Observation

struct ReviewNotificationRoute: Hashable {
    let id = UUID()
    let groupID: UUID
}

struct ReviewNotificationDestination: Equatable {
    let uid: String
    let groupID: UUID

    init?(userInfo: [AnyHashable: Any]) {
        guard userInfo["destination"] as? String == "peerReview",
              let uid = userInfo["recipientUID"] as? String,
              let rawID = userInfo["groupID"] as? String,
              let groupID = UUID(uuidString: rawID) else { return nil }
        self.uid = uid
        self.groupID = groupID
    }
}

/// Retains notification taps until authentication and group loading finish on cold launch.
@MainActor @Observable
final class ReviewNotificationRouter {
    static let shared = ReviewNotificationRouter()
    var pending: ReviewNotificationDestination?
}
