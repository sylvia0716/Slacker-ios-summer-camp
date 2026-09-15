import Foundation
import Observation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

/// 舊版任務看板暫時使用的任務型別。
/// 新畫面請改用 Models/ProjectTask.swift；保留此型別是為了不破壞既有 demo。
struct MissionTask: Identifiable {
    /// 任務唯一識別碼。
    let id = UUID()
    /// 舊看板顯示的任務名稱。
    var title: String
    /// 舊看板顯示的任務說明。
    var detail: String
    /// 舊看板的遊戲化經驗值。
    var points: Int
    /// 舊看板使用的負責人名稱；新功能請改用 ownerMemberID。
    var owner: String?
}

/// 舊版特工畫面暫時使用的成員型別。
/// 新畫面請改用 Models/Member.swift；保留此型別是為了不破壞既有 demo。
struct Agent: Identifiable {
    /// 特工唯一識別碼，舊催進度功能會使用它。
    let id = UUID()
    /// 特工顯示名稱。
    var name: String
    /// 特工顯示角色。
    var role: String
    /// 舊畫面使用的進度百分比；新功能應由子任務自動計算。
    var progress: Int
    /// 是否啟動「我在做了」護盾。
    var isShielded = false
    /// 顯示在特工卡上的目前狀態。
    var status = "待命"
}

/// 互評雷達圖中的單一評分指標。
struct RadarMetric: Identifiable {
    /// 指標唯一識別碼。
    let id = UUID()
    /// 指標名稱，例如準時、品質、溝通。
    let title: String
    /// 0 到 1 的評分，供雷達圖繪製。
    let score: Double
}

/// 催進度時可選擇的提醒方式。
enum PokeStyle: String, CaseIterable, Identifiable {
    case gentle = "輕敲"
    case meme = "迷因轟炸"
    case alarm = "警報催命"

    /// 給 SwiftUI ForEach 使用的穩定識別值。
    var id: Self { self }

    /// 顯示在催進度按鈕上的 SF Symbol。
    var icon: String {
        switch self {
        case .gentle: "hand.tap.fill"
        case .meme: "face.smiling.inverse"
        case .alarm: "alarm.waves.left.and.right.fill"
        }
    }

    /// 顯示在催進度 sheet 的趣味文案。
    var message: String {
        switch self {
        case .gentle: "特工，進度還活著嗎？"
        case .meme: "你的進度比校車還難等。"
        case .alarm: "紅色警戒！死線正在接近！"
        }
    }
}

/// 發布正式任務時可能發生的資料驗證錯誤。
enum PublishTaskError: LocalizedError {
    case groupNotFound
    case emptyTitle
    case assigneeNotInGroup
    case deadlineNotInFuture
    case deadlineAfterGroupDeadline

    var errorDescription: String? {
        switch self {
        case .groupNotFound: "找不到目前群組"
        case .emptyTitle: "請輸入任務名稱"
        case .assigneeNotInGroup: "負責人必須是目前群組成員"
        case .deadlineNotInFuture: "截止時間必須晚於目前時間"
        case .deadlineAfterGroupDeadline: "截止時間不可晚於群組總截止時間"
        }
    }
}

/// 修改群組期限時可能發生的資料驗證錯誤。
enum GroupDeadlineError: LocalizedError {
    case deadlineNotInFuture
    case beforeTaskDeadline

    var errorDescription: String? {
        switch self {
        case .deadlineNotInFuture:
            "群組期限必須晚於目前時間"
        case .beforeTaskDeadline:
            "群組期限不可早於既有任務的截止時間"
        }
    }
}

/// 修改群組名稱時可能發生的資料驗證錯誤。
enum GroupNameError: LocalizedError {
    case emptyName
    case groupNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "群組名稱不可為空白"
        case .groupNotFound:
            "找不到目前群組"
        }
    }
}

enum AppDataMode {
    case live
    case demo
}

/// 全 App 的唯一資料來源。
/// 所有畫面只透過這個 Store 讀取與修改資料，不在 View 內建立第二份任務或成員資料。
@MainActor @Observable
final class AppStore {
    /// 聊天記錄在本機 UserDefaults 中使用的儲存鍵。
    private static let savedChatItemsKey = "savedChatItemsByInviteCode"

    /// 各任務只保留一個 Firestore 即時監聽，讓群組頁與我的任務共用同一份成果。
    @ObservationIgnored private var attachmentListeners: [UUID: ListenerRegistration] = [:]
    @ObservationIgnored private var attachmentRepository: AttachmentRepository?
    @ObservationIgnored private var groupRepository: GroupRepository?
    @ObservationIgnored private var cloudLoadTask: Task<Void, Never>?
    @ObservationIgnored private var cloudGeneration = UUID()
    @ObservationIgnored private var syncIsActive = false
    private(set) var firebaseUID: String?
    private(set) var isLoadingCloudGroups = false
    var cloudErrorMessage: String?
    private(set) var attachmentsByTaskID: [UUID: [TaskAttachment]] = [:]
    private(set) var attachmentErrors: [UUID: String] = [:]

