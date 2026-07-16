import Foundation
import Observation

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

/// 全 App 的唯一資料來源。
/// B、C、D 請只透過這個 Store 讀取與修改 mock 資料，不要在 View 內建立第二份任務或成員資料。
@MainActor @Observable
final class AppStore {
    /// 目前登入使用者的成員 ID；「我的任務」用它篩選任務。
    let currentUserID: UUID

    /// 目前登入使用者的顯示名稱；舊版任務看板仍會使用。
    let userName: String

    /// 設定頁顯示的個人暱稱。
    let profileName = "Peach"

    /// 本機原型的通知開關。
    var notificationsEnabled = true

    /// 所有已加入的群組，群組列表直接讀取這個陣列。
    var groups: [Group]

    /// 所有成員；以 Group.memberIDs 決定某群組要顯示哪些人。
    var members: [Member]

    /// 所有正式任務；任務與群組、負責人的關係都用 ID 連結。
    var projectTasks: [ProjectTask]

    /// 舊版任務看板資料；等 C 完成新群組詳細頁後再移除。
    var tasks: [MissionTask]

    /// 舊版特工頁資料；等 C 完成新版成員進度卡後再移除。
    var agents: [Agent]

    /// 互評雷達圖的 mock 資料。
    let radar: [RadarMetric]

    /// 顯示在舊版畫面上的最新系統事件文字。
    var lastEvent: String

    init() {
        let me = Member(id: UUID(), name: "我", role: .leader, avatarSymbol: "person.fill")
        let xiaoYu = Member(id: UUID(), name: "小宇", role: .member, avatarSymbol: "person.fill")
        let miMi = Member(id: UUID(), name: "米米", role: .member, avatarSymbol: "person.fill")
        let aKai = Member(id: UUID(), name: "阿凱", role: .member, avatarSymbol: "person.fill")
        let allMembers = [me, xiaoYu, miMi, aKai]

        let groupID = UUID()
        let initialCreatedAt = Date.now
        let groupDeadline = initialCreatedAt.addingTimeInterval(48 * 60 * 60)
        let researchTask = ProjectTask(
            id: UUID(), groupID: groupID, title: "蒐集市場數據", detail: "找到 3 個可信來源", weight: 25,
            ownerMemberID: nil,
            subtasks: [
                Subtask(id: UUID(), title: "找到三個可信來源", isComplete: false, weight: 50),
                Subtask(id: UUID(), title: "整理資料重點", isComplete: false, weight: 50)
            ],
            deliverable: nil,
            deadline: groupDeadline,
            createdByMemberID: me.id,
            createdAt: initialCreatedAt,
            status: .pending
        )
        let competitorTask = ProjectTask(
            id: UUID(), groupID: groupID, title: "製作競品分析", detail: "完成比較矩陣", weight: 30,
            ownerMemberID: xiaoYu.id,
            subtasks: [
                Subtask(id: UUID(), title: "整理競品資料", isComplete: true, weight: 40),
                Subtask(id: UUID(), title: "完成比較矩陣", isComplete: false, weight: 60)
            ],
            deliverable: nil,
            deadline: groupDeadline,
            createdByMemberID: me.id,
            createdAt: initialCreatedAt,
            status: .inProgress
        )
        let designTask = ProjectTask(
            id: UUID(), groupID: groupID, title: "簡報視覺統整", detail: "統一圖表與版面", weight: 25,
            ownerMemberID: me.id,
            subtasks: [
                Subtask(id: UUID(), title: "建立簡報版型", isComplete: true, weight: 50),
                Subtask(id: UUID(), title: "統一圖表風格", isComplete: false, weight: 50)
            ],
            deliverable: nil,
            deadline: groupDeadline,
            createdByMemberID: me.id,
            createdAt: initialCreatedAt,
            status: .inProgress
        )
        let conclusionTask = ProjectTask(
            id: UUID(), groupID: groupID, title: "結論與建議", detail: "收斂成 3 個重點", weight: 20,
            ownerMemberID: aKai.id,
            subtasks: [
                Subtask(id: UUID(), title: "撰寫三個重點", isComplete: false, weight: 100)
            ],
            deliverable: nil,
            deadline: groupDeadline,
            createdByMemberID: me.id,
            createdAt: initialCreatedAt,
            status: .pending
        )
        let allProjectTasks = [researchTask, competitorTask, designTask, conclusionTask]

        currentUserID = me.id
        userName = me.name
        members = allMembers
        projectTasks = allProjectTasks
        groups = [
            Group(
                id: groupID,
                name: "期末報告拆彈小隊",
                deadline: groupDeadline,
                memberIDs: allMembers.map(\.id),
                taskIDs: allProjectTasks.map(\.id),
                inviteCode: "BOMB52"
            )
        ]

        tasks = [
            MissionTask(title: "蒐集市場數據", detail: "找到 3 個可信來源", points: 120, owner: nil),
            MissionTask(title: "製作競品分析", detail: "完成比較矩陣", points: 180, owner: "小宇"),
            MissionTask(title: "簡報視覺統整", detail: "統一圖表與版面", points: 150, owner: nil),
            MissionTask(title: "結論與建議", detail: "收斂成 3 個重點", points: 200, owner: "阿凱")
        ]
        agents = [
            Agent(name: "我", role: "拆彈手", progress: 62, status: "正在攻堅"),
            Agent(name: "小宇", role: "情報員", progress: 78, status: "火力全開"),
            Agent(name: "米米", role: "分析師", progress: 28, status: "訊號微弱"),
            Agent(name: "阿凱", role: "簡報手", progress: 43, status: "緩慢推進")
        ]
        radar = [
            RadarMetric(title: "準時", score: 0.82), RadarMetric(title: "品質", score: 0.75),
            RadarMetric(title: "溝通", score: 0.92), RadarMetric(title: "救火", score: 0.68),
            RadarMetric(title: "合作", score: 0.88)
        ]
        lastEvent = "拆彈小隊已上線"
    }

