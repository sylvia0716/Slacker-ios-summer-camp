import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Firestore 時間軸項目的類型；舊資料沒有 kind 時視為一般成員訊息。
enum CloudChatItemKind: String {
    case message
    case botReply
    case botAnalysis
}

/// Firestore 聊天時間軸項目；一般訊息與 AI 結果共用伺服器時間排序。
struct CloudChatMessage: Identifiable {
    let id: String
    let senderID: String
    let senderName: String
    let text: String
    let createdAt: Date
    let kind: CloudChatItemKind
    let analysisScore: Int?
    let analysisStrength: String?
    let analysisSuggestion: String?
}

/// 群組內一位成員的即時在線狀態。
struct ChatPresence: Identifiable {
    let userID: String
    let displayName: String
    let isOnline: Bool
    let lastSeenAt: Date

    var id: String { userID }
}

/// 集中處理聊天室訊息、成員身分與在線狀態，避免 SwiftUI View 直接操作 Firebase。
final class ChatRepository {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    /// 聊天室只驗證既有成員身分；新增成員必須由受信任的 Cloud Function 處理。
    func ensureMembership(groupID: String, displayName: String) async throws {
        let userID = try currentUserID()
        let reference = memberReference(groupID: groupID, userID: userID)
        let snapshot = try await reference.getDocument()

        guard snapshot.exists else { throw ChatRepositoryError.notGroupMember }
        try await reference.updateData(["displayName": displayName])
    }

    func sendMessage(
        id: String,
        groupID: String,
        senderName: String,
        text: String
    ) async throws {
        let userID = try currentUserID()
        try await messagesCollection(groupID: groupID).document(id).setData([
            "id": id,
            "senderID": userID,
            "senderName": senderName,
            "text": text,
            "kind": CloudChatItemKind.message.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func sendBotReply(id: String, groupID: String, text: String) async throws {
        let userID = try currentUserID()
        try await messagesCollection(groupID: groupID).document(id).setData([
            "id": id,
            "senderID": userID,
            "senderName": "拆彈 AI 通訊官",
            "text": text,
            "kind": CloudChatItemKind.botReply.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func sendBotAnalysis(
        id: String,
        groupID: String,
        analysis: CommunicationAnalysis
    ) async throws {
        let userID = try currentUserID()
        try await messagesCollection(groupID: groupID).document(id).setData([
            "id": id,
            "senderID": userID,
            "senderName": "拆彈 AI 通訊官",
            "text": analysis.summary,
            "kind": CloudChatItemKind.botAnalysis.rawValue,
            "analysisScore": analysis.score,
            "analysisStrength": analysis.strength,
            "analysisSuggestion": analysis.suggestion,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    @discardableResult
    func listenToMessages(
        groupID: String,
        onChange: @escaping (Result<[CloudChatMessage], Error>) -> Void
    ) -> ListenerRegistration {
        messagesCollection(groupID: groupID)
            .order(by: "createdAt")
            .limit(toLast: 200)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }

                let messages: [CloudChatMessage] = (snapshot?.documents ?? []).compactMap { document in
                    let data = document.data()
                    guard let senderID = data["senderID"] as? String,
                          let senderName = data["senderName"] as? String,
                          let text = data["text"] as? String else { return nil }

                    return CloudChatMessage(
                        id: document.documentID,
                        senderID: senderID,
                        senderName: senderName,
                        text: text,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
                        kind: CloudChatItemKind(
                            rawValue: data["kind"] as? String ?? CloudChatItemKind.message.rawValue
                        ) ?? .message,
                        analysisScore: data["analysisScore"] as? Int,
                        analysisStrength: data["analysisStrength"] as? String,
                        analysisSuggestion: data["analysisSuggestion"] as? String
                    )
                }
                onChange(.success(messages))
            }
    }

    @discardableResult
    func listenToPresence(
        groupID: String,
        onChange: @escaping (Result<[ChatPresence], Error>) -> Void
    ) -> ListenerRegistration {
        presenceCollection(groupID: groupID)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }

                let presences: [ChatPresence] = (snapshot?.documents ?? []).compactMap { document in
                    let data = document.data()
                    guard let userID = data["userID"] as? String,
                          let displayName = data["displayName"] as? String,
                          let isOnline = data["isOnline"] as? Bool else { return nil }

                    return ChatPresence(
                        userID: userID,
                        displayName: displayName,
                        isOnline: isOnline,
                        lastSeenAt: (data["lastSeenAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    )
                }
                onChange(.success(presences))
            }
    }

    func setPresence(groupID: String, displayName: String, isOnline: Bool) async throws {
        let userID = try currentUserID()
        try await presenceCollection(groupID: groupID).document(userID).setData([
            "userID": userID,
            "displayName": displayName,
            "isOnline": isOnline,
            "lastSeenAt": FieldValue.serverTimestamp()
        ])
    }

    private func messagesCollection(groupID: String) -> CollectionReference {
        firestore.collection("groups").document(groupID).collection("messages")
    }

    private func presenceCollection(groupID: String) -> CollectionReference {
        firestore.collection("groups").document(groupID).collection("presence")
    }

    private func memberReference(groupID: String, userID: String) -> DocumentReference {
        firestore.collection("groups")
            .document(groupID)
            .collection("members")
            .document(userID)
    }

    private func currentUserID() throws -> String {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw ChatRepositoryError.notAuthenticated
        }
        return userID
    }
}

enum ChatRepositoryError: LocalizedError {
    case notAuthenticated
    case notGroupMember

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "請先登入再使用聊天室。"
        case .notGroupMember:
            "目前帳號不是這個雲端群組的成員。"
        }
    }
}
