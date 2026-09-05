import Foundation

/// 聊天室時間軸中的一筆內容；由 AppStore 依群組保存，避免離開畫面後記錄消失。
enum ChatRoomItem: Identifiable, Codable {
    /// 一般成員訊息；isCurrentUser 決定訊息泡泡顯示方向。
    case message(id: String, sender: String, text: String, time: String, isCurrentUser: Bool)
    /// 任務進度或成員加入等系統事件。
    case systemEvent(id: String, icon: String, text: String)
    /// AI 對目前聊天室內容產生的溝通分析。
    case botAnalysis(id: String, analysis: CommunicationAnalysis)
    /// AI 機器人的一般文字回覆。
    case botReply(id: String, text: String)

    var id: String {
        switch self {
        case let .message(id, _, _, _, _),
             let .systemEvent(id, _, _),
             let .botAnalysis(id, _),
             let .botReply(id, _):
            id
        }
    }

    /// 供機器人評分使用的純文字訊息；系統事件與機器人回覆不納入計算。
    var messageText: String? {
        guard case let .message(_, _, text, _, _) = self else { return nil }
        return text
    }

    /// 供 Apple Intelligence 判讀協作情形的成員與訊息內容；排除機器人指令。
    var humanConversationLine: String? {
        guard case let .message(_, sender, text, _, _) = self,
              !text.hasPrefix("@機器人"),
              !text.hasPrefix("＠機器人") else { return nil }
        return "\(sender)：\(text)"
    }

    /// 從已保存的聊天室時間軸恢復設定頁使用的 AI 戰情報告。
    var communicationAnalysis: CommunicationAnalysis? {
        guard case let .botAnalysis(_, analysis) = self else { return nil }
        return analysis
    }
}
