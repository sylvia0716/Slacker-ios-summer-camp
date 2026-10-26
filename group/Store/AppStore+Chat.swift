import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

/// 聊天室：訊息、在線狀態、已讀與釘選的同步。
extension AppStore {
    /// 取得指定群組目前保存的完整聊天內容。
    func chatItems(for groupID: UUID) -> [ChatRoomItem] {
        chatItemsByGroupID[groupID] ?? []
    }

    /// 記錄使用者已看過該群組目前的聊天內容。
    func markChatSeen(in groupID: UUID) {
        let latest = chatItems(for: groupID).map(\.createdAt) + [latestOthersChatDateByGroupID[groupID]].compactMap { $0 }
        lastSeenChatDateByGroupID[groupID] = latest.max() ?? .distantPast
    }

    /// 在群組頁開始追蹤未讀。雲端群組只監聽最新一則訊息，第一次收到時以它作為基準。
    func beginTrackingUnreadChat(in groupID: UUID) {
        guard dataMode == .live else {
            if lastSeenChatDateByGroupID[groupID] == nil { markChatSeen(in: groupID) }
            return
        }
        guard latestChatListeners[groupID] == nil, FirebaseApp.app() != nil else { return }
        let repository = chatRepository ?? ChatRepository()
        chatRepository = repository
        latestChatListeners[groupID] = repository.listenToLatestMessage(
            groupID: cloudGroupDocumentID(for: groupID)
        ) { [weak self] createdAt, senderID in
            Task { @MainActor in
                guard let self else { return }
                if self.lastSeenChatDateByGroupID[groupID] == nil {
                    self.lastSeenChatDateByGroupID[groupID] = createdAt ?? .distantPast
                }
                if let createdAt, senderID != self.firebaseUID {
                    self.latestOthersChatDateByGroupID[groupID] = createdAt
                }
            }
        }
    }

    /// 離開群組頁時停止監聽最新訊息；聊天室內另有完整的訊息監聽。
    func endTrackingUnreadChat(in groupID: UUID) {
        latestChatListeners.removeValue(forKey: groupID)?.remove()
    }

    /// 是否有使用者還沒在聊天室看過、由別人送出的新內容。
    func hasUnreadChat(in groupID: UUID) -> Bool {
        guard let seenDate = lastSeenChatDateByGroupID[groupID] else { return false }
        if let latest = latestOthersChatDateByGroupID[groupID], latest > seenDate { return true }
        return chatItems(for: groupID).contains { item in
            if case let .message(_, _, _, _, isCurrentUser, _, _) = item, isCurrentUser { return false }
            return item.createdAt > seenDate
        }
    }

    /// 將新訊息、系統事件或機器人回覆加入指定群組的聊天記錄。
    func appendChatItem(_ item: ChatRoomItem, to groupID: UUID) {
        chatItemsByGroupID[groupID, default: []].append(item)
        saveChatItems()
    }