    /// 每個群組只保留一組聊天室與在線狀態監聽。
    @ObservationIgnored private var chatMessageListeners: [UUID: ListenerRegistration] = [:]
    @ObservationIgnored private var chatPresenceListeners: [UUID: ListenerRegistration] = [:]
    @ObservationIgnored private var chatHeartbeatTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var chatRepository: ChatRepository?

    /// 舊版聊天室啟動時自動建立的示範訊息 ID；載入時只移除這些內容。
    private static let legacyMockChatItemIDs: Set<String> = [
        "joined", "xiaoyu-update", "me-reply", "progress", "mimi-help"
    ]

    /// 目前登入使用者的成員 ID；「我的任務」用它篩選任務。
    private(set) var currentUserID: UUID

    /// 目前登入使用者的顯示名稱；舊版任務看板仍會使用。
    private(set) var userName: String

    /// 設定頁顯示並可由個人資料頁修改的公開資料。
    var profileName: String
    var profileRole: String
    var profileBio: String
    var profileAvatarSymbol = "person.fill"
    var profileAvatarData: Data?

    /// 本機原型的通知開關。
    var notificationsEnabled = true

    /// 目前原型以本機通知模擬送往被戳隊員裝置的推播。
    private let pokeNotifications = PokeNotificationService()

    /// 每位被戳隊員在個別群組中的累積次數；正式版會由後端維護。
    private var pokeCounts: [PokeCountKey: Int] = [:]

    /// 所有已加入的群組，群組列表直接讀取這個陣列。
    var groups: [Group] = [] {
        didSet { publishWidgetSnapshot() }
    }

    /// 所有成員；以 Group.memberIDs 決定某群組要顯示哪些人。
    var members: [Member] = []

    /// 所有正式任務；任務與群組、負責人的關係都用 ID 連結。
    var projectTasks: [ProjectTask] = [] {
        didSet { publishWidgetSnapshot() }
    }

    /// 截止後送出的匿名隊員互評；MVP 僅保留於目前 App 執行期間。
    var peerReviews: [PeerReview] = []

    /// 舊版任務看板資料；等 C 完成新群組詳細頁後再移除。
    var tasks: [MissionTask] = []

    /// 舊版特工頁資料；等 C 完成新版成員進度卡後再移除。
    var agents: [Agent] = []

    /// 互評雷達圖的 mock 資料。
    var radar: [RadarMetric]

    /// 聊天室 AI 機器人的溝通評分；key 是群組 ID，設定頁與聊天室共用同一份結果。
    var communicationAnalyses: [UUID: CommunicationAnalysis] = [:]

    /// 每個群組的完整聊天時間軸；離開聊天室再進入時仍會讀取同一份記錄。
    var chatItemsByGroupID: [UUID: [ChatRoomItem]] = [:]

    /// 各群組目前仍有有效心跳的在線帳號。
    var onlineMembersByGroupID: [UUID: [ChatPresence]] = [:]

    /// 訊息時間軸與在線狀態分開保存錯誤，避免其中一項成功誤清除另一項錯誤。
    var chatMessageSyncErrorsByGroupID: [UUID: String] = [:]
    var chatPresenceSyncErrorsByGroupID: [UUID: String] = [:]
    var chatMessageSyncReadyGroupIDs: Set<UUID> = []

    /// 顯示在舊版畫面上的最新系統事件文字。
    var lastEvent = ""

    private(set) var dataMode: AppDataMode

    var isDemoMode: Bool { dataMode == .demo }

    init(dataMode: AppDataMode = .live) {
        currentUserID = UUID()
        userName = "我"
        profileName = ""
        profileRole = ""
        profileBio = ""
        groups = []
        members = []
        projectTasks = []
        peerReviews = []
        tasks = []
        agents = []
        radar = []
        communicationAnalyses = [:]
        lastEvent = ""
        self.dataMode = .live

        pokeNotifications.requestAuthorization()

        if dataMode == .demo {
            setDemoMode(true)
        } else {
            publishWidgetSnapshot()
        }
    }

