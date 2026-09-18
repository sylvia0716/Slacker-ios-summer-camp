import Foundation

struct DeadlineReminder: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
    let groupID: UUID
    let taskID: UUID?
    var opensPeerReview = false
}

enum DeadlineReminderPlan {
    static let identifierPrefix = "deadline-reminder."

    static func make(groups: [Group], tasks: [ProjectTask], memberID: UUID,
                     uid: String, now: Date, completedReviewGroupIDs: Set<UUID>? = nil) -> [DeadlineReminder] {
        let joinedGroups = groups.filter { $0.memberIDs.contains(memberID) }
        let groupIDs = Set(joinedGroups.map(\.id))
        var reminders: [DeadlineReminder] = []
        let offsets: [(hours: Int, label: String)] = [(24, "24 小時"), (1, "1 小時")]

        func append(id: UUID, name: String, deadline: Date, groupID: UUID, isTask: Bool) {
            guard deadline < .distantFuture else { return }
            for offset in offsets {
                let fireDate = deadline.addingTimeInterval(-Double(offset.hours) * 3600)
                guard fireDate > now else { continue }
                let kind = isTask ? "task" : "project"
                reminders.append(DeadlineReminder(
                    id: "\(identifierPrefix)\(uid).\(kind).\(id.uuidString).\(offset.hours)",
                    title: isTask ? "我的任務即將到期" : "專案倒數提醒",
                    body: "「\(name)」將在 \(offset.label)後截止。",
                    fireDate: fireDate, groupID: groupID, taskID: isTask ? id : nil
                ))
            }
        }

        for group in joinedGroups {
            append(id: group.id, name: group.name, deadline: group.deadline, groupID: group.id, isTask: false)
            if let completedReviewGroupIDs,
               !completedReviewGroupIDs.contains(group.id),
               group.memberIDs.contains(where: { $0 != memberID }), group.deadline < .distantFuture {
                for hours in [0, 24] {
                    let fireDate = group.deadline.addingTimeInterval(Double(hours) * 3600)
                    guard fireDate > now else { continue }
                    reminders.append(DeadlineReminder(
                        id: "\(identifierPrefix)\(uid).review.\(group.id.uuidString).\(hours)",
                        title: hours == 0 ? "專案已結束，來幫隊友評分吧！" : "別忘了完成隊友互評",
                        body: hours == 0 ? "「\(group.name)」已開放互評。" : "「\(group.name)」的隊友互評，抽空完成吧。",
                        fireDate: fireDate, groupID: group.id, taskID: nil, opensPeerReview: true
                    ))
                }
            }
        }
        for task in tasks where task.ownerMemberID == memberID && groupIDs.contains(task.groupID)
            && !task.isCompleted && task.cloudStatus != .completed {
            append(id: task.id, name: task.title, deadline: task.deadline, groupID: task.groupID, isTask: true)
        }
        return reminders.sorted {
            $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate
        }
    }
}
