import Foundation

/// 開發測試模式使用的完整資料快照；正式模式不會載入這些內容。
struct DemoDataSnapshot {
    let currentUserID: UUID
    let userName: String
    let profileName: String
    let profileRole: String
    let profileBio: String
    let profileAvatarSymbol: String
    let groups: [Group]
    let members: [Member]
    let projectTasks: [ProjectTask]
    let peerReviews: [PeerReview]
    let tasks: [MissionTask]
    let agents: [Agent]
    let radar: [RadarMetric]
}

enum DemoData {
    static let currentUserID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    static func make(now: Date = .now) -> DemoDataSnapshot {
        let me = Member(id: currentUserID, name: "我", role: .leader, avatarSymbol: "person.fill")
        let xiaoYu = Member(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            name: "小宇",
            role: .member,
            avatarSymbol: "person.fill"
        )
        let miMi = Member(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            name: "米米",
            role: .member,
            avatarSymbol: "person.fill"
        )
        let aKai = Member(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
            name: "阿凱",
            role: .member,
            avatarSymbol: "person.fill"
        )
        let allMembers = [me, xiaoYu, miMi, aKai]

        let activeGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
        let summerCampGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
        let circuitGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
        let maicGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000104")!
        let activeDeadline = now.addingTimeInterval(48 * 60 * 60)
        let summerCampDeadline = now.addingTimeInterval(-24 * 60 * 60)
        let circuitDeadline = now.addingTimeInterval(-12 * 60 * 60)
        let maicDeadline = now.addingTimeInterval(-7 * 24 * 60 * 60)

        var nextTaskID = 1
        func makeTask(
            groupID: UUID,
            title: String,
            detail: String,
            weight: Int,
            ownerMemberID: UUID,
            progress: Int,
            deadline: Date
        ) -> ProjectTask {
            var subtasks: [Subtask] = []
            if progress > 0 {
                subtasks.append(Subtask(id: UUID(), title: "已完成工作", isComplete: true, weight: progress))
            }
            if progress < 100 {
                subtasks.append(Subtask(id: UUID(), title: "待完成工作", isComplete: false, weight: 100 - progress))
            }

            let taskID = UUID(
                uuidString: String(format: "00000000-0000-4000-8001-%012d", nextTaskID)
            )!
            nextTaskID += 1

            return ProjectTask(
                id: taskID,
                groupID: groupID,
                title: title,
                detail: detail,
                weight: weight,
                ownerMemberID: ownerMemberID,
                subtasks: subtasks,
                deliverable: nil,
                deadline: deadline,
                createdByMemberID: me.id,
                createdAt: now
            )
        }

        let activeTasks = [
            makeTask(groupID: activeGroupID, title: "蒐集市場數據", detail: "找到 3 個可信來源", weight: 25, ownerMemberID: me.id, progress: 52, deadline: activeDeadline),
            makeTask(groupID: activeGroupID, title: "製作競品分析", detail: "完成比較矩陣", weight: 30, ownerMemberID: xiaoYu.id, progress: 30, deadline: activeDeadline),
            makeTask(groupID: activeGroupID, title: "簡報視覺統整", detail: "統一圖表與版面", weight: 25, ownerMemberID: miMi.id, progress: 52, deadline: activeDeadline),
            makeTask(groupID: activeGroupID, title: "結論與建議", detail: "收斂成 3 個重點", weight: 20, ownerMemberID: aKai.id, progress: 95, deadline: activeDeadline)
        ]
        let summerCampTasks = [
            makeTask(groupID: summerCampGroupID, title: "完成 App 核心流程", detail: "整合主要操作流程", weight: 30, ownerMemberID: me.id, progress: 100, deadline: summerCampDeadline),
            makeTask(groupID: summerCampGroupID, title: "整理 SwiftUI 畫面", detail: "完成介面與互動", weight: 25, ownerMemberID: xiaoYu.id, progress: 100, deadline: summerCampDeadline),
            makeTask(groupID: summerCampGroupID, title: "執行功能測試", detail: "確認 Demo 流程", weight: 25, ownerMemberID: miMi.id, progress: 100, deadline: summerCampDeadline),
            makeTask(groupID: summerCampGroupID, title: "準備成果發表", detail: "完成展示內容", weight: 20, ownerMemberID: aKai.id, progress: 100, deadline: summerCampDeadline)
        ]
        let circuitTasks = [
            makeTask(groupID: circuitGroupID, title: "設計電路圖", detail: "完成線路規劃", weight: 30, ownerMemberID: me.id, progress: 73, deadline: circuitDeadline),
            makeTask(groupID: circuitGroupID, title: "焊接電路板", detail: "完成元件焊接", weight: 25, ownerMemberID: xiaoYu.id, progress: 73, deadline: circuitDeadline),
            makeTask(groupID: circuitGroupID, title: "量測輸出訊號", detail: "記錄量測結果", weight: 25, ownerMemberID: miMi.id, progress: 73, deadline: circuitDeadline),
            makeTask(groupID: circuitGroupID, title: "整理實驗報告", detail: "彙整結果與討論", weight: 20, ownerMemberID: aKai.id, progress: 73, deadline: circuitDeadline)
        ]
        let maicTasks = [
            makeTask(groupID: maicGroupID, title: "建立競賽模型", detail: "完成模型訓練", weight: 35, ownerMemberID: me.id, progress: 100, deadline: maicDeadline),
            makeTask(groupID: maicGroupID, title: "整理訓練資料", detail: "完成資料清理", weight: 25, ownerMemberID: xiaoYu.id, progress: 100, deadline: maicDeadline),
            makeTask(groupID: maicGroupID, title: "驗證模型表現", detail: "完成評估指標", weight: 25, ownerMemberID: miMi.id, progress: 100, deadline: maicDeadline),
            makeTask(groupID: maicGroupID, title: "完成競賽簡報", detail: "整理成果說明", weight: 15, ownerMemberID: aKai.id, progress: 100, deadline: maicDeadline)
        ]
        let allProjectTasks = activeTasks + summerCampTasks + circuitTasks + maicTasks

        func completedReviews(groupID: UUID, deadline: Date, reviewers: [Member]) -> [PeerReview] {
            reviewers.flatMap { reviewer in
                allMembers.compactMap { reviewee in
                    guard reviewer.id != reviewee.id else { return nil }
                    return PeerReview(
                        id: UUID(),
                        groupID: groupID,
                        reviewerMemberID: reviewer.id,
                        revieweeMemberID: reviewee.id,
                        taskCompletionScore: 4,
                        discussionScore: 4,
                        collaborationScore: 4,
                        ideaScore: 4,
                        reliabilityScore: 4,
                        comment: reviewer.id == xiaoYu.id
                            ? "合作時很可靠，也會主動回報進度。"
                            : reviewer.id == miMi.id
                                ? "討論時提供了很實用的想法。"
                                : "遇到問題時願意一起找解法。",
                        submittedAt: deadline.addingTimeInterval(60)
                    )
                }
            }
        }

        let groups = [
            Group(id: activeGroupID, name: "期末報告拆彈小隊", deadline: activeDeadline, memberIDs: allMembers.map(\.id), taskIDs: activeTasks.map(\.id), inviteCode: "BOMB52"),
            Group(id: summerCampGroupID, name: "iOS Summer Camp", deadline: summerCampDeadline, memberIDs: allMembers.map(\.id), taskIDs: summerCampTasks.map(\.id), inviteCode: "IOS100"),
            Group(id: circuitGroupID, name: "電子電路期末", deadline: circuitDeadline, memberIDs: allMembers.map(\.id), taskIDs: circuitTasks.map(\.id), inviteCode: "EE0073"),
            Group(id: maicGroupID, name: "MAIC 比賽", deadline: maicDeadline, memberIDs: allMembers.map(\.id), taskIDs: maicTasks.map(\.id), inviteCode: "MAIC24")
        ]

        return DemoDataSnapshot(
            currentUserID: me.id,
            userName: me.name,
            profileName: "Peach",
            profileRole: "拆彈手",
            profileBio: "一起把死線拆掉。",
            profileAvatarSymbol: "person.fill",
            groups: groups,
            members: allMembers,
            projectTasks: allProjectTasks,
            peerReviews: completedReviews(groupID: summerCampGroupID, deadline: summerCampDeadline, reviewers: [xiaoYu, miMi])
                + completedReviews(groupID: maicGroupID, deadline: maicDeadline, reviewers: allMembers),
            tasks: [
                MissionTask(title: "蒐集市場數據", detail: "找到 3 個可信來源", points: 120, owner: nil),
                MissionTask(title: "製作競品分析", detail: "完成比較矩陣", points: 180, owner: "小宇"),
                MissionTask(title: "簡報視覺統整", detail: "統一圖表與版面", points: 150, owner: nil),
                MissionTask(title: "結論與建議", detail: "收斂成 3 個重點", points: 200, owner: "阿凱")
            ],
            agents: [
                Agent(name: "我", role: "拆彈手", progress: 62, status: "正在攻堅"),
                Agent(name: "小宇", role: "情報員", progress: 78, status: "火力全開"),
                Agent(name: "米米", role: "分析師", progress: 28, status: "訊號微弱"),
                Agent(name: "阿凱", role: "簡報手", progress: 43, status: "緩慢推進")
            ],
            radar: [
                RadarMetric(title: "準時", score: 0.82),
                RadarMetric(title: "品質", score: 0.75),
                RadarMetric(title: "溝通", score: 0.92),
                RadarMetric(title: "救火", score: 0.68),
                RadarMetric(title: "合作", score: 0.88)
            ]
        )
    }
}