    /// Debug 測試模式只替換 AppStore 的資料，不會把示範資料寫進 Firestore。
    func setDemoMode(_ isEnabled: Bool) {
        guard isEnabled != isDemoMode else { return }

        suspendCloudSync()

        if isEnabled {
            let demo = DemoData.make()
            currentUserID = demo.currentUserID
            userName = demo.userName
            profileName = demo.profileName
            profileRole = demo.profileRole
            profileBio = demo.profileBio
            profileAvatarSymbol = demo.profileAvatarSymbol
            profileAvatarData = nil
            groups = demo.groups
            members = demo.members
            projectTasks = demo.projectTasks
            peerReviews = demo.peerReviews
            tasks = demo.tasks
            agents = demo.agents
            radar = demo.radar
            communicationAnalyses = [:]
            lastEvent = "測試資料已載入"
            dataMode = .demo

            let savedChatItems = Self.loadSavedChatItems()
            chatItemsByGroupID = Dictionary(
                uniqueKeysWithValues: groups.map { group in
                    (group.id, savedChatItems[group.inviteCode] ?? [])
                }
            )
            for (groupID, items) in chatItemsByGroupID {
                if let analysis = items.compactMap(\.communicationAnalysis).last {
                    communicationAnalyses[groupID] = analysis
                }
            }
        } else {
            currentUserID = firebaseUID.map(FirebaseMemberIdentity.uiID(for:))
                ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            userName = ""
            profileName = ""
            profileRole = ""
            profileBio = ""
            profileAvatarSymbol = "person.fill"
            profileAvatarData = nil
            groups = []
            members = []
            projectTasks = []
            peerReviews = []
            tasks = []
            agents = []
            radar = []
            communicationAnalyses = [:]
            chatItemsByGroupID = [:]
            lastEvent = ""
            dataMode = .live
        }

        publishWidgetSnapshot()
        if !isEnabled {
            resumeCloudSync()
        }
    }

    private func stopAttachmentListeners() {
        attachmentListeners.values.forEach { $0.remove() }
        attachmentListeners.removeAll()
    }

    /// 舊任務看板中「我已認領幾項任務」的數值。
    var claimedCount: Int { tasks.filter { $0.owner == userName }.count }

    /// 舊特工頁的平均進度；新版畫面請使用 projectProgress(for:)。
    var teamProgress: Int { agents.map(\.progress).reduce(0, +) / max(agents.count, 1) }

    /// 取得最近更新的一份溝通分析，供設定頁的 AI 報告顯示。
    var latestCommunicationAnalysis: CommunicationAnalysis? {
        communicationAnalyses.values.max(by: { $0.updatedAt < $1.updatedAt })
    }

    /// 取得指定群組目前保存的完整聊天內容。
    func chatItems(for groupID: UUID) -> [ChatRoomItem] {
        chatItemsByGroupID[groupID] ?? []
    }

    /// 將新訊息、系統事件或機器人回覆加入指定群組的聊天記錄。
    func appendChatItem(_ item: ChatRoomItem, to groupID: UUID) {
        chatItemsByGroupID[groupID, default: []].append(item)
        saveChatItems()
    }

