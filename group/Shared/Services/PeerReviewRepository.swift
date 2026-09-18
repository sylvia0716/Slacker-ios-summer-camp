import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct CloudPeerReviewStateDocument: Codable {
    var reviewedUIDs: [String] = []
    var completed: Bool = false
}

struct CloudPeerReviewSummaryDocument: Codable {
    var totalReviewCount: Int = 0
    var completedReviewerCount: Int = 0
    var taskCompletionScoreTotal: Int = 0
    var discussionScoreTotal: Int = 0
    var collaborationScoreTotal: Int = 0
    var ideaScoreTotal: Int = 0
    var reliabilityScoreTotal: Int = 0
    var resultsAvailable: Bool = false
}

struct CloudPeerReviewCommentsDocument: Codable {
    var comments: [String] = []
}

@MainActor
final class PeerReviewRepository {
    func submit(
        groupID: String,
        revieweeUID: String,
        taskCompletionScore: Int,
        discussionScore: Int,
        collaborationScore: Int,
        ideaScore: Int,
        reliabilityScore: Int,
        comment: String
    ) async throws {
        guard Auth.auth().currentUser != nil else {
            throw PeerReviewCloudError.signedOut
        }
        let payload: [String: Any] = [
            "groupID": groupID,
            "revieweeUID": revieweeUID,
            "taskCompletionScore": taskCompletionScore,
            "discussionScore": discussionScore,
            "collaborationScore": collaborationScore,
            "ideaScore": ideaScore,
            "reliabilityScore": reliabilityScore,
            "comment": String(comment.prefix(200))
        ]

        do {
            _ = try await Functions.functions(region: "asia-east1")
                .httpsCallable("submitPeerReview").call(payload)
        } catch {
            let nsError = error as NSError
            switch FunctionsErrorCode(rawValue: nsError.code) {
            case .unauthenticated:
                throw PeerReviewCloudError.signedOut
            case .alreadyExists:
                throw PeerReviewSubmissionError.duplicateReview
            case .permissionDenied:
                throw PeerReviewSubmissionError.memberNotInGroup
            case .failedPrecondition:
                throw PeerReviewSubmissionError.groupStillActive
            default:
                throw PeerReviewCloudError.syncFailed
            }
        }
    }

    func listenToMyState(
        groupID: String,
        receive: @escaping (Result<CloudPeerReviewStateDocument, Error>) -> Void
    ) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else {
            receive(.failure(PeerReviewCloudError.signedOut))
            return nil
        }
        return Firestore.firestore().collection("groups").document(groupID)
            .collection("peerReviewStates").document(uid)
            .addSnapshotListener { snapshot, error in
                if let error {
                    receive(.failure(error))
                    return
                }
                guard let snapshot, snapshot.exists else {
                    receive(.success(CloudPeerReviewStateDocument()))
                    return
                }
                do {
                    receive(.success(try snapshot.data(as: CloudPeerReviewStateDocument.self)))
                } catch {
                    receive(.failure(error))
                }
            }
    }

    func listenToSummary(
        groupID: String,
        receive: @escaping (Result<CloudPeerReviewSummaryDocument, Error>) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore().collection("groups").document(groupID)
            .collection("peerReviewPublic").document("summary")
            .addSnapshotListener { snapshot, error in
                if let error {
                    receive(.failure(error))
                    return
                }
                guard let snapshot, snapshot.exists else {
                    receive(.success(CloudPeerReviewSummaryDocument()))
                    return
                }
                do {
                    receive(.success(try snapshot.data(as: CloudPeerReviewSummaryDocument.self)))
                } catch {
                    receive(.failure(error))
                }
            }
    }

    func listenToMyComments(
        groupID: String,
        receive: @escaping (Result<CloudPeerReviewCommentsDocument, Error>) -> Void
    ) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid else {
            receive(.failure(PeerReviewCloudError.signedOut))
            return nil
        }
        return Firestore.firestore().collection("groups").document(groupID)
            .collection("peerReviewComments").document(uid)
            .addSnapshotListener { snapshot, error in
                if let error {
                    receive(.failure(error))
                    return
                }
                guard let snapshot, snapshot.exists else {
                    receive(.success(CloudPeerReviewCommentsDocument()))
                    return
                }
                do {
                    receive(.success(try snapshot.data(as: CloudPeerReviewCommentsDocument.self)))
                } catch {
                    receive(.failure(error))
                }
            }
    }

    func loadMyComments(groupID: String) async throws -> [String] {
        guard Auth.auth().currentUser != nil else {
            throw PeerReviewCloudError.signedOut
        }
        do {
            let result = try await Functions.functions(region: "asia-east1")
                .httpsCallable("getPeerReviewComments")
                .call(["groupID": groupID])
            guard let payload = result.data as? [String: Any],
                  let comments = payload["comments"] as? [String] else {
                throw PeerReviewCloudError.syncFailed
            }
            return comments
        } catch let error as PeerReviewCloudError {
            throw error
        } catch {
            throw PeerReviewCloudError.syncFailed
        }
    }
}

enum PeerReviewCloudError: LocalizedError {
    case signedOut
    case memberNotFound
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .signedOut:
            "請先登入再送出互評。"
        case .memberNotFound:
            "找不到這位群組成員，請重新載入後再試。"
        case .syncFailed:
            "互評同步失敗，請確認網路後再試。"
        }
    }
}
