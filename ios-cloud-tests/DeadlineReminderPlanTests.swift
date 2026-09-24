import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct DeadlineReminderPlanTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let memberID = UUID()

    func group(hours: Double = 48) -> Group {
        Group(id: UUID(), name: "期末專案", deadline: now.addingTimeInterval(hours * 3600),
              memberIDs: [memberID], taskIDs: [], inviteCode: "TEST01")
    }

    func task(in group: Group) -> ProjectTask {
        ProjectTask(id: UUID(), groupID: group.id, title: "完成簡報", detail: "", weight: 100,
            ownerMemberID: memberID,
            subtasks: [Subtask(id: UUID(), title: "整理內容", isComplete: false, weight: 100)],
            deliverable: nil, deadline: now.addingTimeInterval(36 * 3600))
    }

    func plan(_ groups: [Group], _ tasks: [ProjectTask], uid: String = "A") -> [DeadlineReminder] {
        DeadlineReminderPlan.make(groups: groups, tasks: tasks, memberID: memberID, uid: uid, now: now)
    }

    @Test func schedulesBothOffsetsInChronologicalOrder() {
        let group = group()
        let task = task(in: group)
        let result = plan([group], [task])
        #expect(result.count == 4)
        #expect(result.map(\.fireDate) == [12, 24, 35, 47].map { now.addingTimeInterval(Double($0) * 3600) })
        #expect(result.filter { $0.taskID == task.id }.count == 2)
    }

    @Test func doesNotSendMissedOrExpiredReminders() {
        #expect(plan([group(hours: 2)], []).count == 1)
        #expect(plan([group(hours: 0.5)], []).isEmpty)
        #expect(plan([group(hours: -1)], []).isEmpty)
    }

    @Test func completedUnassignedAndOtherPeoplesTasksAreExcluded() {
        let group = group()
        var task = task(in: group)
        task.subtasks[0].isComplete = true
        #expect(plan([group], [task]).allSatisfy { $0.taskID == nil })
        task.subtasks[0].isComplete = false
        task.ownerMemberID = nil
        #expect(plan([group], [task]).allSatisfy { $0.taskID == nil })
        task.ownerMemberID = UUID()
        #expect(plan([group], [task]).allSatisfy { $0.taskID == nil })
    }

    @Test func leavingGroupRemovesItsReminders() {
        var group = group()
        let task = task(in: group)
        group.memberIDs = []
        #expect(plan([group], [task]).isEmpty)
        #expect(plan([], [task]).isEmpty)
    }

    @Test func deadlineAndTitleChangesKeepReplacementIdentifiers() {
        let group = group()
        var task = task(in: group)
        let old = plan([group], [task]).filter { $0.taskID != nil }
        task.deadline = task.deadline.addingTimeInterval(3600)
        task.title = "更新後的簡報"
        let new = plan([group], [task]).filter { $0.taskID != nil }
        #expect(old.map(\.id) == new.map(\.id))
        #expect(new[0].fireDate == old[0].fireDate.addingTimeInterval(3600))
        #expect(new[0].body.contains(task.title))
        #expect(Set(plan([group], [task], uid: "B").map(\.id)).isDisjoint(with: plan([group], [task]).map(\.id)))
    }

    @Test func noDeadlineAndCloudCompletedTasksAreExcluded() {
        let group = group()
        var task = task(in: group)
        task.deadline = .distantFuture
        #expect(plan([group], [task]).allSatisfy { $0.taskID == nil })
        task.deadline = group.deadline
        task.cloudStatus = .completed
        #expect(plan([group], [task]).allSatisfy { $0.taskID == nil })
    }

    @Test func configuredTimeMovesDeadlineRemindersToChosenClockTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let group = group()
        let result = DeadlineReminderPlan.make(
            groups: [group],
            tasks: [],
            memberID: memberID,
            uid: "A",
            now: now,
            reminderTime: DateComponents(hour: 9, minute: 30),
            calendar: calendar
        )
        #expect(!result.isEmpty)
        #expect(result.allSatisfy {
            let components = calendar.dateComponents([.hour, .minute], from: $0.fireDate)
            return components.hour == 9 && components.minute == 30
        })
        #expect(result.allSatisfy { $0.fireDate < group.deadline })
    }

    @Test(arguments: [0, 30, 59])
    func midnightDeadlinesHaveOneReminderPerItem(minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22))!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 0, minute: minute))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9))!
        var group = group()
        group.deadline = deadline
        var first = task(in: group)
        first.deadline = deadline
        var second = task(in: group)
        second.deadline = deadline
        let result = DeadlineReminderPlan.make(groups: [group], tasks: [first, second],
            memberID: memberID, uid: "A", now: start,
            reminderTime: DateComponents(hour: 9, minute: 0), calendar: calendar)

        #expect(result.count == 3)
        #expect(result.filter { $0.taskID == nil }.count == 1)
        #expect(result.filter { $0.taskID == first.id }.count == 1)
        #expect(result.filter { $0.taskID == second.id }.count == 1)
        #expect(result.allSatisfy { $0.fireDate == expected })
        // Retain an existing identifier so reconciliation removes only the duplicate request.
        #expect(result.allSatisfy { $0.id.hasSuffix(".24") })
    }

    @Test func configuredRemindersOnDifferentDaysArePreserved() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22))!
        var group = group()
        group.deadline = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 18))!
        let result = DeadlineReminderPlan.make(groups: [group], tasks: [], memberID: memberID,
            uid: "A", now: start, reminderTime: DateComponents(hour: 9, minute: 0), calendar: calendar)
        #expect(result.map(\.fireDate) == [23, 24].map {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: $0, hour: 9))!
        })
    }

}