    /// 進入聊天室後建立 Firebase 成員身分並開始監聽訊息與在線狀態。
    func startChatSync(groupID: UUID, displayName: String) async {
        chatMessageSyncReadyGroupIDs.remove(groupID)
        guard FirebaseApp.app() != nil else {
            let message = "Firebase 尚未設定完成。"
            chatMessageSyncErrorsByGroupID[groupID] = message
            chatPresenceSyncErrorsByGroupID[groupID] = message
            return
        }

        let repository = chatRepository ?? ChatRepository()
        chatRepository = repository
        let cloudGroupID = groupID.uuidString.lowercased()
        let normalizedName = normalizedChatDisplayName(displayName)

        do {
            try await repository.ensureMembership(
                groupID: cloudGroupID,
                displayName: normalizedName
            )
        } catch {
            chatMessageSyncErrorsByGroupID[groupID] = error.localizedDescription
            chatPresenceSyncErrorsByGroupID[groupID] = error.localizedDescription
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
        guard let repository = chatRepository else { return false }

        do {
            try await repository.sendMessage(
                id: id,
                groupID: groupID.uuidString.lowercased(),
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
        guard let repository = chatRepository else {
            chatMessageSyncErrorsByGroupID[groupID] = "聊天室尚未連線，AI 回覆尚未同步。"
            return false
        }

        do {
            try await repository.sendBotReply(
                id: id,
                groupID: groupID.uuidString.lowercased(),
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
        guard let repository = chatRepository else {
            chatMessageSyncErrorsByGroupID[groupID] = "聊天室尚未連線，AI 分析尚未同步。"
            return false
        }

        do {
            try await repository.sendBotAnalysis(
                id: id,
                groupID: groupID.uuidString.lowercased(),
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
        guard let repository = chatRepository else { return }
        let cloudGroupID = groupID.uuidString.lowercased()
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

    private func applyChatMessages(
        _ result: Result<[CloudChatMessage], Error>,
        to groupID: UUID
    ) {
        switch result {
        case let .success(messages):
            let currentFirebaseUserID = Auth.auth().currentUser?.uid
            let cloudItems = messages.compactMap { message -> ChatRoomItem? in
                switch message.kind {
                case .message:
                    return .message(
                        id: message.id,
                        sender: message.senderName,
                        text: message.text,
                        time: message.createdAt.formatted(date: .omitted, time: .shortened),
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
                            updatedAt: message.createdAt
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

    private func normalizedChatDisplayName(_ displayName: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return Auth.auth().currentUser?.email?.split(separator: "@").first.map(String.init) ?? "群組成員"
    }

    /// 保存 Apple Intelligence 產生的溝通分析，供聊天室與設定頁共用。
    @discardableResult
    func saveCommunicationAnalysis(
        groupID: UUID,
        generated: GeneratedCommunicationAnalysis,
        now: Date = .now
    ) -> CommunicationAnalysis {
        let analysis = CommunicationAnalysis(
            id: UUID(),
            groupID: groupID,
            score: generated.score,
            summary: generated.summary,
            strength: generated.strength,
            suggestion: generated.suggestion,
            updatedAt: now
        )
        communicationAnalyses[groupID] = analysis
        lastEvent = "AI 已完成團隊溝通分析：\(generated.score) 分"
        return analysis
    }

    /// 取得指定群組內某位成員負責的正式任務。
    func tasks(for memberID: UUID, in groupID: UUID) -> [ProjectTask] {
        projectTasks.filter { $0.groupID == groupID && $0.ownerMemberID == memberID }
    }

    /// 依子任務完成狀態計算群組總進度，不要在 View 手動設定百分比。
    func projectProgress(for groupID: UUID) -> Int {
        let tasks = projectTasks.filter { $0.groupID == groupID }
        let totalWeight = tasks.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        return tasks.reduce(0) { $0 + $1.progress * $1.weight } / totalWeight
    }

    /// Writes the nearest group deadline and calculated project progress for the widget.
    private func publishWidgetSnapshot() {
        let group = groups.min(by: { $0.deadline < $1.deadline })
        let snapshot = group.map {
            WidgetProgressSnapshot(
                groupName: $0.name,
                progress: projectProgress(for: $0.id),
                deadline: $0.deadline
            )
        }
        WidgetSnapshotStore.save(snapshot)
    }

    /// 依該成員負責任務的子任務完成狀態計算個人進度。
    func memberProgress(for memberID: UUID, in groupID: UUID) -> Int {
        let tasks = tasks(for: memberID, in: groupID)
        let totalWeight = tasks.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        return tasks.reduce(0) { $0 + $1.progress * $1.weight } / totalWeight
    }

    /// 取得指定群組已送出的匿名互評。
    func reviews(for groupID: UUID) -> [PeerReview] {
        peerReviews.filter { $0.groupID == groupID }
    }

    /// 同一位評價者對同一位隊員只能送出一次。
    func hasReviewed(reviewerID: UUID, revieweeID: UUID, groupID: UUID) -> Bool {
        peerReviews.contains {
            $0.groupID == groupID
                && $0.reviewerMemberID == reviewerID
                && $0.revieweeMemberID == revieweeID
        }
    }

    /// 判斷一位成員是否已完成對群組內所有其他成員的互評。
    func hasCompletedAllReviews(reviewerID: UUID, groupID: UUID) -> Bool {
        guard let group = groups.first(where: { $0.id == groupID }),
              group.memberIDs.contains(reviewerID) else { return false }

        return group.memberIDs
            .filter { $0 != reviewerID }
            .allSatisfy { hasReviewed(reviewerID: reviewerID, revieweeID: $0, groupID: groupID) }
    }

    /// 群組內已完成全部互評的成員人數。
    func completedPeerReviewerCount(in groupID: UUID) -> Int {
        guard let group = groups.first(where: { $0.id == groupID }) else { return 0 }
        return group.memberIDs.filter {
            hasCompletedAllReviews(reviewerID: $0, groupID: groupID)
        }.count
    }

    /// 驗證並送出匿名隊員互評。評價內容不對外暴露 reviewer 身份。
    @discardableResult
    func submitPeerReview(
        groupID: UUID,
        reviewerID: UUID,
        revieweeID: UUID,
        taskCompletionScore: Int,
        discussionScore: Int,
        collaborationScore: Int,
        ideaScore: Int,
        reliabilityScore: Int,
        comment: String,
        now: Date = .now
    ) throws -> PeerReview {
        guard let group = groups.first(where: { $0.id == groupID }) else {
            throw PeerReviewSubmissionError.groupNotFound
        }
        guard now >= group.deadline else {
            throw PeerReviewSubmissionError.groupStillActive
        }
        guard group.memberIDs.contains(reviewerID), group.memberIDs.contains(revieweeID) else {
            throw PeerReviewSubmissionError.memberNotInGroup
        }
        guard reviewerID != revieweeID else {
            throw PeerReviewSubmissionError.cannotReviewSelf
        }

        let scores = [
            taskCompletionScore,
            discussionScore,
            collaborationScore,
            ideaScore,
            reliabilityScore
        ]
        guard scores.allSatisfy({ (1...5).contains($0) }) else {
            throw PeerReviewSubmissionError.invalidScore
        }
        guard !hasReviewed(reviewerID: reviewerID, revieweeID: revieweeID, groupID: groupID) else {
            throw PeerReviewSubmissionError.duplicateReview
        }

        let review = PeerReview(
            id: UUID(),
            groupID: groupID,
            reviewerMemberID: reviewerID,
            revieweeMemberID: revieweeID,
            taskCompletionScore: taskCompletionScore,
            discussionScore: discussionScore,
            collaborationScore: collaborationScore,
            ideaScore: ideaScore,
            reliabilityScore: reliabilityScore,
            comment: String(comment.prefix(200)),
            submittedAt: now
        )
        peerReviews.append(review)
        lastEvent = "已送出匿名隊員互評"
        return review
    }

#if DEBUG
    /// 清除指定群組互評，僅供截止後互評流程的 DEBUG 測試選單使用。
    func resetPeerReviews(for groupID: UUID) {
        peerReviews.removeAll { $0.groupID == groupID }
    }
#endif

    /// 驗證並發布一項正式任務，同步維護群組的 taskIDs 關係。
    @discardableResult
    func publishTask(
        title: String,
        detail: String,
        groupID: UUID,
        assigneeMemberID: UUID,
        deadline: Date,
        now: Date = .now
    ) throws -> ProjectTask {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw PublishTaskError.emptyTitle }
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw PublishTaskError.groupNotFound
        }
        guard groups[groupIndex].memberIDs.contains(assigneeMemberID),
              members.contains(where: { $0.id == assigneeMemberID }) else {
            throw PublishTaskError.assigneeNotInGroup
        }
        guard deadline > now else { throw PublishTaskError.deadlineNotInFuture }
        guard deadline <= groups[groupIndex].deadline else {
            throw PublishTaskError.deadlineAfterGroupDeadline
        }

        let task = ProjectTask(
            id: UUID(),
            groupID: groupID,
            title: trimmedTitle,
            detail: trimmedDetail,
            weight: 1,
            ownerMemberID: assigneeMemberID,
            subtasks: [Subtask(id: UUID(), title: trimmedTitle, isComplete: false, weight: 100)],
            deliverable: nil,
            deadline: deadline,
            createdByMemberID: currentUserID,
            createdAt: now,
            status: .pending
        )

        projectTasks.append(task)
        groups[groupIndex].taskIDs.append(task.id)
        lastEvent = "已發布新任務「\(trimmedTitle)」"
        return task
    }

    /// 建立一個只有目前使用者的新群組，供建立群組 sheet 呼叫。
    func createGroup(name: String, deadline: Date) {
        let group = Group(id: UUID(), name: name, deadline: deadline, memberIDs: [currentUserID], taskIDs: [], inviteCode: String(UUID().uuidString.prefix(6)).uppercased())
        groups.append(group)
        chatItemsByGroupID[group.id] = [
            .systemEvent(
                id: UUID().uuidString,
                icon: "person.2.fill",
                text: "群組聊天室已建立",
                createdAt: .now
            )
        ]
        saveChatItems()
        lastEvent = "已建立「\(name)」"
    }

    /// 修改群組總截止時間；任務發布會以更新後的期限驗證。
    @discardableResult
    func updateGroupDeadline(groupID: UUID, deadline: Date, now: Date = .now) throws -> Group {
        guard deadline > now else { throw GroupDeadlineError.deadlineNotInFuture }
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            throw PublishTaskError.groupNotFound
        }
        let taskDeadlines = projectTasks
            .filter { $0.groupID == groupID }
            .map(\.deadline)
        guard taskDeadlines.allSatisfy({ $0 <= deadline }) else {
            throw GroupDeadlineError.beforeTaskDeadline
        }

        groups[index].deadline = deadline
        lastEvent = "已更新「\(groups[index].name)」期限"
        return groups[index]
    }

    /// 修改群組名稱。
    @discardableResult
    func updateGroupName(groupID: UUID, name: String) throws -> Group {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw GroupNameError.emptyName }
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            throw GroupNameError.groupNotFound
        }

        groups[index].name = trimmedName
        lastEvent = "已更新群組名稱"
        return groups[index]
    }

    /// 將 Callable Function 回傳的可存取群組合併進既有單一資料來源。
    func mergeAccessibleCloudGroups(_ cloudGroups: [CloudGroupSummary]) {
        for cloudGroup in cloudGroups {
            if let index = groups.firstIndex(where: { $0.id == cloudGroup.id }) {
                groups[index].name = cloudGroup.name
                groups[index].deadline = cloudGroup.deadline
                if !cloudGroup.inviteCode.isEmpty {
                    groups[index].inviteCode = cloudGroup.inviteCode
                }
            } else {
                groups.append(Group(
                    id: cloudGroup.id,
                    name: cloudGroup.name,
                    deadline: cloudGroup.deadline,
                    memberIDs: [],
                    taskIDs: [],
                    inviteCode: cloudGroup.inviteCode,
                    firestoreDocumentID: cloudGroup.pathID
                ))
            }
        }
    }

    /// Called synchronously before AuthSession publishes a different UID.
    func changeCloudAccount(to uid: String?) {
        guard uid != firebaseUID else { return }
        suspendCloudSync()
        groups = []
        projectTasks = []
        members = []
        peerReviews = []
        tasks = []
        agents = []
        radar = []
        chatItemsByGroupID = [:]
        communicationAnalyses = [:]
        pokeCounts = [:]
        attachmentsByTaskID = [:]
        attachmentErrors = [:]
        cloudErrorMessage = nil
        profileName = ""
        profileBio = ""
        profileRole = ""
        profileAvatarSymbol = "person.fill"
        profileAvatarData = nil
        userName = ""
        lastEvent = ""
        firebaseUID = uid
        currentUserID = uid.map(FirebaseMemberIdentity.uiID(for:))
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        publishWidgetSnapshot()
    }

    func resumeCloudSync() {
        guard dataMode == .live, firebaseUID != nil, !syncIsActive else { return }
        syncIsActive = true
        cloudLoadTask = Task { [weak self] in _ = await self?.reloadCloudGroups() }
    }

    func suspendCloudSync() {
        syncIsActive = false
        cloudGeneration = UUID()
        cloudLoadTask?.cancel()
        cloudLoadTask = nil
        stopAttachmentSync()
        attachmentsByTaskID = [:]
        attachmentErrors = [:]
        for index in projectTasks.indices where projectTasks[index].firestoreDocumentID != nil {
            projectTasks[index].deliverable = nil
        }
        isLoadingCloudGroups = false
    }

    private func stopAttachmentSync() {
        attachmentListeners.values.forEach { $0.remove() }
        attachmentListeners.removeAll()
    }

    @discardableResult
    func reloadCloudGroups(reportError: Bool = true) async -> Bool {
        guard dataMode == .live,
              let uid = firebaseUID,
              syncIsActive,
              FirebaseApp.app() != nil else { return false }
        let generation = UUID()
        cloudGeneration = generation
        stopAttachmentSync()
        isLoadingCloudGroups = true
        defer { if cloudGeneration == generation { isLoadingCloudGroups = false } }
        do {
            let repository = groupRepository ?? GroupRepository.firebase()
            groupRepository = repository
            let loaded = try await repository.load()
            guard !Task.isCancelled, firebaseUID == uid, cloudGeneration == generation, syncIsActive else { return false }
            // Replace, never append stale account/group/task rows.
            projectTasks = loaded.flatMap(\.tasks)
            groups = loaded.map(\.group)
            var byID: [UUID: Member] = [:]
            for member in loaded.flatMap(\.members) { byID[member.id] = member }
            members = byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
            userName = byID[currentUserID]?.name ?? ""
            let taskIDs = Set(projectTasks.map(\.id))
            attachmentsByTaskID = attachmentsByTaskID.filter { taskIDs.contains($0.key) }
            attachmentErrors = [:]
            cloudErrorMessage = nil
            // Tasks now exist in the single source of truth; only now attach listeners.
            startAttachmentSync(for: projectTasks.map(\.id))
            return true
        } catch {
            guard !Task.isCancelled, firebaseUID == uid, cloudGeneration == generation else { return false }
            // Invalidate task/attachment cache on a failed authoritative refresh.
            // Joined summaries remain visible so success is never presented as failure.
            projectTasks = []
            members = []
            attachmentsByTaskID = [:]
            attachmentErrors = [:]
            for index in groups.indices {
                groups[index].taskIDs = []
                groups[index].memberIDs = []
                groups[index].memberRoles = [:]
            }
            if reportError { cloudErrorMessage = Self.cloudMessage(error) }
            return false
        }
    }

    func acceptJoinedGroup(_ result: GroupJoinResult) -> Bool {
        guard firebaseUID == result.firebaseUID else { return false }
        cloudErrorMessage = nil
        mergeAccessibleCloudGroups([result.group])
        lastEvent = result.wasAlreadyMember
            ? "你已經是「\(result.group.name)」的成員"
            : "已加入「\(result.group.name)」"
        return true
    }

    private static func cloudMessage(_ error: Error) -> String {
        if let error = error as? GroupLoadError { return error.localizedDescription }
        if let error = error as? GroupJoinError { return error.localizedDescription }
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return GroupLoadError.permissionDenied.localizedDescription
        }
        if error is DecodingError { return GroupLoadError.invalidData.localizedDescription }
        return "雲端資料同步失敗，請確認網路後重新整理。"
    }

#if DEBUG
    /// 僅供 Debug 原型資料使用；正式邀請碼加入流程由 Callable Function 處理。
    @discardableResult
    func joinGroup(inviteCode: String) -> Bool {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return false }
        guard let index = groups.firstIndex(where: { $0.inviteCode == code }) else { return false }
        if !groups[index].memberIDs.contains(currentUserID) {
            groups[index].memberIDs.append(currentUserID)
        }
        lastEvent = "已加入「\(groups[index].name)」"
        return true
    }
#endif

    /// 離開目前使用者已加入的群組；群組列表只保留目前使用者仍加入的群組。
    @discardableResult
    func leaveGroup(groupID: UUID) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].memberIDs.contains(currentUserID) else { return false }

        let groupName = groups[index].name
        groups.remove(at: index)
        chatItemsByGroupID[groupID] = nil
        saveChatItems()
        lastEvent = "已離開「\(groupName)」"
        return true
    }

    /// 從本機載入各邀請碼所屬的聊天記錄；資料損毀時安全地回到預設內容。
    private static func loadSavedChatItems() -> [String: [ChatRoomItem]] {
        guard let data = UserDefaults.standard.data(forKey: savedChatItemsKey),
              let items = try? JSONDecoder().decode([String: [ChatRoomItem]].self, from: data) else {
            return [:]
        }
        return items.mapValues { chatItems in
            chatItems
                .filter { !legacyMockChatItemIDs.contains($0.id) }
                .map(\.restoringInterruptedDelivery)
        }
    }

    /// 以不會隨 App 重啟改變的群組邀請碼作為索引，保存完整聊天室時間軸。
    private func saveChatItems() {
        let itemsByInviteCode = Dictionary(
            uniqueKeysWithValues: groups.compactMap { group -> (String, [ChatRoomItem])? in
                guard let items = chatItemsByGroupID[group.id] else { return nil }
                return (group.inviteCode, items)
            }
        )

        guard let data = try? JSONEncoder().encode(itemsByInviteCode) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedChatItemsKey)
    }

    /// 切換子任務完成狀態；完成後所有依 progress 計算的畫面會自動更新。
    func toggleSubtask(taskID: UUID, subtaskID: UUID) {
        guard let taskIndex = projectTasks.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = projectTasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        projectTasks[taskIndex].subtasks[subtaskIndex].isComplete.toggle()
        lastEvent = "已更新「\(projectTasks[taskIndex].title)」進度"
    }

    /// 為任務送出成果；畫面傳入的 Deliverable 可來自 mock 檔案或連結。
    func submitDeliverable(taskID: UUID, deliverable: Deliverable) {
        guard let index = projectTasks.firstIndex(where: { $0.id == taskID }) else { return }
        projectTasks[index].deliverable = deliverable
        lastEvent = "已送出「\(projectTasks[index].title)」成果"
    }

    /// 啟動指定任務的附件監聽；重複進入畫面不會重複註冊 listener。
    func startAttachmentSync(for taskID: UUID) {
        guard dataMode == .live,
              attachmentListeners[taskID] == nil,
              syncIsActive, let uid = firebaseUID,
              FirebaseApp.app() != nil,
              let task = projectTasks.first(where: { $0.id == taskID }),
              let path = task.firestoreDocumentID,
              let groupPath = groups.first(where: { $0.id == task.groupID })?.firestoreDocumentID else { return }
        let generation = cloudGeneration

        let repository = attachmentRepository ?? AttachmentRepository()
        attachmentRepository = repository
        attachmentListeners[taskID] = repository.listen(
            groupID: groupPath,
            taskID: path
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.firebaseUID == uid, self.cloudGeneration == generation,
                      self.syncIsActive else { return }
                switch result {
                case .success(let attachments):
                    do {
                        let collection = try CloudAttachmentCollection(attachments, groupID: groupPath, taskID: path)
                        self.attachmentErrors[taskID] = nil
                        self.applyCloudAttachments(collection.attachments, to: taskID)
                    } catch {
                        self.applyCloudAttachments([], to: taskID)
                        self.attachmentErrors[taskID] = Self.cloudMessage(error)
                        self.cloudErrorMessage = Self.cloudMessage(error)
                    }
                case .failure(let error):
                    self.applyCloudAttachments([], to: taskID)
                    let message = Self.cloudMessage(error)
                    self.attachmentErrors[taskID] = message
                    self.cloudErrorMessage = message
                }
            }
        }
    }

    private func startAttachmentSync(for taskIDs: [UUID]) {
        taskIDs.forEach(startAttachmentSync(for:))
    }

    private func applyCloudAttachments(_ attachments: [TaskAttachment], to taskID: UUID) {
        guard let taskIndex = projectTasks.firstIndex(where: { $0.id == taskID }) else { return }
        attachmentsByTaskID[taskID] = attachments
        projectTasks[taskIndex].deliverable = attachments.first(where: { $0.status == .ready }).map { Deliverable(attachment: $0) }
    }

    /// 由群組成員確認已看到任務成果；同一位成員不可重複確認。
    func confirmDeliverable(taskID: UUID, memberID: UUID) {
        guard let taskIndex = projectTasks.firstIndex(where: { $0.id == taskID }),
              let group = groups.first(where: { $0.id == projectTasks[taskIndex].groupID }),
              group.memberIDs.contains(memberID),
              var deliverable = projectTasks[taskIndex].deliverable,
              !deliverable.confirmedMemberIDs.contains(memberID) else { return }

        deliverable.confirmedMemberIDs.append(memberID)
        projectTasks[taskIndex].deliverable = deliverable
        lastEvent = "已確認「\(projectTasks[taskIndex].title)」成果進度"
    }

    /// 將已送出的成果標記為驗收通過。
    func approveDeliverable(taskID: UUID) {
        guard let index = projectTasks.firstIndex(where: { $0.id == taskID }),
              var deliverable = projectTasks[index].deliverable else { return }
        deliverable.isApproved = true
        projectTasks[index].deliverable = deliverable
        lastEvent = "已驗收「\(projectTasks[index].title)」成果"
    }

    /// 在群組內提醒進度較慢的成員，並以本機系統通知模擬送達被戳隊員。
    @discardableResult
    func poke(memberID: UUID, in groupID: UUID, style: PokeStyle) -> Int? {
        guard memberID != currentUserID,
              let group = groups.first(where: { $0.id == groupID }), group.memberIDs.contains(memberID),
              let member = members.first(where: { $0.id == memberID }),
              memberProgress(for: memberID, in: groupID) <= 90 else { return nil }
        lastEvent = "用「\(style.rawValue)」戳了 \(member.name)"

        let key = PokeCountKey(groupID: groupID, memberID: memberID)
        let pokeCount = (pokeCounts[key] ?? 0) + 1
        pokeCounts[key] = pokeCount
        if notificationsEnabled {
            pokeNotifications.deliver(group: group, pokeCount: pokeCount)
        }
        return pokeCount
    }

    /// 僅供隱藏測試頁使用，模擬目前使用者收到群組的戳一戳通知。
    @discardableResult
    func sendTestPoke(in groupID: UUID) -> Int? {
        guard notificationsEnabled,
              let group = groups.first(where: { $0.id == groupID }) else { return nil }

        let key = PokeCountKey(groupID: groupID, memberID: currentUserID)
        let pokeCount = (pokeCounts[key] ?? 0) + 1
        pokeCounts[key] = pokeCount
        pokeNotifications.deliver(group: group, pokeCount: pokeCount)
        return pokeCount
    }

    /// 舊任務看板的認領行為；等新任務畫面完成後改用 ProjectTask.ownerMemberID。
    func claim(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].owner == nil else { return }
        tasks[index].owner = userName
        lastEvent = "已認領「\(tasks[index].title)」"
    }

    /// 舊版催進度行為；新版群組詳細頁請改呼叫 poke(memberID:in:style:)。
    func poke(agentID: UUID, style: PokeStyle) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        lastEvent = "用「\(style.rawValue)」戳了 \(agents[index].name)"
    }

    /// 舊版「我在做了」護盾行為；新版可改成綁定個別 ProjectTask。
    func shield(minutes: Int, note: String) {
        guard let index = agents.firstIndex(where: { $0.name == userName }) else { return }
        agents[index].isShielded = true
        agents[index].status = "護盾 \(minutes) 分鐘｜\(note)"
        agents[index].progress = min(100, agents[index].progress + 5)
        lastEvent = "護盾啟動，隊友看得到你在做了"
    }
}

private struct PokeCountKey: Hashable {
    let groupID: UUID
    let memberID: UUID
}

/// 暫時相容舊 View 名稱；新檔案一律使用 AppStore。
typealias GroupBombModel = AppStore
