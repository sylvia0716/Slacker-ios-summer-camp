import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import Foundation
import UIKit

enum PokeRepositoryError: LocalizedError {
    case notAuthenticated
    case notGroupMember
    case invalidRecipient
    case network
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: L10n.text("請先登入再戳隊友。")
        case .notGroupMember: L10n.text("你必須先加入此群組才能戳隊友。")
        case .invalidRecipient: L10n.text("只能戳同一群組的其他成員。")
        case .network: L10n.text("網路連線異常，請確認網路後重試。")
        case .unavailable: L10n.text("目前無法送出戳戳，請稍後再試。")
        }
    }
}

@MainActor
final class PokeRepository {
    private static let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private static var registrationTask: Task<Void, Error>?
    private static var registrationSuspended = false

    private let functions: Functions
    private let firestore: Firestore

    init(
        functions: Functions = Functions.functions(region: "asia-east1"),
        firestore: Firestore = Firestore.firestore()
    ) {
        self.functions = functions
        self.firestore = firestore
    }

    func send(groupID: String, recipientUID: String, style: PokeStyle) async throws {
        guard Auth.auth().currentUser != nil else { throw PokeRepositoryError.notAuthenticated }
        do {
            _ = try await functions.httpsCallable("sendPoke").call([
                "groupID": groupID,
                "recipientUID": recipientUID,
                "style": style.rawValue,
            ])
        } catch {
            throw Self.map(error)
        }
    }

    func registerCurrentDevice() async throws {
        guard !Self.registrationSuspended,
              let uid = Auth.auth().currentUser?.uid else { return }
        let previous = Self.registrationTask
        let task = Task { @MainActor in
            _ = await previous?.result
            guard !Self.registrationSuspended, Auth.auth().currentUser?.uid == uid else { return }
            let token = try await Messaging.messaging().token()
            guard !Self.registrationSuspended, Auth.auth().currentUser?.uid == uid else { return }
            _ = try await self.functions.httpsCallable("registerPokeDevice").call([
                "deviceID": Self.deviceID,
                "token": token,
                "languageCode": AppLanguageSettings.shared.language.rawValue,
                "pokesEnabled": PokeDeliveryState.shared.receivesPokes,
            ])
        }
        Self.registrationTask = task
        try await task.value
    }

    /// Finish any old registration before revoking it, while still authenticated as its owner.
    func prepareForAccountChange() async throws {
        Self.registrationSuspended = true
        _ = await Self.registrationTask?.result
        guard Auth.auth().currentUser != nil else { return }
        _ = try await functions.httpsCallable("unregisterPokeDevice").call([
            "deviceID": Self.deviceID
        ])
        // Rotate the token so legacy registrations under other accounts cannot reach this device.
        try await Messaging.messaging().deleteToken()
        await PokeNotificationService().clearAccountNotifications()
    }

    static func resumeDeviceRegistration() {
        registrationSuspended = false
        Task { try? await PokeRepository().registerCurrentDevice() }
    }

    @discardableResult
    func listenForIncomingPokes(
        groupID: String,
        recipientUID: String,
        onReceive: @escaping (Result<[PokeReception], Error>) -> Void
    ) -> ListenerRegistration {
        incomingQuery(groupID: groupID, recipientUID: recipientUID)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onReceive(.failure(error))
                    return
                }

                // Cached snapshots must not establish or advance the delivery baseline.
                guard let snapshot, !snapshot.metadata.isFromCache else { return }
                onReceive(.success(snapshot.documents.compactMap { Self.reception(from: $0.data()) }))
            }
    }

    func latestIncomingPoke(groupID: String, recipientUID: String) async throws -> PokeReception? {
        let snapshot = try await incomingQuery(groupID: groupID, recipientUID: recipientUID)
            .getDocuments(source: .server)
        return snapshot.documents.first.flatMap { Self.reception(from: $0.data()) }
    }

    private func incomingQuery(groupID: String, recipientUID: String) -> Query {
        firestore.collection("groups").document(groupID).collection("pokes")
            .whereField("recipientID", isEqualTo: recipientUID)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
    }

    nonisolated private static func reception(from data: [String: Any]) -> PokeReception? {
        guard let recipientUID = data["recipientID"] as? String,
              let groupName = data["groupName"] as? String,
              let pokeCount = data["pokeCount"] as? Int, pokeCount > 0,
              let styleRawValue = data["style"] as? String,
              let style = PokeStyle(rawValue: styleRawValue) else { return nil }
        return PokeReception(groupName: groupName, pokeCount: pokeCount, style: style, recipientUID: recipientUID)
    }

    private static func map(_ error: Error) -> PokeRepositoryError {
        let nsError = error as NSError
        let reason = (nsError.userInfo["details"] as? [String: Any])?["reason"] as? String
        switch reason {
        case "not-authenticated": return .notAuthenticated
        case "not-group-member": return .notGroupMember
        case "invalid-recipient": return .invalidRecipient
        default: break
        }
        switch nsError.code {
        case 16: return .notAuthenticated
        case 7: return .notGroupMember
        case 3, 9: return .invalidRecipient
        case 14, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return .network
        default: return .unavailable
        }
    }
}