    /// 進入聊天室後建立 Firebase 成員身分並開始監聽訊息與在線狀態。
    func startChatSync(groupID: UUID, displayName: String) async {
        chatMessageSyncReadyGroupIDs.remove(groupID)
        guard dataMode == .live else {
            chatMessageSyncErrorsByGroupID[groupID] = nil
            chatPresenceSyncErrorsByGroupID[groupID] = nil
            chatReadSyncErrorsByGroupID[groupID] = nil
            chatPinSyncErrorsByGroupID[groupID] = nil
            chatMessageSyncReadyGroupIDs.insert(groupID)
            return
        }
        guard FirebaseApp.app() != nil else {
            let message = L10n.text("Firebase 尚未設定完成。")
            chatMessageSyncErrorsByGroupID[groupID] = message
            chatPresenceSyncErrorsByGroupID[groupID] = message
            chatReadSyncErrorsByGroupID[groupID] = message
            chatPinSyncErrorsByGroupID[groupID] = message
            return
        }

        let repository = chatRepository ?? ChatRepository()
        chatRepository = repository
        let cloudGroupID = cloudGroupDocumentID(for: groupID)
        let normalizedName = normalizedChatDisplayName(displayName)

        do {
            try await repository.ensureMembership(
                groupID: cloudGroupID,
                displayName: normalizedName
            )
        } catch {
            chatMessageSyncErrorsByGroupID[groupID] = error.localizedDescription
            chatPresenceSyncErrorsByGroupID[groupID] = error.localizedDescription
            chatReadSyncErrorsByGroupID[groupID] = error.localizedDescription
            chatPinSyncErrorsByGroupID[groupID] = error.localizedDescription
            return
        }
        guard !Task.isCancelled else { return }

        if chatMessageListeners[groupID] == nil {
            chatMessageListeners[groupID] = repository.listenToMessages(
                groupID: cloudGroupID
            ) { [weak self] result in
                Task { @MainActor in
                    self?.applyChatMessages(result, to: groupID)
                }
            }
        }

        if chatPresenceListeners[groupID] == nil {
            chatPresenceListeners[groupID] = repository.listenToPresence(
                groupID: cloudGroupID
            ) { [weak self] result in
                Task { @MainActor in
                    self?.applyChatPresence(result, to: groupID)
                }
            }
        }

        if chatReadListeners[groupID] == nil {
            chatReadListeners[groupID] = repository.listenToReadReceipts(
                groupID: cloudGroupID
            ) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case let .success(receipts):
                        self?.chatReadReceiptsByGroupID[groupID] = receipts
                        self?.chatReadSyncErrorsByGroupID[groupID] = nil
                    case let .failure(error):
                        self?.chatReadSyncErrorsByGroupID[groupID] = error.localizedDescription
                    }
                }
            }
        }

        if chatPinListeners[groupID] == nil {
            chatPinListeners[groupID] = repository.listenToPinnedMessage(
                groupID: cloudGroupID
            ) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case let .success(message):
                        self?.pinnedChatMessageByGroupID[groupID] = message
                        self?.chatPinSyncErrorsByGroupID[groupID] = nil
                    case let .failure(error):
                        self?.chatPinSyncErrorsByGroupID[groupID] = error.localizedDescription
                    }
                }
            }
        }

        do {
            try await repository.setPresence(
                groupID: cloudGroupID,
                displayName: normalizedName,
                isOnline: true
            )
            chatPresenceSyncErrorsByGroupID[groupID] = nil
        } catch {
            chatPresenceSyncErrorsByGroupID[groupID] = error.localizedDescription
        }
        startChatHeartbeat(
            groupID: groupID,
            cloudGroupID: cloudGroupID,
            displayName: normalizedName,
            repository: repository
        )
    }

    /// 發送一筆由 Firebase Auth UID 標記身分的群組訊息。
    func sendChatMessage(
        id: String,
        text: String,
        groupID: UUID,
        displayName: String
    ) async -> Bool {
        if isDemoMode { return true }
        guard let repository = chatRepository else { return false }

        do {
            try await repository.sendMessage(
                id: id,
                groupID: cloudGroupDocumentID(for: groupID),
                senderName: normalizedChatDisplayName(displayName),
                text: text
            )
            return true
        } catch {
            return false
        }
    }

    /// 將裝置端產生的 AI 回覆寫入群組時間軸，讓所有成員收到同一則結果。
    func sendChatBotReply(id: String, text: String, groupID: UUID) async -> Bool {
        if isDemoMode { return true }
        guard let repository = chatRepository else {
            chatMessageSyncErrorsByGroupID[groupID] = L10n.text("聊天室尚未連線，AI 回覆尚未同步。")
            return false
        }

        do {
            try await repository.sendBotReply(
                id: id,
                groupID: cloudGroupDocumentID(for: groupID),
                text: text
            )
            return true
        } catch {
            chatMessageSyncErrorsByGroupID[groupID] = error.localizedDescription
            return false
        }
    }

    /// 將 AI 溝通分析寫入群組時間軸，其他成員也能看到相同卡片與分數。
    func sendChatBotAnalysis(
        id: String,
        analysis: CommunicationAnalysis,
        groupID: UUID
    ) async -> Bool {
        if isDemoMode { return true }
        let repository = chatRepository ?? ChatRepository()
        chatRepository = repository
        let cloudGroupID = cloudGroupDocumentID(for: groupID)

        do {
            try await repository.sendBotAnalysis(
                id: id,
                groupID: cloudGroupID,
                analysis: analysis
            )
            return true
        } catch {
            chatMessageSyncErrorsByGroupID[groupID] = error.localizedDescription
            return false
        }
    }

    func updateChatMessageDeliveryState(
        id: String,
        groupID: UUID,
        deliveryState: ChatMessageDeliveryState
    ) {
        guard let items = chatItemsByGroupID[groupID],
              let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatItemsByGroupID[groupID]?[index] = items[index].updatingDeliveryState(deliveryState)
        saveChatItems()
    }

    /// App 前景狀態改變時立即刷新 presence；心跳會持續處理異常中斷的逾時。
    func updateChatPresence(groupID: UUID, displayName: String, isOnline: Bool) {
        guard !isDemoMode else { return }
        guard let repository = chatRepository else { return }
        let cloudGroupID = cloudGroupDocumentID(for: groupID)
        let normalizedName = normalizedChatDisplayName(displayName)

        Task { [weak self] in
            do {
                try await repository.setPresence(
                    groupID: cloudGroupID,
                    displayName: normalizedName,
                    isOnline: isOnline
                )
            } catch {
                await MainActor.run {
                    self?.chatPresenceSyncErrorsByGroupID[groupID] = error.localizedDescription
                }
            }
        }
    }

    /// 離開聊天室時移除監聽並盡力寫入離線狀態。
    func stopChatSync(groupID: UUID, displayName: String) {
        chatMessageListeners.removeValue(forKey: groupID)?.remove()
        chatPresenceListeners.removeValue(forKey: groupID)?.remove()
        chatReadListeners.removeValue(forKey: groupID)?.remove()
        chatPinListeners.removeValue(forKey: groupID)?.remove()
        chatHeartbeatTasks.removeValue(forKey: groupID)?.cancel()
        onlineMembersByGroupID[groupID] = []
        updateChatPresence(groupID: groupID, displayName: displayName, isOnline: false)
    }

    func onlineMembers(for groupID: UUID) -> [ChatPresence] {
        onlineMembersByGroupID[groupID] ?? []
    }

    func chatMessageSyncError(for groupID: UUID) -> String? {
        chatMessageSyncErrorsByGroupID[groupID]
    }

    func chatPresenceSyncError(for groupID: UUID) -> String? {
        chatPresenceSyncErrorsByGroupID[groupID]
    }

    func isChatMessageSyncReady(for groupID: UUID) -> Bool {
        chatMessageSyncReadyGroupIDs.contains(groupID)
    }

    func markLatestChatMessageRead(groupID: UUID) {
        guard !isDemoMode, let repository = chatRepository,
              let messageID = cloudChatMessageIDsByGroupID[groupID]?.last,
              lastMarkedChatMessageIDByGroupID[groupID] != messageID else { return }
        lastMarkedChatMessageIDByGroupID[groupID] = messageID
        Task {
            do {
                try await repository.markRead(
                    groupID: cloudGroupDocumentID(for: groupID), messageID: messageID
                )
                chatReadSyncErrorsByGroupID[groupID] = nil
            } catch {
                lastMarkedChatMessageIDByGroupID[groupID] = nil
                chatReadSyncErrorsByGroupID[groupID] = error.localizedDescription
            }
        }
    }

    func readCount(for messageID: String, in groupID: UUID) -> Int {
        guard let IDs = cloudChatMessageIDsByGroupID[groupID],
              let messageIndex = IDs.firstIndex(of: messageID),
              let group = groups.first(where: { $0.id == groupID }) else { return 0 }
        let activeMemberUIDs = Set(members.filter { group.memberIDs.contains($0.id) }
            .compactMap(\.firebaseUID))
        return chatReadReceiptsByGroupID[groupID, default: []].filter { receipt in
            guard receipt.userID != firebaseUID,
                  activeMemberUIDs.contains(receipt.userID),
                  let readIndex = IDs.firstIndex(of: receipt.messageID) else { return false }
            return readIndex >= messageIndex
        }.count
    }

    func setPinnedChatMessage(_ message: ChatPinnedMessage?, groupID: UUID) {
        guard !isDemoMode else {
            pinnedChatMessageByGroupID[groupID] = message
            return
        }
        guard let repository = chatRepository else { return }
        Task {
            do {
                try await repository.setPinnedMessage(
                    groupID: cloudGroupDocumentID(for: groupID), message: message
                )
                chatPinSyncErrorsByGroupID[groupID] = nil
            } catch {
                chatPinSyncErrorsByGroupID[groupID] = error.localizedDescription
            }
        }
    }

    private func applyChatMessages(
        _ result: Result<[CloudChatMessage], Error>,
        to groupID: UUID
    ) {
        switch result {
        case let .success(messages):
            cloudChatMessageIDsByGroupID[groupID] = messages.map(\.id)
            let currentFirebaseUserID = Auth.auth().currentUser?.uid
            chatSenderIDsByGroupID[groupID] = Dictionary(
                messages.map { ($0.id, $0.senderID) }, uniquingKeysWith: { _, latest in latest }
            )
            let cloudItems = messages.compactMap { message -> ChatRoomItem? in
                switch message.kind {
                case .message:
                    return .message(
                        id: message.id,
                        sender: message.senderName,
                        text: message.text,
                        time: message.createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)),
                        isCurrentUser: message.senderID == currentFirebaseUserID,
                        createdAt: message.createdAt,
                        deliveryState: .sent
                    )
                case .botReply:
                    return .botReply(
                        id: message.id,
                        text: message.text,
                        createdAt: message.createdAt
                    )
                case .agendaReminder:
                    guard let summary = message.agendaSummary else {
                        return .systemEvent(id: message.id, icon: "list.bullet.rectangle", text: message.text, createdAt: message.createdAt)
                    }
                    return .agendaReminder(id: message.id, summary: summary, createdAt: message.createdAt)
                case .botAnalysis:
                    guard let score = message.analysisScore,
                          let strength = message.analysisStrength,
                          let suggestion = message.analysisSuggestion,
                          let analysisID = UUID(uuidString: message.id) else { return nil }
                    return .botAnalysis(
                        id: message.id,
                        analysis: CommunicationAnalysis(
                            id: analysisID,
                            groupID: groupID,
                            score: score,
                            summary: message.text,
                            strength: strength,
                            suggestion: suggestion,
                            updatedAt: message.createdAt,
                            taskCompletionScore: message.taskCompletionScore,
                            discussionScore: message.discussionScore,
                            collaborationScore: message.collaborationScore,
                            problemSolvingScore: message.problemSolvingScore,
                            reliabilityScore: message.reliabilityScore
                        )
                    )
                }
            }

            var itemsByID = Dictionary(
                uniqueKeysWithValues: chatItemsByGroupID[groupID, default: []]
                    .filter { item in
                        guard case .message = item else { return true }
                        return item.deliveryState != .sent
                    }
                    .map { ($0.id, $0) }
            )
            for item in cloudItems {
                itemsByID[item.id] = item
            }
            let mergedItems = itemsByID.values.sorted {
                $0.createdAt < $1.createdAt
            }
            chatItemsByGroupID[groupID] = mergedItems
            if let latestAnalysis = mergedItems.compactMap(\.communicationAnalysis)
                .max(by: { $0.updatedAt < $1.updatedAt }) {
                communicationAnalyses[groupID] = latestAnalysis
            }
            chatMessageSyncErrorsByGroupID[groupID] = nil
            chatMessageSyncReadyGroupIDs.insert(groupID)
            saveChatItems()
        case let .failure(error):
            chatMessageSyncReadyGroupIDs.remove(groupID)
            chatMessageSyncErrorsByGroupID[groupID] = error.localizedDescription
        }
    }

    private func applyChatPresence(
        _ result: Result<[ChatPresence], Error>,
        to groupID: UUID
    ) {
        switch result {
        case let .success(presences):
            let activeAfter = Date.now.addingTimeInterval(-75)
            onlineMembersByGroupID[groupID] = presences
                .filter { $0.isOnline && $0.lastSeenAt >= activeAfter }
                .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            chatPresenceSyncErrorsByGroupID[groupID] = nil
        case let .failure(error):
            chatPresenceSyncErrorsByGroupID[groupID] = error.localizedDescription
        }
    }

    private func startChatHeartbeat(
        groupID: UUID,
        cloudGroupID: String,
        displayName: String,
        repository: ChatRepository
    ) {
        guard chatHeartbeatTasks[groupID] == nil else { return }
        chatHeartbeatTasks[groupID] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    try Task.checkCancellation()
                    try await repository.setPresence(
                        groupID: cloudGroupID,
                        displayName: displayName,
                        isOnline: true
                    )
                    self?.chatPresenceSyncErrorsByGroupID[groupID] = nil
                } catch is CancellationError {
                    return
                } catch {
                    self?.chatPresenceSyncErrorsByGroupID[groupID] = error.localizedDescription
                }
            }
        }
    }

    func normalizedChatDisplayName(_ displayName: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return Auth.auth().currentUser?.email?.split(separator: "@").first.map(String.init) ?? L10n.text("群組成員")
    }
}
