import FirebaseAuth
import FirebaseFunctions
import Foundation
import Observation

struct CloudJoinRequest: Identifiable, Decodable {
    let id: String
    let groupID: String
    let groupName: String
    let displayName: String
    let status: String
    let version: String
    let requestedAt: Double
    let report: Report?

    struct Report: Decodable {
        let projectCount: Int
        let reviewCount: Int
        let taskCompletionScore: Double?
        let discussionScore: Double?
        let collaborationScore: Double?
        let ideaScore: Double?
        let reliabilityScore: Double?
    }

    var statusText: String {
        switch status {
        case "pending": L10n.text("申請中，等待組長審核")
        case "approved": L10n.text("申請已核准")
        case "rejected": L10n.text("申請未通過，未加入群組")
        default: L10n.text("申請已失效，群組已結束或邀請碼已失效")
        }
    }
}

@MainActor @Observable
final class CloudJoinRequestStore {
    private(set) var requests: [CloudJoinRequest] = []
    private(set) var errorMessage: String?
    private(set) var busy = false
    @ObservationIgnored private var accountUID: String?
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var generation = UUID()

    func reset() {
        generation = UUID()
        accountUID = nil
        requests = []
        errorMessage = nil
        busy = false
    }

    func refresh(groupID: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { reset(); return }
        if accountUID != uid || scope != groupID {
            reset()
            accountUID = uid
            scope = groupID
        }
        let token = generation
        do {
            let result = try await Functions.functions(region: "asia-east1")
                .httpsCallable("listGroupJoinRequests").call(groupID.map { ["groupID": $0] } ?? [:])
            struct Response: Decodable { let requests: [CloudJoinRequest] }
            let data = try JSONSerialization.data(withJSONObject: result.data)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard generation == token, Auth.auth().currentUser?.uid == uid, !Task.isCancelled else { return }
            requests = decoded.requests
            errorMessage = nil
        } catch {
            guard generation == token, Auth.auth().currentUser?.uid == uid, !Task.isCancelled else { return }
            if (error as NSError).code == FunctionsErrorCode.permissionDenied.rawValue { requests = [] }
            errorMessage = L10n.text("入群申請更新失敗，請重試。")
        }
    }

    func decide(_ request: CloudJoinRequest, approve: Bool) async -> String? {
        guard !busy, let uid = accountUID, uid == Auth.auth().currentUser?.uid else { return nil }
        busy = true
        let token = generation
        defer { if token == generation { busy = false } }
        do {
            let result = try await Functions.functions(region: "asia-east1").httpsCallable("decideGroupJoinRequest").call([
                "requestID": request.id, "version": request.version, "approve": approve,
            ])
            guard token == generation, Auth.auth().currentUser?.uid == uid else { return nil }
            await refresh(groupID: request.groupID)
            guard token == generation, Auth.auth().currentUser?.uid == uid else { return nil }
            return (result.data as? [String: Any])?["status"] as? String
        } catch {
            guard token == generation, Auth.auth().currentUser?.uid == uid else { return nil }
            errorMessage = L10n.text("審核未完成，請重新整理後重試。")
            return nil
        }
    }
}
