import FirebaseAuth
import FirebaseFunctions
import Foundation

enum TaskMutationError: LocalizedError {
    case notAuthenticated
    case invalidData
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: L10n.text("請先登入再更新任務。")
        case .invalidData: L10n.text("任務資料格式不正確，請重新載入後再試。")
        case .permissionDenied: L10n.text("目前帳號沒有修改這項任務的權限。")
        case .unavailable: L10n.text("任務同步失敗，請確認網路後再試。")
        }
    }
}

@MainActor
final class TaskMutationRepository {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "asia-east1")) {
        self.functions = functions
    }

    func create(
        expectedUserID: String,
        groupID: String,
        taskID: UUID,
        title: String,
        detail: String,
        assigneeUserID: String,
        subtasks: [Subtask],
        deadline: Date
    ) async throws {
        try requireAuthenticatedUser(expectedUserID)
        do {
            _ = try await functions.httpsCallable("createTask").call([
                "groupID": groupID,
                "taskID": taskID.uuidString.lowercased(),
                "title": title,
                "detail": detail,
                "assigneeUserID": assigneeUserID,
                "subtasks": subtasks.map {
                    ["id": $0.id.uuidString.lowercased(), "title": $0.title]
                },
                "deadlineMillis": deadline.timeIntervalSince1970 * 1_000,
            ])
            try requireAuthenticatedUser(expectedUserID)
        } catch let error as TaskMutationError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func setSubtaskCompletion(
        expectedUserID: String,
        groupID: String,
        taskID: String,
        subtaskID: UUID,
        isComplete: Bool
    ) async throws {
        try requireAuthenticatedUser(expectedUserID)
        do {
            _ = try await functions.httpsCallable("updateSubtask").call([
                "groupID": groupID,
                "taskID": taskID,
                "subtaskID": subtaskID.uuidString.lowercased(),
                "isComplete": isComplete,
            ])
            try requireAuthenticatedUser(expectedUserID)
        } catch let error as TaskMutationError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func update(
        expectedUserID: String,
        groupID: String,
        taskID: String,
        title: String,
        detail: String,
        subtasks: [Subtask],
        deadline: Date
    ) async throws {
        try requireAuthenticatedUser(expectedUserID)
        do {
            _ = try await functions.httpsCallable("updateTask").call([
                "groupID": groupID,
                "taskID": taskID,
                "title": title,
                "detail": detail,
                "subtasks": subtasks.map {
                    ["id": $0.id.uuidString.lowercased(), "title": $0.title]
                },
                "deadlineMillis": deadline.timeIntervalSince1970 * 1_000,
            ])
            try requireAuthenticatedUser(expectedUserID)
        } catch let error as TaskMutationError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func remove(
        expectedUserID: String,
        groupID: String,
        taskID: String
    ) async throws {
        try requireAuthenticatedUser(expectedUserID)
        do {
            _ = try await functions.httpsCallable("deleteTask").call([
                "groupID": groupID,
                "taskID": taskID,
            ])
            try requireAuthenticatedUser(expectedUserID)
        } catch let error as TaskMutationError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    private func requireAuthenticatedUser(_ expectedUserID: String) throws {
        guard Auth.auth().currentUser?.uid == expectedUserID else {
            throw TaskMutationError.notAuthenticated
        }
    }

    private static func map(_ error: Error) -> TaskMutationError {
        let nsError = error as NSError
        let details = nsError.userInfo["details"] as? [String: Any]
        switch details?["reason"] as? String {
        case "not-authenticated": return .notAuthenticated
        case "permission-denied", "not-task-owner": return .permissionDenied
        case "group-not-found", "assignee-not-in-group", "task-not-found",
             "subtask-not-found", "invalid-task-data", "task-deadline-after-group",
             "task-already-exists": return .invalidData
        default: break
        }

        switch nsError.code {
        case 16: return .notAuthenticated
        case 7: return .permissionDenied
        case 3, 5, 6, 9: return .invalidData
        default: return .unavailable
        }
    }
}