    /// 舊任務看板中「我已認領幾項任務」的數值。
    var claimedCount: Int { tasks.filter { $0.owner == userName }.count }

    /// 舊特工頁的平均進度；新版畫面請使用 projectProgress(for:)。
    var teamProgress: Int { agents.map(\.progress).reduce(0, +) / max(agents.count, 1) }

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

    /// 依該成員負責任務的子任務完成狀態計算個人進度。
    func memberProgress(for memberID: UUID, in groupID: UUID) -> Int {
        let tasks = tasks(for: memberID, in: groupID)
        let totalWeight = tasks.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        return tasks.reduce(0) { $0 + $1.progress * $1.weight } / totalWeight
    }

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
        lastEvent = "已建立「\(name)」"
    }

    /// 以邀請碼加入 MVP mock 群組；成功時回傳 true，輸入空白則回傳 false。
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

    /// 將已送出的成果標記為驗收通過。
    func approveDeliverable(taskID: UUID) {
        guard let index = projectTasks.firstIndex(where: { $0.id == taskID }),
              var deliverable = projectTasks[index].deliverable else { return }
        deliverable.isApproved = true
        projectTasks[index].deliverable = deliverable
        lastEvent = "已驗收「\(projectTasks[index].title)」成果"
    }

    /// 在群組內提醒進度較慢的成員；MVP 先記錄系統事件，之後可接推播與觸覺回饋。
    func poke(memberID: UUID, in groupID: UUID, style: PokeStyle) {
        guard let group = groups.first(where: { $0.id == groupID }), group.memberIDs.contains(memberID),
              let member = members.first(where: { $0.id == memberID }) else { return }
        lastEvent = "用「\(style.rawValue)」戳了 \(member.name)"
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

/// 暫時相容舊 View 名稱；新檔案一律使用 AppStore。
typealias GroupBombModel = AppStore
