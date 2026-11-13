import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation
import Observation

/// Shared application inbox. Membership remains owned by AppStore.
@MainActor @Observable
final class GroupAdmissionStore {
    private(set) var myRequests: [GroupJoinRequest] = []
    private(set) var incomingRequests: [GroupJoinRequest] = []
    private(set) var loadedIncomingGroupIDs: Set<String> = []
    private(set) var syncError: String?
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var subscriptionKey = ""
    @ObservationIgnored private var incomingByGroup: [String: [GroupJoinRequest]] = [:]
    @ObservationIgnored private var errors: Set<String> = []

    func start(uid: String, leaderGroupIDs: [String], inbox: NotificationInboxStore) {
        let key = ([uid] + leaderGroupIDs.sorted()).joined(separator: "/")
        guard key != subscriptionKey else { return }
        stop()
        subscriptionKey = key
        let generation = session
        let db = Firestore.firestore()
        func listen(_ query: Query, key: String) {
            listeners.append(query.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.session == generation, Auth.auth().currentUser?.uid == uid else { return }
                    do {
                        if let error { throw error }
                        let requests = try (snapshot?.documents ?? []).map(Self.decode)
                            .sorted { $0.requestedAt > $1.requestedAt }
                        self.errors.remove(key)
                        if key == "mine" { self.myRequests = requests }
                        else {
                            if snapshot?.metadata.isFromCache == false {
                                self.loadedIncomingGroupIDs.insert(key)
                            }
                            self.incomingByGroup[key] = requests.filter { $0.status == .pending }
                            self.incomingRequests = self.incomingByGroup.values.flatMap { $0 }
                                .sorted { $0.requestedAt < $1.requestedAt }
                        }
                        inbox.receiveApplications(requests, incoming: key != "mine", uid: uid)
                        if key != "mine", snapshot?.metadata.isFromCache == false {
                            inbox.reconcileAdmissionReviews(groupID: key,
                                pendingIDs: Set(requests.map(\.requestID)), uid: uid)
                        }
                    } catch {
                        self.errors.insert(key)
                        // Never retain applicant data after access is revoked.
                        if key != "mine" {
                            self.incomingByGroup[key] = []
                            self.incomingRequests = self.incomingByGroup.values.flatMap { $0 }
                        }
                    }
                        self.syncError = self.errors.isEmpty ? nil : L10n.text("入群申請同步失敗，請重試。")
                }
            })
        }
        listen(db.collection("users").document(uid).collection("groupJoinRequests"), key: "mine")
        for groupID in leaderGroupIDs {
            listen(db.collection("groups").document(groupID).collection("joinRequests")
                .whereField("status", isEqualTo: "pending"), key: groupID)
        }
    }

    func stop() {
        session = UUID()
        listeners.forEach { $0.remove() }
        listeners = []
        subscriptionKey = ""
        myRequests = []
        incomingRequests = []
        loadedIncomingGroupIDs = []
        incomingByGroup = [:]
        errors = []
        syncError = nil
    }

    func profile(for request: GroupJoinRequest) async throws -> [PersonalPeerReviewProject] {
        let result = try await call("getJoinApplicantProfile", request: request)
        guard let payload = result as? [String: Any], let projects = payload["projects"] as? [[String: Any]] else {
            throw GroupJoinError.invalidGroupData
        }
        return try projects.map { value in
            guard let id = value["groupID"] as? String, let name = value["groupName"] as? String,
                  let date = value["completedAtMillis"] as? NSNumber,
                  let count = value["reviewCount"] as? Int,
                  let completion = value["taskCompletionScore"] as? NSNumber,
                  let discussion = value["discussionScore"] as? NSNumber,
                  let collaboration = value["collaborationScore"] as? NSNumber,
                  let idea = value["ideaScore"] as? NSNumber,
                  let reliability = value["reliabilityScore"] as? NSNumber else { throw GroupJoinError.invalidGroupData }
            return PersonalPeerReviewProject(groupID: id, groupName: name,
                completedAt: Date(timeIntervalSince1970: date.doubleValue / 1_000), reviewCount: count,
                acceptedReviewCount: value["acceptedReviewCount"] as? Int ?? count,
                excludedReviewCount: value["excludedReviewCount"] as? Int ?? 0,
                taskCompletionScoreTotal: 0, discussionScoreTotal: 0, collaborationScoreTotal: 0,
                ideaScoreTotal: 0, reliabilityScoreTotal: 0,
                taskCompletionScore: completion.doubleValue, discussionScore: discussion.doubleValue,
                collaborationScore: collaboration.doubleValue, ideaScore: idea.doubleValue,
                reliabilityScore: reliability.doubleValue)
        }.sorted { $0.completedAt > $1.completedAt }
    }

    func review(_ request: GroupJoinRequest, approve: Bool) async throws {
        _ = try await call("reviewGroupJoinRequest", request: request,
                          extra: ["decision": approve ? "approved" : "rejected"])
    }

    private func call(_ name: String, request: GroupJoinRequest, extra: [String: Any] = [:]) async throws -> Any {
        guard let uid = Auth.auth().currentUser?.uid else { throw GroupJoinError.notAuthenticated }
        let generation = session
        var data: [String: Any] = ["groupID": request.groupID, "applicantID": request.applicantID,
                                   "requestID": request.requestID]
        data.merge(extra) { _, new in new }
        let result = try await Functions.functions(region: "asia-east1").httpsCallable(name).call(data)
        guard Auth.auth().currentUser?.uid == uid, session == generation else { throw GroupJoinError.notAuthenticated }
        return result.data
    }

    private static func decode(_ document: QueryDocumentSnapshot) throws -> GroupJoinRequest {
        let d = document.data()
        guard let groupID = d["groupID"] as? String, let groupName = d["groupName"] as? String,
              let applicantID = d["applicantID"] as? String, let applicantName = d["applicantName"] as? String,
              let requestID = d["requestID"] as? String,
              let rawStatus = d["status"] as? String, let status = GroupJoinRequest.Status(rawValue: rawStatus),
              let requestedAt = d["requestedAt"] as? Timestamp else { throw GroupJoinError.invalidGroupData }
        return GroupJoinRequest(requestID: requestID, groupID: groupID, groupName: groupName,
            applicantID: applicantID, applicantName: applicantName, requestedAt: requestedAt.dateValue(), status: status,
            reviewedAt: (d["reviewedAt"] as? Timestamp)?.dateValue())
    }
}
