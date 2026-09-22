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
    var status = L10n.text("待命")
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
        case .gentle: L10n.text("特工，進度還活著嗎？")
        case .meme: L10n.text("你的進度比校車還難等。")
        case .alarm: L10n.text("紅色警戒！死線正在接近！")
        }
    }
}

/// 發布正式任務時可能發生的資料驗證錯誤。
enum PublishTaskError: LocalizedError {
    case groupNotFound
    case emptyTitle
    case invalidSubtasks
    case assigneeNotInGroup
    case deadlineNotInFuture
    case deadlineAfterGroupDeadline

    var errorDescription: String? {
        switch self {
        case .groupNotFound: L10n.text("找不到目前群組")
        case .emptyTitle: L10n.text("請輸入任務名稱")
        case .invalidSubtasks: L10n.text("請填寫 1 到 10 項子任務")
        case .assigneeNotInGroup: L10n.text("負責人必須是目前群組成員")
        case .deadlineNotInFuture: L10n.text("截止時間必須晚於目前時間")
        case .deadlineAfterGroupDeadline: L10n.text("截止時間不可晚於群組總截止時間")
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
            L10n.text("群組期限必須晚於目前時間")
        case .beforeTaskDeadline:
            L10n.text("群組期限不可早於既有任務的截止時間")
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
            L10n.text("群組名稱不可為空白")
        case .groupNotFound:
            L10n.text("找不到目前群組")
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
    @ObservationIgnored private var progressSubscriptions: [UUID: GroupProgressSubscription] = [:]
    private(set) var pendingTaskUpdates: Set<UUID> = []
    private(set) var pendingSubtaskUpdates: [UUID: UUID] = [:]
    private(set) var isSavingNickname = false
    @ObservationIgnored private var groupRepository: GroupRepository?
    @ObservationIgnored private var taskMutationRepository: TaskMutationRepository?
    @ObservationIgnored private var pokeRepository: PokeRepository?
    @ObservationIgnored private var pokeListeners: [UUID: ListenerRegistration] = [:]
    @ObservationIgnored private var hasLoadedReminderData = false
    @ObservationIgnored private var reminderUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var peerReviewRepository: PeerReviewRepository?
    @ObservationIgnored private var peerReviewStateListeners: [UUID: ListenerRegistration] = [:]
    @ObservationIgnored private var peerReviewSummaryListeners: [UUID: ListenerRegistration] = [:]
    @ObservationIgnored private var peerReviewCommentsListeners: [UUID: ListenerRegistration] = [:]
    @ObservationIgnored private var personalPeerReviewProjectsListener: ListenerRegistration?
    @ObservationIgnored private var peerReviewStateSyncErrorsByGroupID: [UUID: String] = [:]
    @ObservationIgnored private var peerReviewSummarySyncErrorsByGroupID: [UUID: String] = [:]
    @ObservationIgnored private var peerReviewCommentsSyncErrorsByGroupID: [UUID: String] = [:]
    private(set) var peerReviewSummariesByGroupID: [UUID: PeerReviewSummary] = [:]
    private(set) var peerReviewCommentsByGroupID: [UUID: [String]] = [:]
    private(set) var personalPeerReviewProjects: [PersonalPeerReviewProject] = []
    private(set) var personalPeerReviewSyncError: String?
    @ObservationIgnored private var progressSyncErrorsByGroupID: [UUID: String] = [:]
    @ObservationIgnored private var cloudLoadTask: Task<Void, Never>?
    @ObservationIgnored private var cloudGeneration = UUID()
    @ObservationIgnored private var syncIsActive = false
    private(set) var firebaseUID: String?
    private(set) var isLoadingCloudGroups = false
    var cloudErrorMessage: String?
    private(set) var cloudGroupSyncErrorMessage: String?
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

    /// Shared with background refresh, including launches without the settings screen.
    var notificationsEnabled = PokeDeliveryState.shared.notificationsEnabled {
        didSet {
            PokeDeliveryState.shared.notificationsEnabled = notificationsEnabled
            notificationSettingsChanged()
        }
    }

    var notificationCategories = PokeDeliveryState.shared.categories {
        didSet {
            PokeDeliveryState.shared.categories = notificationCategories
            notificationSettingsChanged()
        }
    }

    var deadlineReminderTime = PokeDeliveryState.shared.deadlineReminderTime {
        didSet {
            PokeDeliveryState.shared.deadlineReminderTime = deadlineReminderTime
            notificationSettingsChanged()
        }
    }

    var receivesPokes: Bool { notificationsEnabled && notificationCategories.pokes }

    private func notificationSettingsChanged() {
        refreshDeadlineReminders()
        if receivesPokes, dataMode == .live {
            PokeBackgroundRefresh.shared.schedule()
        } else {
            PokeBackgroundRefresh.shared.cancel()
            pokeNotifications.cancelPendingPokes()
        }
    }

    /// 目前原型以本機通知模擬送往被戳隊員裝置的推播。
    private let pokeNotifications = PokeNotificationService()

    /// 每位被戳隊員在個別群組中的累積次數；正式版會由後端維護。
    private var pokeCounts: [PokeCountKey: Int] = [:]

    /// 所有已加入的群組，群組列表直接讀取這個陣列。
    var groups: [Group] = [] {
        didSet { publishWidgetSnapshot(); refreshDeadlineReminders() }
    }

    /// 所有成員；以 Group.memberIDs 決定某群組要顯示哪些人。
    var members: [Member] = []

    /// 所有正式任務；任務與群組、負責人的關係都用 ID 連結。
    var projectTasks: [ProjectTask] = [] {
        didSet { publishWidgetSnapshot(); refreshDeadlineReminders() }
    }

    /// 截止後送出的匿名隊員互評；MVP 僅保留於目前 App 執行期間。
    var peerReviews: [PeerReview] = [] {
        didSet { refreshDeadlineReminders() }
    }

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
    private(set) var chatSenderIDsByGroupID: [UUID: [String: String]] = [:]

    /// 各群組目前仍有有效心跳的在線帳號。
    var onlineMembersByGroupID: [UUID: [ChatPresence]] = [:]

    /// 訊息時間軸與在線狀態分開保存錯誤，避免其中一項成功誤清除另一項錯誤。
    var chatMessageSyncErrorsByGroupID: [UUID: String] = [:]
    var chatPresenceSyncErrorsByGroupID: [UUID: String] = [:]
    var chatMessageSyncReadyGroupIDs: Set<UUID> = []

    /// 顯示在舊版畫面上的最新系統事件文字。
    var groupLeaveMessage: String?
    var lastEvent = ""

    private(set) var dataMode: AppDataMode

    var isDemoMode: Bool { dataMode == .demo }

    var personalReviewProjectsForReport: [PersonalPeerReviewProject] {
        guard isDemoMode else { return personalPeerReviewProjects }
        return Dictionary(grouping: peerReviews.filter { $0.revieweeMemberID == currentUserID }, by: \.groupID)
            .compactMap { groupID, reviews in
                guard let group = groups.first(where: { $0.id == groupID }), !reviews.isEmpty else { return nil }
                return PersonalPeerReviewProject(
                    groupID: groupID.uuidString,
                    groupName: group.name,
                    completedAt: group.deadline,
                    reviewCount: reviews.count,
                    acceptedReviewCount: reviews.count,
                    excludedReviewCount: 0,
                    taskCompletionScoreTotal: reviews.reduce(0) { $0 + $1.taskCompletionScore },
                    discussionScoreTotal: reviews.reduce(0) { $0 + $1.discussionScore },
                    collaborationScoreTotal: reviews.reduce(0) { $0 + $1.collaborationScore },
                    ideaScoreTotal: reviews.reduce(0) { $0 + $1.ideaScore },
                    reliabilityScoreTotal: reviews.reduce(0) { $0 + $1.reliabilityScore },
                    taskCompletionScore: Double(reviews.map(\.taskCompletionScore).sorted()[reviews.count / 2]),
                    discussionScore: Double(reviews.map(\.discussionScore).sorted()[reviews.count / 2]),
                    collaborationScore: Double(reviews.map(\.collaborationScore).sorted()[reviews.count / 2]),
                    ideaScore: Double(reviews.map(\.ideaScore).sorted()[reviews.count / 2]),
                    reliabilityScore: Double(reviews.map(\.reliabilityScore).sorted()[reviews.count / 2])
                )
            }
            .sorted { $0.completedAt > $1.completedAt }
    }

    func personalPeerReviewProject(for group: Group) -> PersonalPeerReviewProject? {
        let cloudID = group.firestoreDocumentID
        return personalReviewProjectsForReport.first { project in
            project.groupID == cloudID
                || project.groupID.caseInsensitiveCompare(group.id.uuidString) == .orderedSame
        }
    }

    init(dataMode: AppDataMode = .live) {
        currentUserID = UUID()
        userName = L10n.text("我")
        profileName = ""
        profileRole = ""
        profileBio = ""
        groups = []
        members = []
        projectTasks = []
        peerReviews = []
        peerReviewSummariesByGroupID = [:]
        peerReviewCommentsByGroupID = [:]
        personalPeerReviewProjects = []
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
        hasLoadedReminderData = false

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
            peerReviewSummariesByGroupID = [:]
            peerReviewCommentsByGroupID = [:]
            personalPeerReviewProjects = []
            tasks = demo.tasks
            agents = demo.agents
            radar = demo.radar
            communicationAnalyses = demo.communicationAnalyses
            cloudGroupSyncErrorMessage = nil
            lastEvent = L10n.text("測試資料已載入")
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
            peerReviewSummariesByGroupID = [:]
            peerReviewCommentsByGroupID = [:]
            personalPeerReviewProjects = []
            tasks = []
            agents = []
            radar = []
            communicationAnalyses = [:]
            chatItemsByGroupID = [:]
            cloudGroupSyncErrorMessage = nil
            lastEvent = ""
            dataMode = .live
        }

        publishWidgetSnapshot()
        if !isEnabled {
            resumeCloudSync()
        }
        refreshDeadlineReminders()
    }

    private func stopAttachmentListeners() {
        attachmentListeners.values.forEach { $0.remove() }
        attachmentListeners.removeAll()
    }

    private func stopPeerReviewSync() {
        peerReviewStateListeners.values.forEach { $0.remove() }
        peerReviewStateListeners.removeAll()
        peerReviewSummaryListeners.values.forEach { $0.remove() }
        peerReviewSummaryListeners.removeAll()
        peerReviewCommentsListeners.values.forEach { $0.remove() }
        peerReviewCommentsListeners.removeAll()
        personalPeerReviewProjectsListener?.remove()
        personalPeerReviewProjectsListener = nil
        peerReviewStateSyncErrorsByGroupID.removeAll()
        peerReviewSummarySyncErrorsByGroupID.removeAll()
        peerReviewCommentsSyncErrorsByGroupID.removeAll()
        personalPeerReviewSyncError = nil
    }

    /// 舊任務看板中「我已認領幾項任務」的數值。
    var claimedCount: Int { tasks.filter { $0.owner == userName }.count }

    /// 舊特工頁的平均進度；新版畫面請使用 projectProgress(for:)。
    var teamProgress: Int { agents.map(\.progress).reduce(0, +) / max(agents.count, 1) }

    /// 取得最近更新的一份溝通分析。
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
        guard dataMode == .live else {
            chatMessageSyncErrorsByGroupID[groupID] = nil
            chatPresenceSyncErrorsByGroupID[groupID] = nil
            chatMessageSyncReadyGroupIDs.insert(groupID)
            return
        }
        guard FirebaseApp.app() != nil else {
            let message = L10n.text("Firebase 尚未設定完成。")
            chatMessageSyncErrorsByGroupID[groupID] = message
            chatPresenceSyncErrorsByGroupID[groupID] = message
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

    private func normalizedChatDisplayName(_ displayName: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return Auth.auth().currentUser?.email?.split(separator: "@").first.map(String.init) ?? L10n.text("群組成員")
    }

    private func cloudGroupDocumentID(for groupID: UUID) -> String {
        groups.first(where: { $0.id == groupID })?.firestoreDocumentID
            ?? groupID.uuidString.lowercased()
    }

    /// 保存 Apple Intelligence 產生的專案分析，供聊天室與團隊戰報共用。
    @discardableResult
    func saveCommunicationAnalysis(
        groupID: UUID,
        generated: GeneratedCommunicationAnalysis,
        now: Date = .now
    ) -> CommunicationAnalysis {
        let overallScore = (
            generated.taskCompletionScore
                + generated.discussionScore
                + generated.collaborationScore
                + generated.problemSolvingScore
                + generated.reliabilityScore
        ) / 5
        let analysis = CommunicationAnalysis(
            id: UUID(),
            groupID: groupID,
            score: overallScore,
            summary: generated.summary,
            strength: generated.strength,
            suggestion: generated.suggestion,
            updatedAt: now,
            taskCompletionScore: generated.taskCompletionScore,
            discussionScore: generated.discussionScore,
            collaborationScore: generated.collaborationScore,
            problemSolvingScore: generated.problemSolvingScore,
            reliabilityScore: generated.reliabilityScore
        )
        communicationAnalyses[groupID] = analysis
        lastEvent = L10n.format("AI 已完成專案協作分析：{0} 分", String(describing: overallScore))
        return analysis
    }

    @discardableResult
    func generateProjectAIAnalysis(groupID: UUID) async throws -> CommunicationAnalysis {
        if let existing = communicationAnalyses[groupID],
           existing.taskCompletionScore != nil,
           existing.discussionScore != nil,
           existing.collaborationScore != nil,
           existing.problemSolvingScore != nil,
           existing.reliabilityScore != nil {
            return existing
        }
        if isDemoMode {
            throw ProjectAIAnalysisError.groupNotFound
        }
        guard let group = groups.first(where: { $0.id == groupID }) else {
            throw ProjectAIAnalysisError.groupNotFound
        }
        let repository = chatRepository ?? ChatRepository()
        chatRepository = repository
        let cloudGroupID = group.firestoreDocumentID ?? groupID.uuidString.lowercased()
        if let shared = try await repository.loadLatestProjectAnalysis(
            groupID: cloudGroupID,
            appGroupID: groupID
        ) {
            communicationAnalyses[groupID] = shared
            return shared
        }
        let conversation = try await repository.loadHumanConversation(groupID: cloudGroupID)
        let generated = try await AppleIntelligenceService().analyzeProject(
            groupName: group.name,
            groupDeadline: group.deadline,
            tasks: projectTasks.filter { $0.groupID == groupID },
            members: members.filter { group.memberIDs.contains($0.id) },
            conversation: conversation
        )
        let analysis = saveCommunicationAnalysis(groupID: groupID, generated: generated)
        let analysisID = analysis.id.uuidString.lowercased()
        appendChatItem(.botAnalysis(id: analysisID, analysis: analysis), to: groupID)
        guard await sendChatBotAnalysis(id: analysisID, analysis: analysis, groupID: groupID) else {
            throw ProjectAIAnalysisError.syncFailed
        }
        return analysis
    }

    /// 取得指定群組內某位成員負責的正式任務。
    func tasks(for memberID: UUID, in groupID: UUID) -> [ProjectTask] {
        projectTasks.filter { $0.groupID == groupID && $0.ownerMemberID == memberID }
    }

    /// 依子任務完成狀態計算群組總進度，不要在 View 手動設定百分比。
    func projectProgress(for groupID: UUID) -> Int {
        let tasks = projectTasks.filter { $0.groupID == groupID && $0.includedInProgress }
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

    /// 依目前可存取的所有群組任務，以每項任務等權計算成員整體進度。
    func overallMemberProgress(for memberID: UUID) -> Int {
        let tasks = projectTasks.filter { $0.ownerMemberID == memberID }
        guard !tasks.isEmpty else { return 0 }
        return tasks.reduce(0) { $0 + $1.progress } / tasks.count
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
        if dataMode == .live {
            return peerReviewSummariesByGroupID[groupID]?.completedReviewerCount ?? 0
        }
        guard let group = groups.first(where: { $0.id == groupID }) else { return 0 }
        return group.memberIDs.filter {
            hasCompletedAllReviews(reviewerID: $0, groupID: groupID)
        }.count
    }

    func peerReviewSummary(for groupID: UUID) -> PeerReviewSummary? {
        if dataMode == .live { return peerReviewSummariesByGroupID[groupID] }
        let reviews = reviews(for: groupID)
        guard let group = groups.first(where: { $0.id == groupID }),
              !reviews.isEmpty else { return nil }
        return PeerReviewSummary(
            participantCount: group.memberIDs.count,
            totalReviewCount: reviews.count,
            completedReviewerCount: completedPeerReviewerCount(in: groupID),
            taskCompletionScoreTotal: reviews.reduce(0) { $0 + $1.taskCompletionScore },
            discussionScoreTotal: reviews.reduce(0) { $0 + $1.discussionScore },
            collaborationScoreTotal: reviews.reduce(0) { $0 + $1.collaborationScore },
            ideaScoreTotal: reviews.reduce(0) { $0 + $1.ideaScore },
            reliabilityScoreTotal: reviews.reduce(0) { $0 + $1.reliabilityScore }
        )
    }

    func peerReviewParticipantCount(in groupID: UUID) -> Int {
        if dataMode == .live,
           let count = peerReviewSummariesByGroupID[groupID]?.participantCount,
           count > 0 {
            return count
        }
        return groups.first(where: { $0.id == groupID })?.memberIDs.count ?? 0
    }

    func peerReviewSyncError(for groupID: UUID) -> String? {
        peerReviewStateSyncErrorsByGroupID[groupID]
            ?? peerReviewSummarySyncErrorsByGroupID[groupID]
            ?? peerReviewCommentsSyncErrorsByGroupID[groupID]
    }

    func receivedPeerReviewComments(for groupID: UUID) -> [String] {
        if dataMode == .live {
            return peerReviewCommentsByGroupID[groupID] ?? []
        }
        return reviews(for: groupID)
            .filter { $0.revieweeMemberID == currentUserID }
            .map { $0.comment.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
        let review = try makePeerReview(
            id: UUID(),
            groupID: groupID,
            reviewerID: reviewerID,
            revieweeID: revieweeID,
            taskCompletionScore: taskCompletionScore,
            discussionScore: discussionScore,
            collaborationScore: collaborationScore,
            ideaScore: ideaScore,
            reliabilityScore: reliabilityScore,
            comment: comment,
            now: now
        )
        peerReviews.append(review)
        recordReviewReminderCompletionIfNeeded(groupID: groupID, reviewerID: reviewerID)
        lastEvent = L10n.text("已送出匿名隊員互評")
        return review
    }

    func submitPeerReviewToCloud(
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
    ) async throws -> PeerReview {
        if dataMode == .demo {
            return try submitPeerReview(
                groupID: groupID,
                reviewerID: reviewerID,
                revieweeID: revieweeID,
                taskCompletionScore: taskCompletionScore,
                discussionScore: discussionScore,
                collaborationScore: collaborationScore,
                ideaScore: ideaScore,
                reliabilityScore: reliabilityScore,
                comment: comment,
                now: now
            )
        }

        guard let firebaseUID,
              Auth.auth().currentUser?.uid == firebaseUID else {
            throw PeerReviewCloudError.signedOut
        }
        guard let group = groups.first(where: { $0.id == groupID }),
              let cloudGroupID = group.firestoreDocumentID,
              let revieweeUID = members.first(where: { $0.id == revieweeID })?.firebaseUID else {
            throw PeerReviewCloudError.memberNotFound
        }

        let review = try makePeerReview(
            id: FirebaseMemberIdentity.uiID(for: "peer-review/\(firebaseUID)/\(revieweeUID)"),
            groupID: groupID,
            reviewerID: reviewerID,
            revieweeID: revieweeID,
            taskCompletionScore: taskCompletionScore,
            discussionScore: discussionScore,
            collaborationScore: collaborationScore,
            ideaScore: ideaScore,
            reliabilityScore: reliabilityScore,
            comment: comment,
            now: now
        )

        let repository = peerReviewRepository ?? PeerReviewRepository()
        peerReviewRepository = repository
        try await repository.submit(
            groupID: cloudGroupID,
            revieweeUID: revieweeUID,
            taskCompletionScore: taskCompletionScore,
            discussionScore: discussionScore,
            collaborationScore: collaborationScore,
            ideaScore: ideaScore,
            reliabilityScore: reliabilityScore,
            comment: comment
        )

        guard self.firebaseUID == firebaseUID else {
            throw PeerReviewCloudError.signedOut
        }
        if let index = peerReviews.firstIndex(where: { $0.id == review.id }) {
            peerReviews[index] = review
        } else {
            peerReviews.append(review)
        }
        recordReviewReminderCompletionIfNeeded(groupID: groupID, reviewerID: reviewerID)
        lastEvent = L10n.text("已同步匿名隊員互評")
        return review
    }

    private func makePeerReview(
        id: UUID,
        groupID: UUID,
        reviewerID: UUID,
        revieweeID: UUID,
        taskCompletionScore: Int,
        discussionScore: Int,
        collaborationScore: Int,
        ideaScore: Int,
        reliabilityScore: Int,
        comment: String,
        now: Date
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

        return PeerReview(
            id: id,
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


    }

    private func recordReviewReminderCompletionIfNeeded(groupID: UUID, reviewerID: UUID) {
        guard dataMode == .live,
              let uid = firebaseUID,
              reviewerID == currentUserID,
              let group = groups.first(where: { $0.id == groupID }),
              hasCompletedAllReviews(reviewerID: currentUserID, groupID: groupID) else { return }
        ReviewReminderState.shared.recordCompletion(
            uid: uid,
            groupID: groupID,
            revieweeIDs: Set(group.memberIDs.filter { $0 != currentUserID })
        )
    }

#if DEBUG
    /// 清除指定群組互評，僅供截止後互評流程的 DEBUG 測試選單使用。
    func resetPeerReviews(for groupID: UUID) {
        peerReviews.removeAll { $0.groupID == groupID }
        if let uid = firebaseUID { ReviewReminderState.shared.clear(uid: uid, groupID: groupID) }
        peerReviewSummariesByGroupID[groupID] = nil
        peerReviewCommentsByGroupID[groupID] = nil
    }
#endif

    /// 驗證並發布一項正式任務，同步維護群組的 taskIDs 關係。
    @discardableResult
    func publishTask(
        title: String,
        detail: String,
        subtaskTitles: [String],
        groupID: UUID,
        assigneeMemberID: UUID,
        deadline: Date,
        now: Date = .now
    ) async throws -> ProjectTask {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtaskTitles = subtaskTitles.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmedTitle.isEmpty else { throw PublishTaskError.emptyTitle }
        guard (1...10).contains(trimmedSubtaskTitles.count),
              trimmedSubtaskTitles.allSatisfy({ !$0.isEmpty }) else {
            throw PublishTaskError.invalidSubtasks
        }
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

        let baseWeight = 100 / trimmedSubtaskTitles.count
        let remainder = 100 % trimmedSubtaskTitles.count
        let subtasks = trimmedSubtaskTitles.enumerated().map { index, title in
            Subtask(
                id: UUID(),
                title: title,
                isComplete: false,
                weight: baseWeight + (index < remainder ? 1 : 0)
            )
        }

        let taskID = UUID()
        var task = ProjectTask(
            id: taskID,
            groupID: groupID,
            title: trimmedTitle,
            detail: trimmedDetail,
            weight: 1,
            ownerMemberID: assigneeMemberID,
            subtasks: subtasks,
            deliverable: nil,
            deadline: deadline,
            createdByMemberID: currentUserID,
            createdAt: now
        )

        if dataMode == .live {
            guard let uid = firebaseUID,
                  let groupPath = groups[groupIndex].firestoreDocumentID,
                  let assigneeUID = members.first(where: { $0.id == assigneeMemberID })?.firebaseUID else {
                throw TaskMutationError.invalidData
            }
            let repository = taskMutationRepository ?? TaskMutationRepository()
            taskMutationRepository = repository
            try await repository.create(
                expectedUserID: uid,
                groupID: groupPath,
                taskID: taskID,
                title: trimmedTitle,
                detail: trimmedDetail,
                assigneeUserID: assigneeUID,
                subtasks: subtasks,
                deadline: deadline
            )
            guard firebaseUID == uid else { throw TaskMutationError.notAuthenticated }
            task.firestoreDocumentID = taskID.uuidString.lowercased()
            task.firestoreGroupID = groupPath
        }

        projectTasks.append(task)
        groups[groupIndex].taskIDs.append(task.id)
        lastEvent = L10n.format("已發布新任務「{0}」", String(describing: trimmedTitle))
        return task
    }

    /// 由任務負責人修改自己的任務內容；雲端模式會先通過後端權限驗證。
    func updateOwnedTask(
        taskID: UUID,
        title: String,
        detail: String,
        subtasks: [Subtask],
        deadline: Date,
        now: Date = .now
    ) async throws {
        guard let taskIndex = projectTasks.firstIndex(where: { $0.id == taskID }),
              let groupIndex = groups.firstIndex(where: { $0.id == projectTasks[taskIndex].groupID }) else {
            throw PublishTaskError.groupNotFound
        }
        guard projectTasks[taskIndex].ownerMemberID == currentUserID else {
            throw TaskMutationError.permissionDenied
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw PublishTaskError.emptyTitle }
        guard (1...10).contains(subtasks.count),
              Set(subtasks.map(\.id)).count == subtasks.count,
              subtasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PublishTaskError.invalidSubtasks
        }
        guard deadline > now else { throw PublishTaskError.deadlineNotInFuture }
        guard deadline <= groups[groupIndex].deadline else {
            throw PublishTaskError.deadlineAfterGroupDeadline
        }

        let baseWeight = 100 / subtasks.count
        let remainder = 100 % subtasks.count
        let normalizedSubtasks = subtasks.enumerated().map { index, subtask in
            Subtask(
                id: subtask.id,
                title: subtask.title.trimmingCharacters(in: .whitespacesAndNewlines),
                isComplete: subtask.isComplete,
                weight: baseWeight + (index < remainder ? 1 : 0)
            )
        }

        if dataMode == .live {
            guard let uid = firebaseUID,
                  let groupPath = groups[groupIndex].firestoreDocumentID,
                  let taskPath = projectTasks[taskIndex].firestoreDocumentID else {
                throw TaskMutationError.invalidData
            }
            let repository = taskMutationRepository ?? TaskMutationRepository()
            taskMutationRepository = repository
            try await repository.update(
                expectedUserID: uid,
                groupID: groupPath,
                taskID: taskPath,
                title: trimmedTitle,
                detail: trimmedDetail,
                subtasks: normalizedSubtasks,
                deadline: deadline
            )
            guard firebaseUID == uid else { throw TaskMutationError.notAuthenticated }
        }

        guard let refreshedIndex = projectTasks.firstIndex(where: { $0.id == taskID }) else { return }
        projectTasks[refreshedIndex].title = trimmedTitle
        projectTasks[refreshedIndex].detail = trimmedDetail
        projectTasks[refreshedIndex].subtasks = normalizedSubtasks
        projectTasks[refreshedIndex].deadline = deadline
        lastEvent = L10n.format("已修改任務「{0}」", String(describing: trimmedTitle))
    }

    /// 由任務負責人刪除自己的任務與其附件資料。
    func deleteOwnedTask(taskID: UUID) async throws {
        guard let task = projectTasks.first(where: { $0.id == taskID }),
              let groupIndex = groups.firstIndex(where: { $0.id == task.groupID }) else {
            throw PublishTaskError.groupNotFound
        }
        guard task.ownerMemberID == currentUserID else {
            throw TaskMutationError.permissionDenied
        }

        if dataMode == .live {
            guard let uid = firebaseUID,
                  let groupPath = groups[groupIndex].firestoreDocumentID,
                  let taskPath = task.firestoreDocumentID else {
                throw TaskMutationError.invalidData
            }
            let repository = taskMutationRepository ?? TaskMutationRepository()
            taskMutationRepository = repository
            try await repository.remove(expectedUserID: uid, groupID: groupPath, taskID: taskPath)
            guard firebaseUID == uid else { throw TaskMutationError.notAuthenticated }
        }

        attachmentListeners[taskID]?.remove()
        attachmentListeners[taskID] = nil
        projectTasks.removeAll { $0.id == taskID }
        groups[groupIndex].taskIDs.removeAll { $0 == taskID }
        lastEvent = L10n.format("已刪除任務「{0}」", String(describing: task.title))
    }

    /// 建立一個只有目前使用者的新群組，供建立群組 sheet 呼叫。
    func createGroup(name: String, deadline: Date) {
        var code = GroupInviteCode.generate()
        while groups.contains(where: { $0.inviteCode == code }) { code = GroupInviteCode.generate() }
        let group = Group(id: UUID(), name: name, deadline: deadline, memberIDs: [currentUserID], taskIDs: [], inviteCode: code)
        groups.append(group)
        chatItemsByGroupID[group.id] = [
            .systemEvent(
                id: UUID().uuidString,
                icon: "person.2.fill",
                text: L10n.text("群組聊天室已建立"),
                createdAt: .now
            )
        ]
        saveChatItems()
        lastEvent = L10n.format("已建立「{0}」", String(describing: name))
    }

    /// 正式模式透過受信任的 Callable Function 建立群組、群主會員與邀請碼。
    func createCloudGroup(name: String, deadline: Date) async throws -> Group {
        guard dataMode == .live, let uid = firebaseUID else {
            throw GroupJoinError.notAuthenticated
        }

        let result = try await GroupJoinRepository().create(
            name: name,
            deadline: deadline,
            displayName: normalizedChatDisplayName(profileName)
        )
        guard firebaseUID == uid, result.firebaseUID == uid else {
            throw GroupJoinError.notAuthenticated
        }

        mergeAccessibleCloudGroups([result.group])
        _ = await reloadCloudGroups(reportError: false)
        guard firebaseUID == uid,
              let group = groups.first(where: { $0.id == result.group.id }) else {
            throw GroupJoinError.invalidGroupData
        }
        lastEvent = L10n.format("已建立「{0}」", String(describing: group.name))
        return group
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
        lastEvent = L10n.format("已更新「{0}」期限", String(describing: groups[index].name))
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
        lastEvent = L10n.text("已更新群組名稱")
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
        guard uid != firebaseUID else {
            refreshDeadlineReminders()
            return
        }
        hasLoadedReminderData = false
        PokeBackgroundRefresh.shared.cancel()
        suspendCloudSync()
        groups = []
        projectTasks = []
        members = []
        peerReviews = []
        peerReviewSummariesByGroupID = [:]
        peerReviewCommentsByGroupID = [:]
        personalPeerReviewProjects = []
        tasks = []
        agents = []
        radar = []
        chatItemsByGroupID = [:]
        chatSenderIDsByGroupID = [:]
        communicationAnalyses = [:]
        pokeCounts = [:]
        attachmentsByTaskID = [:]
        attachmentErrors = [:]
        cloudErrorMessage = nil
        cloudGroupSyncErrorMessage = nil
        profileName = ""
        profileBio = ""
        profileRole = ""
        profileAvatarSymbol = "person.fill"
        profileAvatarData = nil
        userName = ""
        lastEvent = ""
        firebaseUID = uid
        if let uid, Auth.auth().currentUser?.uid == uid {
            profileName = Auth.auth().currentUser?.displayName ?? ""
            Task { [weak self] in
                let data = try? await ProfilePhotoService().load(uid: uid)
                guard let self, self.firebaseUID == uid else { return }
                self.profileAvatarData = data
            }
        }
        currentUserID = uid.map(FirebaseMemberIdentity.uiID(for:))
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        publishWidgetSnapshot()
        refreshDeadlineReminders()
    }

    func refreshDeadlineReminders() {
        reminderUpdateTask?.cancel()
        reminderUpdateTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            let enabled = self.notificationsEnabled && self.dataMode == .live
            let plan: [DeadlineReminder]? = self.hasLoadedReminderData && !self.isLoadingCloudGroups
                ? DeadlineReminderPlan.make(groups: self.groups, tasks: self.projectTasks,
                    memberID: self.currentUserID, uid: self.firebaseUID ?? "", now: .now,
                    reminderTime: Calendar.current.dateComponents([.hour, .minute], from: self.deadlineReminderTime),
                    completedReviewGroupIDs: Set(self.groups.filter { self.hasCompletedReviewReminders(in: $0) }.map(\.id)))
                : nil
            DeadlineNotificationService.shared.update(uid: self.firebaseUID, enabled: enabled, plan: plan, categories: self.notificationCategories)
        }
    }

    func hasCompletedReviewReminders(in group: Group) -> Bool {
        hasCompletedAllReviews(reviewerID: currentUserID, groupID: group.id)
            || (firebaseUID.map { ReviewReminderState.shared.isComplete(uid: $0, groupID: group.id,
                revieweeIDs: Set(group.memberIDs.filter { $0 != currentUserID })) } ?? false)
    }

    func resumeCloudSync() {
        guard dataMode == .live, firebaseUID != nil, !syncIsActive else { return }
        syncIsActive = true
        refreshDeadlineReminders()
        PokeBackgroundRefresh.shared.schedule()
        registerPokeDevice()
        cloudLoadTask = Task { [weak self] in _ = await self?.reloadCloudGroups() }
    }

    func registerPokeDevice() {
        guard dataMode == .live, firebaseUID != nil else { return }
        Task { [weak self] in
            do {
                let repository = self?.pokeRepository ?? PokeRepository()
                self?.pokeRepository = repository
                try await repository.registerCurrentDevice()
            } catch {
                // Notification registration must not block cloud-group synchronization.
            }
        }
    }

    func suspendCloudSync() {
        syncIsActive = false
        cloudGeneration = UUID()
        cloudLoadTask?.cancel()
        cloudLoadTask = nil
        stopAttachmentSync()
        stopPokeSync()
        stopPeerReviewSync()
        attachmentsByTaskID = [:]
        attachmentErrors = [:]
        for index in projectTasks.indices where projectTasks[index].firestoreDocumentID != nil {
            projectTasks[index].deliverable = nil
        }
        isLoadingCloudGroups = false
    }

    private func stopAttachmentSync() {
        progressSubscriptions.values.forEach { $0.stop() }
        progressSubscriptions = [:]
        progressSyncErrorsByGroupID = [:]
        pendingTaskUpdates = []
        pendingSubtaskUpdates = [:]
        attachmentListeners.values.forEach { $0.remove() }
        attachmentListeners.removeAll()
    }

    private func stopPokeSync() {
        pokeListeners.values.forEach { $0.remove() }
        pokeListeners = [:]
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
        stopPokeSync()
        stopPeerReviewSync()
        startPersonalPeerReviewSync(uid: uid, generation: generation)
        isLoadingCloudGroups = true
        defer {
            if cloudGeneration == generation {
                isLoadingCloudGroups = false
                refreshDeadlineReminders()
            }
        }
        do {
            let repository = groupRepository ?? GroupRepository.firebase()
            groupRepository = repository
            let loaded = try await repository.load()
            guard !Task.isCancelled, firebaseUID == uid, cloudGeneration == generation, syncIsActive else { return false }
            // Replace, never append stale account/group/task rows.
            projectTasks = loaded.flatMap(\.tasks)
            groups = loaded.map(\.group)
            hasLoadedReminderData = true
            var byID: [UUID: Member] = [:]
            for member in loaded.flatMap(\.members) { byID[member.id] = member }
            members = byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
            userName = byID[currentUserID]?.name ?? ""
            let taskIDs = Set(projectTasks.map(\.id))
            attachmentsByTaskID = attachmentsByTaskID.filter { taskIDs.contains($0.key) }
            attachmentErrors = [:]
            cloudErrorMessage = nil
            cloudGroupSyncErrorMessage = nil
            // Tasks now exist in the single source of truth; only now attach listeners.
            startAttachmentSync(for: projectTasks.map(\.id))
            for group in groups { startProgressSync(group: group, uid: uid, generation: generation) }
            for group in groups { startPokeSync(group: group, uid: uid, generation: generation) }
            for group in groups { startPeerReviewSync(group: group, uid: uid, generation: generation) }
            let personalRepository = peerReviewRepository ?? PeerReviewRepository()
            peerReviewRepository = personalRepository
            Task { [weak self] in
                do {
                    try await personalRepository.syncMyHistory()
                } catch {
                    await MainActor.run {
                        guard let self, self.firebaseUID == uid, self.cloudGeneration == generation else { return }
                        self.personalPeerReviewSyncError = Self.cloudMessage(error)
                    }
                }
            }
            if let photo = try? await ProfilePhotoService().load(uid: uid), firebaseUID == uid {
                profileAvatarData = photo
                try? await ProfilePhotoService().share(
                    photo,
                    uid: uid,
                    groupIDs: groups.compactMap(\.firestoreDocumentID)
                )
            }
            return true
        } catch {
            guard !Task.isCancelled, firebaseUID == uid, cloudGeneration == generation else { return false }
            // Keep the last successful snapshot so a transient failure is not mistaken for an empty account.
            let message = Self.cloudMessage(error)
            cloudGroupSyncErrorMessage = message
            if reportError { cloudErrorMessage = message }
            return false
        }
    }

    func acceptJoinedGroup(_ result: GroupJoinResult) -> Bool {
        guard firebaseUID == result.firebaseUID else { return false }
        cloudErrorMessage = nil
        mergeAccessibleCloudGroups([result.group])
        lastEvent = result.wasAlreadyMember
            ? L10n.format("你已經是「{0}」的成員", String(describing: result.group.name))
            : L10n.format("已加入「{0}」", String(describing: result.group.name))
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
        return L10n.text("雲端資料同步失敗，請確認網路後重新整理。")
    }

#if DEBUG
    /// 僅供 Debug 原型資料使用；正式邀請碼加入流程由 Callable Function 處理。
    @discardableResult
    func joinGroup(inviteCode: String) -> Bool {
        let code = GroupInviteCode.normalized(inviteCode)
        guard GroupInviteCode.isValid(code) else { return false }
        guard let index = groups.firstIndex(where: { $0.inviteCode == code }) else { return false }
        if !groups[index].memberIDs.contains(currentUserID) {
            groups[index].memberIDs.append(currentUserID)
        }
        lastEvent = L10n.format("已加入「{0}」", String(describing: groups[index].name))
        return true
    }
#endif

    func chooseGroupLeader(groupID: UUID, candidateID: UUID, electionID: String?) async throws {
        guard let group = groups.first(where: { $0.id == groupID }),
              group.memberIDs.contains(currentUserID), group.memberIDs.contains(candidateID),
              let candidate = members.first(where: { $0.id == candidateID }) else { throw GroupJoinError.permissionDenied }
        let account = firebaseUID
        if !isDemoMode {
            guard let path = group.firestoreDocumentID, let uid = candidate.firebaseUID else { throw GroupJoinError.invalidGroupData }
            try await GroupJoinRepository().chooseLeader(groupID: path, candidateUID: uid, electionID: electionID)
            guard firebaseUID == account else { return }
        } else if let index = groups.firstIndex(where: { $0.id == groupID }),
                  group.memberRoles[currentUserID] == .leader {
            for memberID in group.memberIDs { groups[index].memberRoles[memberID] = memberID == candidateID ? .leader : .member }
        }
    }

    func setDepartedTasksInclusion(groupID: UUID, departureID: String, included: Bool) async throws {
        guard let group = groups.first(where: { $0.id == groupID }),
              members.contains(where: { $0.id == currentUserID && group.memberIDs.contains($0.id) && (group.memberRoles[$0.id] ?? $0.role) == .leader }) else {
            throw GroupJoinError.permissionDenied
        }
        let account = firebaseUID
        if !isDemoMode {
            guard let path = group.firestoreDocumentID else { throw GroupJoinError.invalidGroupData }
            try await GroupJoinRepository().setDepartedTasksInclusion(groupID: path, departureID: departureID, included: included)
            guard firebaseUID == account else { return }
        }
        for index in projectTasks.indices where projectTasks[index].groupID == groupID && projectTasks[index].departureID == departureID {
            projectTasks[index].includedInProgress = included
            projectTasks[index].departureReviewed = true
        }
        publishWidgetSnapshot()
    }

    /// Only remove local data after the server confirms the caller has left.
    func leaveGroup(groupID: UUID) async throws {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        let uid = firebaseUID
        if !isDemoMode {
            guard let path = group.firestoreDocumentID else { throw GroupJoinError.invalidGroupData }
            suspendCloudSync()
            do {
                try await GroupJoinRepository().leave(groupID: path)
            } catch {
                if firebaseUID == uid { resumeCloudSync() }
                throw error
            }
            guard firebaseUID == uid else { throw GroupJoinError.notAuthenticated }
        }
        chatMessageListeners.removeValue(forKey: groupID)?.remove()
        chatPresenceListeners.removeValue(forKey: groupID)?.remove()
        chatHeartbeatTasks.removeValue(forKey: groupID)?.cancel()
        onlineMembersByGroupID[groupID] = nil
        chatMessageSyncErrorsByGroupID[groupID] = nil
        chatPresenceSyncErrorsByGroupID[groupID] = nil
        chatMessageSyncReadyGroupIDs.remove(groupID)
        groups.removeAll { $0.id == groupID }
        projectTasks.removeAll { $0.groupID == groupID }
        peerReviews.removeAll { $0.groupID == groupID }
        peerReviewSummariesByGroupID[groupID] = nil
        peerReviewCommentsByGroupID[groupID] = nil
        communicationAnalyses[groupID] = nil
        chatItemsByGroupID[groupID] = nil
        chatSenderIDsByGroupID[groupID] = nil
        saveChatItems()
        publishWidgetSnapshot()
        lastEvent = L10n.format("已退出「{0}」", String(describing: group.name))
        groupLeaveMessage = lastEvent
        if !isDemoMode { resumeCloudSync() }
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

    func saveProfileNickname(_ value: String) async throws {
        guard !isSavingNickname else { return }
        if dataMode != .live {
            profileName = try ProfileNicknameRepository.normalized(value)
            return
        }
        guard let uid = firebaseUID, Auth.auth().currentUser?.uid == uid else { throw NicknameError.signedOut }
        isSavingNickname = true
        defer { isSavingNickname = false }
        let name = try await ProfileNicknameRepository.firebase().save(value, groupIDs: groups.compactMap(\.firestoreDocumentID))
        guard firebaseUID == uid else { throw NicknameError.accountChanged }
        profileName = name
        userName = name
        if let index = members.firstIndex(where: { $0.firebaseUID == uid }) { members[index].name = name }
    }

    private func sendTaskUpdate(taskID: UUID, action: String, subtaskID: String? = nil,
                                isComplete: Bool? = nil, attachmentID: String? = nil) {
        guard let uid = firebaseUID, !pendingTaskUpdates.contains(taskID),
              let task = projectTasks.first(where: { $0.id == taskID }),
              let groupID = task.firestoreGroupID, let documentID = task.firestoreDocumentID else { return }
        let generation = cloudGeneration
        pendingTaskUpdates.insert(taskID)
        let updatingSubtaskID = subtaskID.flatMap(UUID.init(uuidString:))
        if action == "setSubtask", let updatingSubtaskID {
            pendingSubtaskUpdates[taskID] = updatingSubtaskID
        }
        Task { [weak self] in
            do {
                try await TaskProgressRepository().update(groupID: groupID, taskID: documentID, action: action,
                    subtaskID: subtaskID, isComplete: isComplete, attachmentID: attachmentID)
                guard let self, self.firebaseUID == uid, self.cloudGeneration == generation else { return }
                if action == "setSubtask", let updatingSubtaskID, let isComplete,
                   let taskIndex = self.projectTasks.firstIndex(where: { $0.id == taskID }),
                   let subtaskIndex = self.projectTasks[taskIndex].subtasks.firstIndex(where: { $0.id == updatingSubtaskID }) {
                    self.projectTasks[taskIndex].subtasks[subtaskIndex].isComplete = isComplete
                }
                self.pendingTaskUpdates.remove(taskID)
                self.pendingSubtaskUpdates.removeValue(forKey: taskID)
                self.lastEvent = action == "confirm" ? L10n.text("已送出成果確認") : L10n.text("已更新子任務")
            } catch {
                guard let self, self.firebaseUID == uid, self.cloudGeneration == generation else { return }
                self.pendingTaskUpdates.remove(taskID)
                self.pendingSubtaskUpdates.removeValue(forKey: taskID)
                self.cloudErrorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.text("任務更新失敗，請重試。")
            }
        }
    }

    private func startProgressSync(group: Group, uid: String, generation: UUID) {
        guard let path = group.firestoreDocumentID else { return }
        let summary = CloudGroupSummary(id: group.id, name: group.name, deadline: group.deadline,
                                       inviteCode: group.inviteCode, documentID: path)
        progressSubscriptions[group.id] = GroupProgressSubscription(summary: summary, uid: uid) { [weak self] result in
            guard let self, self.firebaseUID == uid, self.cloudGeneration == generation, self.syncIsActive else { return }
            switch result {
            case .failure(let error):
                self.progressSyncErrorsByGroupID[group.id] = Self.cloudMessage(error)
                self.cloudGroupSyncErrorMessage = self.progressSyncErrorsByGroupID.values.first
            case .success(let loaded):
                guard let index = self.groups.firstIndex(where: { $0.id == group.id }) else { return }
                let oldIDs = Set(self.projectTasks.filter { $0.groupID == group.id }.map(\.id))
                let newIDs = Set(loaded.tasks.map(\.id))
                for id in oldIDs.subtracting(newIDs) {
                    self.attachmentListeners.removeValue(forKey: id)?.remove()
                    self.attachmentsByTaskID.removeValue(forKey: id)
                }
                self.groups[index].memberIDs = loaded.group.memberIDs
                self.groups[index].memberRoles = loaded.group.memberRoles
                self.groups[index].leaderElectionID = loaded.group.leaderElectionID
                self.groups[index].leaderVotes = loaded.group.leaderVotes
                self.groups[index].taskIDs = loaded.group.taskIDs
                for member in loaded.members {
                    if let i = self.members.firstIndex(where: { $0.id == member.id }) { self.members[i] = member }
                    else { self.members.append(member) }
                    if member.id == self.currentUserID { self.userName = member.name }
                }
                self.projectTasks.removeAll { $0.groupID == group.id }
                self.projectTasks.append(contentsOf: loaded.tasks)
                for task in loaded.tasks {
                    self.applyCloudAttachments(self.attachmentsByTaskID[task.id] ?? [], to: task.id)
                    self.startAttachmentSync(for: task.id)
                }
                self.progressSyncErrorsByGroupID[group.id] = nil
                self.cloudGroupSyncErrorMessage = self.progressSyncErrorsByGroupID.values.first
            }
        }
    }

    private func startPokeSync(group: Group, uid: String, generation: UUID) {
        guard let firestoreGroupID = group.firestoreDocumentID else { return }

        let repository = pokeRepository ?? PokeRepository()
        pokeRepository = repository
        pokeListeners[group.id] = repository.listenForIncomingPokes(
            groupID: firestoreGroupID,
            recipientUID: uid
        ) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.dataMode == .live,
                      self.syncIsActive,
                      self.firebaseUID == uid,
                      self.cloudGeneration == generation else { return }

                switch result {
                case .success(let receptions):
                    if receptions.isEmpty {
                        _ = PokeDeliveryState.shared.unseenCount(latestCount: 0, uid: uid, groupID: firestoreGroupID)
                    }
                    for reception in receptions {
                        let unseen = PokeDeliveryState.shared.unseenCount(
                            latestCount: reception.pokeCount, uid: uid, groupID: firestoreGroupID
                        )
                        PokeDeliveryState.shared.markHandled(count: reception.pokeCount, uid: uid, groupID: firestoreGroupID)
                        if self.receivesPokes, unseen > 0 {
                            NotificationCenter.default.post(name: .pokeReceived, object: reception)
                        }
                    }
                case .failure:
                    self.cloudErrorMessage = L10n.text("即時通知同步失敗，請確認網路後重試。")
                }
            }
        }
    }

    private func startPeerReviewSync(group: Group, uid: String, generation: UUID) {
        guard let path = group.firestoreDocumentID else { return }
        let repository = peerReviewRepository ?? PeerReviewRepository()
        peerReviewRepository = repository

        peerReviewStateListeners[group.id]?.remove()
        peerReviewStateListeners[group.id] = repository.listenToMyState(groupID: path) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.firebaseUID == uid,
                      self.cloudGeneration == generation,
                      self.syncIsActive else { return }

                switch result {
                case .success(let state):
                    let mapped = state.reviewedUIDs.map { revieweeUID in
                        PeerReview(
                            id: FirebaseMemberIdentity.uiID(for: "peer-review/\(uid)/\(revieweeUID)"),
                            groupID: group.id,
                            reviewerMemberID: self.currentUserID,
                            revieweeMemberID: FirebaseMemberIdentity.uiID(for: revieweeUID),
                            taskCompletionScore: 0,
                            discussionScore: 0,
                            collaborationScore: 0,
                            ideaScore: 0,
                            reliabilityScore: 0,
                            comment: "",
                            submittedAt: .distantPast
                        )
                    }
                    self.peerReviews.removeAll { $0.groupID == group.id }
                    self.peerReviews.append(contentsOf: mapped)
                    self.peerReviewStateSyncErrorsByGroupID[group.id] = nil
                case .failure(let error):
                    self.peerReviewStateSyncErrorsByGroupID[group.id] = Self.cloudMessage(error)
                }
            }
        }

        peerReviewSummaryListeners[group.id]?.remove()
        peerReviewSummaryListeners[group.id] = repository.listenToSummary(groupID: path) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.firebaseUID == uid,
                      self.cloudGeneration == generation,
                      self.syncIsActive else { return }

                switch result {
                case .success(let value):
                    self.peerReviewSummariesByGroupID[group.id] = PeerReviewSummary(
                        participantCount: value.participantCount ?? 0,
                        totalReviewCount: value.totalReviewCount,
                        completedReviewerCount: value.completedReviewerCount,
                        taskCompletionScoreTotal: value.taskCompletionScoreTotal,
                        discussionScoreTotal: value.discussionScoreTotal,
                        collaborationScoreTotal: value.collaborationScoreTotal,
                        ideaScoreTotal: value.ideaScoreTotal,
                        reliabilityScoreTotal: value.reliabilityScoreTotal
                    )
                    self.peerReviewSummarySyncErrorsByGroupID[group.id] = nil
                    if value.resultsAvailable {
                        Task { @MainActor [weak self] in
                            do {
                                let comments = try await repository.loadMyComments(groupID: path)
                                guard let self,
                                      self.firebaseUID == uid,
                                      self.cloudGeneration == generation,
                                      self.syncIsActive else { return }
                                self.peerReviewCommentsByGroupID[group.id] = comments
                                self.peerReviewCommentsSyncErrorsByGroupID[group.id] = nil
                            } catch {
                                guard let self,
                                      self.firebaseUID == uid,
                                      self.cloudGeneration == generation,
                                      self.syncIsActive else { return }
                                self.peerReviewCommentsSyncErrorsByGroupID[group.id] = Self.cloudMessage(error)
                            }
                        }
                    }
                case .failure(let error):
                    self.peerReviewSummarySyncErrorsByGroupID[group.id] = Self.cloudMessage(error)
                }
            }
        }

        peerReviewCommentsListeners[group.id]?.remove()
        peerReviewCommentsListeners[group.id] = repository.listenToMyComments(groupID: path) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.firebaseUID == uid,
                      self.cloudGeneration == generation,
                      self.syncIsActive else { return }

                switch result {
                case .success(let value):
                    self.peerReviewCommentsByGroupID[group.id] = value.comments
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    self.peerReviewCommentsSyncErrorsByGroupID[group.id] = nil
                case .failure(let error):
                    self.peerReviewCommentsSyncErrorsByGroupID[group.id] = Self.cloudMessage(error)
                }
            }
        }
    }

    private func startPersonalPeerReviewSync(uid: String, generation: UUID) {
        let repository = peerReviewRepository ?? PeerReviewRepository()
        peerReviewRepository = repository
        personalPeerReviewProjectsListener?.remove()
        personalPeerReviewProjectsListener = repository.listenToMyProjects { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.firebaseUID == uid,
                      self.cloudGeneration == generation,
                      self.syncIsActive else { return }
                switch result {
                case .success(let projects):
                    self.personalPeerReviewProjects = projects
                    self.personalPeerReviewSyncError = nil
                case .failure(let error):
                    self.personalPeerReviewSyncError = Self.cloudMessage(error)
                }
            }
        }
    }

    /// 切換子任務完成狀態；雲端任務等待後端確認，再由即時監聽更新畫面。
    func toggleSubtask(taskID: UUID, subtaskID: UUID) async {
        guard let taskIndex = projectTasks.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = projectTasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        if projectTasks[taskIndex].firestoreDocumentID != nil {
            let subtask = projectTasks[taskIndex].subtasks[subtaskIndex]
            sendTaskUpdate(taskID: taskID, action: "setSubtask", subtaskID: subtask.id.uuidString,
                           isComplete: !subtask.isComplete)
            return
        }
        projectTasks[taskIndex].subtasks[subtaskIndex].isComplete.toggle()
        lastEvent = L10n.format("已更新「{0}」進度", String(describing: projectTasks[taskIndex].title))
    }

    /// 為任務送出成果；畫面傳入的 Deliverable 可來自 mock 檔案或連結。
    func submitDeliverable(taskID: UUID, deliverable: Deliverable) {
        guard let index = projectTasks.firstIndex(where: { $0.id == taskID }) else { return }
        projectTasks[index].deliverable = deliverable
        lastEvent = L10n.format("已送出「{0}」成果", String(describing: projectTasks[index].title))
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

    func downloadAttachment(_ attachment: TaskAttachment, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        guard let uid = firebaseUID, Auth.auth().currentUser?.uid == uid else {
            throw AttachmentOperationError.signedOut
        }
        let url = try await AttachmentDownloadService.firebase().download(attachment, progress: progress)
        guard firebaseUID == uid, Auth.auth().currentUser?.uid == uid else {
            AttachmentDownloadService.removeLocalFile(url)
            throw AttachmentOperationError.accountChanged
        }
        return url
    }

    func editAttachment(_ attachment: TaskAttachment, title: String, detail: String, taskID: UUID) async throws {
        guard let uid = firebaseUID, Auth.auth().currentUser?.uid == uid else { throw AttachmentOperationError.signedOut }
        guard attachment.uploaderID == uid else { throw GroupJoinError.permissionDenied }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 100, detail.count <= 1000 else { throw AttachmentOperationError.invalidFile }
        try await Firestore.firestore().collection("groups").document(attachment.groupID)
            .collection("tasks").document(attachment.taskID).collection("attachments").document(attachment.id)
            .updateData(["title": title, "detail": detail])
        guard firebaseUID == uid else { throw AttachmentOperationError.accountChanged }
        var items = attachmentsByTaskID[taskID] ?? []
        if let index = items.firstIndex(where: { $0.id == attachment.id }) {
            items[index].title = title
            items[index].detail = detail
            applyCloudAttachments(items, to: taskID)
        }
    }

    func deleteAttachment(_ attachment: TaskAttachment, taskID: UUID) async throws {
        guard let uid = firebaseUID, Auth.auth().currentUser?.uid == uid else {
            throw AttachmentOperationError.signedOut
        }
        try await AttachmentDeletionService.firebase().delete(attachment)
        guard firebaseUID == uid, Auth.auth().currentUser?.uid == uid else {
            throw AttachmentOperationError.accountChanged
        }
        // Only remove locally after BOTH remote operations succeed. Listener remains authoritative.
        applyCloudAttachments((attachmentsByTaskID[taskID] ?? []).filter { $0.id != attachment.id }, to: taskID)
        lastEvent = L10n.text("附件已刪除")
    }

    private func applyCloudAttachments(_ attachments: [TaskAttachment], to taskID: UUID) {
        guard let taskIndex = projectTasks.firstIndex(where: { $0.id == taskID }) else { return }
        attachmentsByTaskID[taskID] = attachments
        var task = projectTasks[taskIndex]
        task.deliverable = attachments.first(where: { $0.status == .ready }).map { attachment in
            var result = Deliverable(attachment: attachment)
            if task.confirmedAttachmentID == attachment.id {
                result.confirmedMemberIDs = task.confirmedMemberUIDs.map(FirebaseMemberIdentity.uiID(for:))
                let memberIDs = groups.first(where: { $0.id == task.groupID })?.memberIDs ?? []
                result.isApproved = task.cloudStatus == .completed && !memberIDs.isEmpty
                    && memberIDs.filter { $0 != task.ownerMemberID }.allSatisfy { result.confirmedMemberIDs.contains($0) }
                    && task.subtasks.allSatisfy(\.isComplete)
            }
            return result
        }
        projectTasks[taskIndex] = task
    }

    /// 由群組成員確認已看到任務成果；同一位成員不可重複確認。
    func confirmDeliverable(taskID: UUID, memberID: UUID) {
        if let task = projectTasks.first(where: { $0.id == taskID }), task.firestoreDocumentID != nil {
            guard memberID == currentUserID, memberID != task.ownerMemberID,
                  let id = task.deliverable?.attachmentID else { return }
            sendTaskUpdate(taskID: taskID, action: "confirm", attachmentID: id)
            return
        }
        guard let taskIndex = projectTasks.firstIndex(where: { $0.id == taskID }),
              let group = groups.first(where: { $0.id == projectTasks[taskIndex].groupID }),
              group.memberIDs.contains(memberID),
              memberID != projectTasks[taskIndex].ownerMemberID,
              var deliverable = projectTasks[taskIndex].deliverable,
              !deliverable.confirmedMemberIDs.contains(memberID) else { return }

        deliverable.confirmedMemberIDs.append(memberID)
        projectTasks[taskIndex].deliverable = deliverable
        lastEvent = L10n.format("已確認「{0}」成果進度", String(describing: projectTasks[taskIndex].title))
    }

    /// 將已送出的成果標記為驗收通過。
    func approveDeliverable(taskID: UUID) {
        if projectTasks.first(where: { $0.id == taskID })?.firestoreDocumentID != nil {
            confirmDeliverable(taskID: taskID, memberID: currentUserID)
            return
        }
        guard let index = projectTasks.firstIndex(where: { $0.id == taskID }),
              var deliverable = projectTasks[index].deliverable else { return }
        deliverable.isApproved = true
        projectTasks[index].deliverable = deliverable
        lastEvent = L10n.format("已驗收「{0}」成果", String(describing: projectTasks[index].title))
    }

    /// 在群組內提醒進度較慢的成員；接收端通知應只在被戳者的裝置上送達。
    @discardableResult
    func poke(memberID: UUID, in groupID: UUID, style: PokeStyle) -> Int? {
        guard memberID != currentUserID,
              groups.contains(where: { $0.id == groupID && $0.memberIDs.contains(memberID) }),
              let member = members.first(where: { $0.id == memberID }),
              memberProgress(for: memberID, in: groupID) <= 90 else { return nil }
        lastEvent = L10n.format("用「{0}」戳了 {1}", L10n.text(style.rawValue), String(describing: member.name))

        let key = PokeCountKey(groupID: groupID, memberID: memberID)
        let pokeCount = (pokeCounts[key] ?? 0) + 1
        pokeCounts[key] = pokeCount
        if dataMode == .live,
           let firestoreGroupID = groups.first(where: { $0.id == groupID })?.firestoreDocumentID,
           let recipientUID = member.firebaseUID {
            Task { [weak self] in
                do {
                    let repository = self?.pokeRepository ?? PokeRepository()
                    self?.pokeRepository = repository
                    try await repository.send(groupID: firestoreGroupID, recipientUID: recipientUID, style: style)
                } catch {
                    self?.cloudErrorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.text("戳戳送出失敗，請重試。")
                }
            }
        }
        return pokeCount
    }

    /// 供通知設定的測試頁使用，模擬目前使用者收到群組的戳一戳通知。
    @discardableResult
    func sendTestPoke(in groupID: UUID) -> Int? {
        guard receivesPokes,
              let group = groups.first(where: { $0.id == groupID }) else { return nil }

        let key = PokeCountKey(groupID: groupID, memberID: currentUserID)
        let pokeCount = (pokeCounts[key] ?? 0) + 1
        pokeCounts[key] = pokeCount
        pokeNotifications.deliver(group: group, pokeCount: pokeCount, style: .gentle)
        return pokeCount
    }

    /// 舊任務看板的認領行為；等新任務畫面完成後改用 ProjectTask.ownerMemberID。
    func claim(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].owner == nil else { return }
        tasks[index].owner = userName
        lastEvent = L10n.format("已認領「{0}」", String(describing: tasks[index].title))
    }

    /// 舊版催進度行為；新版群組詳細頁請改呼叫 poke(memberID:in:style:)。
    func poke(agentID: UUID, style: PokeStyle) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        lastEvent = L10n.format("用「{0}」戳了 {1}", L10n.text(style.rawValue), String(describing: agents[index].name))
    }

    /// 舊版「我在做了」護盾行為；新版可改成綁定個別 ProjectTask。
    func shield(minutes: Int, note: String) {
        guard let index = agents.firstIndex(where: { $0.name == userName }) else { return }
        agents[index].isShielded = true
        agents[index].status = L10n.format("護盾 {0} 分鐘｜{1}", String(describing: minutes), String(describing: note))
        agents[index].progress = min(100, agents[index].progress + 5)
        lastEvent = L10n.text("護盾啟動，隊友看得到你在做了")
    }
}

private struct PokeCountKey: Hashable {
    let groupID: UUID
    let memberID: UUID
}

/// 暫時相容舊 View 名稱；新檔案一律使用 AppStore。
typealias GroupBombModel = AppStore
