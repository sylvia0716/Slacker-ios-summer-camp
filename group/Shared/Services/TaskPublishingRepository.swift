import FirebaseAuth
import FirebaseFunctions
import Foundation

enum TaskPublishingError: LocalizedError {
    case notAuthenticated
    case notGroupMember
    case groupNotFound
    case assigneeNotInGroup
    case invalidTask
    case network
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "請先登入再發布任務。"
        case .notGroupMember: "你必須先加入此群組才能發布任務。"
        case .groupNotFound: "找不到目前群組。"
        case .assigneeNotInGroup: "負責人必須是目前群組成員。"
        case .invalidTask: "任務資料不正確，請確認名稱與截止時間。"
        case .network: "網路連線異常，請確認網路後重試。"
        case .unavailable: "目前無法發布任務，請稍後再試。"
        }
    }
}

@MainActor
final class TaskPublishingRepository {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "asia-east1")) {
        self.functions = functions
    }

    func publish(groupID: String, title: String, detail: String, assigneeUID: String, deadline: Date) async throws {
        guard Auth.auth().currentUser != nil else { throw TaskPublishingError.notAuthenticated }

        do {
            _ = try await functions.httpsCallable("createTask").call([
                "groupID": groupID,
                "title": title,
                "detail": detail,
                "assigneeUID": assigneeUID,
                "deadlineMillis": deadline.timeIntervalSince1970 * 1_000,
            ])
        } catch let error as TaskPublishingError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> TaskPublishingError {
        let nsError = error as NSError
        let details = nsError.userInfo["details"] as? [String: Any]
        switch details?["reason"] as? String {
        case "not-authenticated": return .notAuthenticated
        case "not-group-member": return .notGroupMember
        case "group-not-found": return .groupNotFound
        case "assignee-not-member": return .assigneeNotInGroup
        case "invalid-task": return .invalidTask
        default: break
        }

        switch nsError.code {
        case 16: return .notAuthenticated
        case 7: return .notGroupMember
        case 5: return .groupNotFound
        case 3, 9: return .invalidTask
        case 14, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return .network
        default: return .unavailable
        }
    }
}
