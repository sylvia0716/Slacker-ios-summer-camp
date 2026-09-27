import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Firestore 時間軸項目的類型；舊資料沒有 kind 時視為一般成員訊息。
enum CloudChatItemKind: String {
    case message
    case botReply
    case botAnalysis
    case agendaReminder
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
    let taskCompletionScore: Int?
    let discussionScore: Int?
    let collaborationScore: Int?
    let problemSolvingScore: Int?
    let reliabilityScore: Int?
    var agendaSummary: AgendaChatSummary? = nil
}

/// 群組內一位成員的即時在線狀態。
struct ChatPresence: Identifiable {
    let userID: String
    let displayName: String
    let isOnline: Bool
    let lastSeenAt: Date

    var id: String { userID }
}

struct ChatReadReceipt: Identifiable {
    let userID: String
    let messageID: String
    var id: String { userID }
}

struct ChatPinnedMessage: Identifiable {
    let messageID: String
    let senderName: String
    let text: String
    var id: String { messageID }
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
            "senderName": L10n.text("拆彈 AI 通訊官"),
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
        var data: [String: Any] = [
            "id": id,
            "senderID": userID,
            "senderName": L10n.text("拆彈 AI 通訊官"),
            "text": analysis.summary,
            "kind": CloudChatItemKind.botAnalysis.rawValue,
            "analysisScore": analysis.score,
            "analysisStrength": analysis.strength,
            "analysisSuggestion": analysis.suggestion,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let taskCompletionScore = analysis.taskCompletionScore,
           let discussionScore = analysis.discussionScore,
           let collaborationScore = analysis.collaborationScore,
           let problemSolvingScore = analysis.problemSolvingScore,
           let reliabilityScore = analysis.reliabilityScore {
            data["taskCompletionScore"] = taskCompletionScore
            data["discussionScore"] = discussionScore
            data["collaborationScore"] = collaborationScore
            data["problemSolvingScore"] = problemSolvingScore
            data["reliabilityScore"] = reliabilityScore
        }
        try await messagesCollection(groupID: groupID).document(id).setData(data)
    }

    func loadHumanConversation(groupID: String) async throws -> [String] {
        let snapshot = try await recentMessages(groupID: groupID)
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard (data["kind"] as? String ?? CloudChatItemKind.message.rawValue)
                    == CloudChatItemKind.message.rawValue,
                  let senderName = data["senderName"] as? String,
                  let text = data["text"] as? String,
                  !text.hasPrefix("@機器人"),
                  !text.hasPrefix("＠機器人"),
                  !text.hasPrefix("@bot"),
                  !text.hasPrefix("＠bot"),
                  !text.hasPrefix("@Bomb AI") else { return nil }
            return "\(senderName)：\(text)"
        }
    }

    func loadLatestProjectAnalysis(groupID: String, appGroupID: UUID) async throws -> CommunicationAnalysis? {
        let snapshot = try await recentMessages(groupID: groupID)
        return snapshot.documents.reversed().compactMap { document -> CommunicationAnalysis? in
            let data = document.data()
            guard data["kind"] as? String == CloudChatItemKind.botAnalysis.rawValue,
                  let id = UUID(uuidString: document.documentID),
                  let score = data["analysisScore"] as? Int,
                  let summary = data["text"] as? String,
                  let strength = data["analysisStrength"] as? String,
                  let suggestion = data["analysisSuggestion"] as? String,
                  let taskCompletionScore = data["taskCompletionScore"] as? Int,
                  let discussionScore = data["discussionScore"] as? Int,
                  let collaborationScore = data["collaborationScore"] as? Int,
                  let problemSolvingScore = data["problemSolvingScore"] as? Int,
                  let reliabilityScore = data["reliabilityScore"] as? Int else { return nil }
            return CommunicationAnalysis(
                id: id,
                groupID: appGroupID,
                score: score,
                summary: summary,
                strength: strength,
                suggestion: suggestion,
                updatedAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
                taskCompletionScore: taskCompletionScore,
                discussionScore: discussionScore,
                collaborationScore: collaborationScore,
                problemSolvingScore: problemSolvingScore,
                reliabilityScore: reliabilityScore
            )
        }.first
    }

    private func recentMessages(groupID: String) async throws -> QuerySnapshot {
        try await messagesCollection(groupID: groupID)
            .order(by: "createdAt")
            .limit(toLast: 200)
            .getDocuments()
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
                        analysisSuggestion: data["analysisSuggestion"] as? String,
                        taskCompletionScore: data["taskCompletionScore"] as? Int,
                        discussionScore: data["discussionScore"] as? Int,
                        collaborationScore: data["collaborationScore"] as? Int,
                        problemSolvingScore: data["problemSolvingScore"] as? Int,
                        reliabilityScore: data["reliabilityScore"] as? Int,
                        agendaSummary: (data["agendaSummary"] as? [String: Any]).flatMap { value in
                            guard let json = try? JSONSerialization.data(withJSONObject: value) else { return nil }
                            return try? JSONDecoder().decode(AgendaChatSummary.self, from: json)
                        }
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

    @discardableResult
    func listenToReadReceipts(
        groupID: String,
        onChange: @escaping (Result<[ChatReadReceipt], Error>) -> Void
    ) -> ListenerRegistration {
        firestore.collection("groups").document(groupID).collection("readReceipts")
            .addSnapshotListener { snapshot, error in
                if let error { onChange(.failure(error)); return }
                onChange(.success((snapshot?.documents ?? []).compactMap { document in
                    guard let messageID = document.data()["messageID"] as? String else { return nil }
                    return ChatReadReceipt(userID: document.documentID, messageID: messageID)
                }))
            }
    }

    func markRead(groupID: String, messageID: String) async throws {
        let userID = try currentUserID()
        try await firestore.collection("groups").document(groupID)
            .collection("readReceipts").document(userID).setData([
                "messageID": messageID,
                "readAt": FieldValue.serverTimestamp()
            ])
    }

    @discardableResult
    func listenToPinnedMessage(
        groupID: String,
        onChange: @escaping (Result<ChatPinnedMessage?, Error>) -> Void
    ) -> ListenerRegistration {
        firestore.collection("groups").document(groupID).collection("chatSettings")
            .document("pin").addSnapshotListener { snapshot, error in
                if let error { onChange(.failure(error)); return }
                guard let data = snapshot?.data(),
                      let messageID = data["messageID"] as? String,
                      let senderName = data["senderName"] as? String,
                      let text = data["text"] as? String else {
                    onChange(.success(nil))
                    return
                }
                onChange(.success(ChatPinnedMessage(
                    messageID: messageID, senderName: senderName, text: text
                )))
            }
    }

    func setPinnedMessage(groupID: String, message: ChatPinnedMessage?) async throws {
        let reference = firestore.collection("groups").document(groupID)
            .collection("chatSettings").document("pin")
        if let message {
            try await reference.setData([
                "messageID": message.messageID,
                "senderName": message.senderName,
                "text": message.text
            ])
        } else {
            try await reference.delete()
        }
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
            L10n.text("請先登入再使用聊天室。")
        case .notGroupMember:
            L10n.text("目前帳號不是這個雲端群組的成員。")
        }
    }
}
