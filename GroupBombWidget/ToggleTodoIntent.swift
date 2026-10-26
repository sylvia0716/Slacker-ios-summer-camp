import AppIntents
import WidgetKit

/// Completes a subtask straight from the Home Screen.
///
/// The widget extension has no Firebase access, so the tick is queued in the App Group and
/// replayed by the app the next time it becomes active. Until then the row is hidden from the
/// widget by `WidgetSnapshotStore.loadTodo`, which keeps the tap feeling immediate.
struct ToggleTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete To-Do"
    static let description = IntentDescription("Marks a subtask as done from the widget.")
    static let openAppWhenRun = false

    @Parameter(title: "Subtask ID") var subtaskID: String
    @Parameter(title: "Task ID") var taskID: String

    init() {}

    init(subtaskID: UUID, taskID: UUID) {
        self.subtaskID = subtaskID.uuidString
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let subtask = UUID(uuidString: subtaskID), let task = UUID(uuidString: taskID) else {
            return .result()
        }
        WidgetTodoActionQueue.enqueue(
            WidgetTodoAction(subtaskID: subtask, taskID: task, requestedAt: .now)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConfig.todoWidgetKind)
        return .result()
    }
}
