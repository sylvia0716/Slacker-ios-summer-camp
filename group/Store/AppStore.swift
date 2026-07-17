import Foundation
import Observation

/// Legacy prototype task model. Future work: replace with ProjectTask and attach it to a Group.
struct MissionTask: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var points: Int
    var owner: String?
    var deadline: Date
    var subtasks: [Subtask]
    var deliverables: [Deliverable] = []

    var progress: Int {
        guard !subtasks.isEmpty else { return 0 }
        let totalWeight = subtasks.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let completedWeight = subtasks.filter(\.isComplete).reduce(0) { $0 + $1.weight }
        return completedWeight * 100 / totalWeight
    }

    var isComplete: Bool { progress == 100 }
}

/// Legacy prototype member model. Future work: replace with Member and group-scoped roles.
struct Agent: Identifiable {
    let id = UUID()
    var name: String
    var role: String
    var progress: Int
    var isShielded = false
    var status = "待命"
}

/// Input data for the existing peer-review radar.
struct RadarMetric: Identifiable {
    let id = UUID()
    let title: String
    let score: Double
}

/// Available reminder interactions for the current local-only prototype.
enum PokeStyle: String, CaseIterable, Identifiable {
    case gentle = "輕敲"
    case meme = "迷因轟炸"
    case alarm = "警報催命"
    var id: Self { self }
    var icon: String {
        switch self { case .gentle: "hand.tap.fill"; case .meme: "face.smiling.inverse"; case .alarm: "alarm.waves.left.and.right.fill" }
    }
    var message: String {
        switch self { case .gentle: "特工，進度還活著嗎？"; case .meme: "你的進度比校車還難等。"; case .alarm: "紅色警戒！死線正在接近！" }
    }
}

/// Single source of truth for all mock data and mutations in the current prototype.
/// Future work: own Group, ProjectTask, Subtask, Deliverable, chat, and report data here.
@MainActor @Observable
final class AppStore {
    let userName = "我"
    let profileName = "Peach"
    var notificationsEnabled = true
    var groups = [
        Group(
            id: UUID(),
            name: "期末報告拆彈小隊",
            deadline: .now.addingTimeInterval(48 * 60 * 60),
            memberIDs: [],
            taskIDs: []
        )
    ]
    var tasks = [
        MissionTask(
            title: "蒐集市場數據",
            detail: "找到 3 個可信來源",
            points: 120,
            owner: "我",
            deadline: .now.addingTimeInterval(18 * 60 * 60),
            subtasks: [
                Subtask(id: UUID(), title: "整理問卷結果", isComplete: true, weight: 1),
                Subtask(id: UUID(), title: "蒐集競品資料", isComplete: true, weight: 1),
                Subtask(id: UUID(), title: "補上引用來源", isComplete: false, weight: 1)
            ],
            deliverables: [
                Deliverable(id: UUID(), title: "市場資料整理.pdf", url: nil, submittedAt: .now, isApproved: false)
            ]
        ),
        MissionTask(
            title: "製作競品分析",
            detail: "完成比較矩陣",
            points: 180,
            owner: "小宇",
            deadline: .now.addingTimeInterval(30 * 60 * 60),
            subtasks: [Subtask(id: UUID(), title: "建立比較矩陣", isComplete: false, weight: 1)]
        ),
        MissionTask(
            title: "簡報視覺統整",
            detail: "統一圖表與版面",
            points: 150,
            owner: "我",
            deadline: .now.addingTimeInterval(42 * 60 * 60),
            subtasks: [Subtask(id: UUID(), title: "統一簡報樣式", isComplete: false, weight: 1)]
        ),
        MissionTask(
            title: "結論與建議",
            detail: "收斂成 3 個重點",
            points: 200,
            owner: "我",
            deadline: .now.addingTimeInterval(46 * 60 * 60),
            subtasks: [Subtask(id: UUID(), title: "整理三項建議", isComplete: false, weight: 1)]
        )
    ]
    var agents = [
        Agent(name: "我", role: "拆彈手", progress: 62, status: "正在攻堅"),
        Agent(name: "小宇", role: "情報員", progress: 78, status: "火力全開"),
        Agent(name: "米米", role: "分析師", progress: 28, status: "訊號微弱"),
        Agent(name: "阿凱", role: "簡報手", progress: 43, status: "緩慢推進")
    ]
    let radar = [RadarMetric(title: "準時", score: 0.82), RadarMetric(title: "品質", score: 0.75), RadarMetric(title: "溝通", score: 0.92), RadarMetric(title: "救火", score: 0.68), RadarMetric(title: "合作", score: 0.88)]
    var lastEvent = "拆彈小隊已上線"

    var claimedCount: Int { tasks.filter { $0.owner == userName }.count }
    var teamProgress: Int { agents.map(\.progress).reduce(0, +) / agents.count }

    func claim(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].owner == nil else { return }
        tasks[index].owner = userName
        lastEvent = "已認領「\(tasks[index].title)」"
    }

    func toggleSubtask(taskID: UUID, subtaskID: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        tasks[taskIndex].subtasks[subtaskIndex].isComplete.toggle()
        lastEvent = "已更新「\(tasks[taskIndex].title)」進度"
    }

    func addMockDeliverable(to taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].deliverables.append(
            Deliverable(id: UUID(), title: "新增成果連結", url: URL(string: "https://example.com"), submittedAt: .now, isApproved: false)
        )
        lastEvent = "成果已送出，等待驗收"
    }

    func poke(agentID: UUID, style: PokeStyle) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        lastEvent = "用「\(style.rawValue)」戳了 \(agents[index].name)"
    }

    func shield(minutes: Int, note: String) {
        guard let index = agents.firstIndex(where: { $0.name == userName }) else { return }
        agents[index].isShielded = true
        agents[index].status = "護盾 \(minutes) 分鐘｜\(note)"
        agents[index].progress = min(100, agents[index].progress + 5)
        lastEvent = "護盾啟動，隊友看得到你在做了"
    }
}

/// Temporary compatibility name while feature views migrate to AppStore.
typealias GroupBombModel = AppStore
