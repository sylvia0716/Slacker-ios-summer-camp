import Foundation

enum ChatMessageDeliveryState: String, Codable {
    case sending
    case sent
    case failed
}

/// 聊天室時間軸中的一筆內容；由 AppStore 依群組保存，避免離開畫面後記錄消失。
enum ChatRoomItem: Identifiable, Codable {
    /// 一般成員訊息；isCurrentUser 決定訊息泡泡顯示方向。
    case message(
        id: String,
        sender: String,
        text: String,
        time: String,
        isCurrentUser: Bool,
        createdAt: Date,
        deliveryState: ChatMessageDeliveryState
    )
    /// 任務進度或成員加入等系統事件。
    case systemEvent(id: String, icon: String, text: String, createdAt: Date)
    /// AI 對目前聊天室內容產生的溝通分析。
    case botAnalysis(id: String, analysis: CommunicationAnalysis)
    /// AI 機器人的一般文字回覆。
    case botReply(id: String, text: String, createdAt: Date)

    var id: String {
        switch self {
        case let .message(id, _, _, _, _, _, _),
             let .systemEvent(id, _, _, _),
             let .botAnalysis(id, _),
             let .botReply(id, _, _):
            id
        }
    }

    /// 所有來源共用的排序時間；舊版無時間戳的本機內容會排在新的雲端訊息之前。
    var createdAt: Date {
        switch self {
        case let .message(_, _, _, _, _, createdAt, _),
             let .systemEvent(_, _, _, createdAt),
             let .botReply(_, _, createdAt):
            createdAt
        case let .botAnalysis(_, analysis):
            analysis.updatedAt
        }
    }

    /// 供機器人評分使用的純文字訊息；系統事件與機器人回覆不納入計算。
    var messageText: String? {
        guard case let .message(_, _, text, _, _, _, _) = self else { return nil }
        return text
    }

    /// 供 Apple Intelligence 判讀協作情形的成員與訊息內容；排除機器人指令。
    var humanConversationLine: String? {
        guard case let .message(_, sender, text, _, _, _, _) = self,
              !text.hasPrefix("@機器人"),
              !text.hasPrefix("＠機器人"),
                  !text.hasPrefix("@bot"),
                  !text.hasPrefix("＠bot"),
                  !text.hasPrefix("@Bomb AI") else { return nil }
        return "\(sender)：\(text)"
    }

    /// 從已保存的聊天室時間軸恢復設定頁使用的 AI 戰情報告。
    var communicationAnalysis: CommunicationAnalysis? {
        guard case let .botAnalysis(_, analysis) = self else { return nil }
        return analysis
    }

    var deliveryState: ChatMessageDeliveryState? {
        guard case let .message(_, _, _, _, _, _, deliveryState) = self else { return nil }
        return deliveryState
    }

    func updatingDeliveryState(_ deliveryState: ChatMessageDeliveryState) -> ChatRoomItem {
        guard case let .message(id, sender, text, time, isCurrentUser, createdAt, _) = self else {
            return self
        }
        return .message(
            id: id,
            sender: sender,
            text: text,
            time: time,
            isCurrentUser: isCurrentUser,
            createdAt: createdAt,
            deliveryState: deliveryState
        )
    }

    /// App 若在傳送途中關閉，下次開啟時改為可重試狀態，避免永久卡在「傳送中」。
    var restoringInterruptedDelivery: ChatRoomItem {
        deliveryState == .sending ? updatingDeliveryState(.failed) : self
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case systemEvent
        case botAnalysis
        case botReply
    }

    private struct MessagePayload: Codable {
        let id: String
        let sender: String
        let text: String
        let time: String
        let isCurrentUser: Bool
        let createdAt: Date?
        let deliveryState: ChatMessageDeliveryState?
    }

    private struct SystemEventPayload: Codable {
        let id: String
        let icon: String
        let text: String
        let createdAt: Date?
    }

    private struct BotAnalysisPayload: Codable {
        let id: String
        let analysis: CommunicationAnalysis
    }

    private struct BotReplyPayload: Codable {
        let id: String
        let text: String
        let createdAt: Date?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.message) {
            let payload = try container.decode(MessagePayload.self, forKey: .message)
            self = .message(
                id: payload.id,
                sender: payload.sender,
                text: payload.text,
                time: payload.time,
                isCurrentUser: payload.isCurrentUser,
                createdAt: payload.createdAt ?? .distantPast,
                deliveryState: payload.deliveryState ?? .sent
            )
        } else if container.contains(.systemEvent) {
            let payload = try container.decode(SystemEventPayload.self, forKey: .systemEvent)
            self = .systemEvent(
                id: payload.id,
                icon: payload.icon,
                text: payload.text,
                createdAt: payload.createdAt ?? .distantPast
            )
        } else if container.contains(.botAnalysis) {
            let payload = try container.decode(BotAnalysisPayload.self, forKey: .botAnalysis)
            self = .botAnalysis(id: payload.id, analysis: payload.analysis)
        } else {
            let payload = try container.decode(BotReplyPayload.self, forKey: .botReply)
            self = .botReply(
                id: payload.id,
                text: payload.text,
                createdAt: payload.createdAt ?? .distantPast
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .message(id, sender, text, time, isCurrentUser, createdAt, deliveryState):
            try container.encode(
                MessagePayload(
                    id: id,
                    sender: sender,
                    text: text,
                    time: time,
                    isCurrentUser: isCurrentUser,
                    createdAt: createdAt,
                    deliveryState: deliveryState
                ),
                forKey: .message
            )
        case let .systemEvent(id, icon, text, createdAt):
            try container.encode(
                SystemEventPayload(id: id, icon: icon, text: text, createdAt: createdAt),
                forKey: .systemEvent
            )
        case let .botAnalysis(id, analysis):
            try container.encode(
                BotAnalysisPayload(id: id, analysis: analysis),
                forKey: .botAnalysis
            )
        case let .botReply(id, text, createdAt):
            try container.encode(
                BotReplyPayload(id: id, text: text, createdAt: createdAt),
                forKey: .botReply
            )
        }
    }
}
