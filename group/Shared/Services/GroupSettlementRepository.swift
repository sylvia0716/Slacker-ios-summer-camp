import FirebaseAuth
import FirebaseFunctions
import Foundation

enum GroupSettlementError: LocalizedError {
    case notAuthenticated
    case notLeader
    case tasksIncomplete
    case groupNotFound
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: L10n.text("請先登入再結算專案。")
        case .notLeader: L10n.text("只有組長可以提前結算專案。")
        case .tasksIncomplete: L10n.text("所有任務完成後才能提前結算。")
        case .groupNotFound: L10n.text("找不到目前群組。")
        case .invalidResponse, .unavailable: L10n.text("結算失敗，請確認網路後重試。")
        }
    }
}

@MainActor
final class GroupSettlementRepository {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "asia-east1")) {
        self.functions = functions
    }

    func settle(groupID: String) async throws -> Date {
        guard Auth.auth().currentUser != nil else { throw GroupSettlementError.notAuthenticated }
        do {
            let result = try await functions.httpsCallable("settleGroup").call(["groupID": groupID])
            guard let payload = result.data as? [String: Any],
                  let milliseconds = (payload["settledAtMillis"] as? NSNumber)?.doubleValue else {
                throw GroupSettlementError.invalidResponse
            }
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        } catch let error as GroupSettlementError {
            throw error
        } catch {
            let details = (error as NSError).userInfo["details"] as? [String: Any]
            switch details?["reason"] as? String {
            case "not-authenticated": throw GroupSettlementError.notAuthenticated
            case "not-group-leader": throw GroupSettlementError.notLeader
            case "tasks-incomplete", "no-tasks": throw GroupSettlementError.tasksIncomplete
            case "group-not-found": throw GroupSettlementError.groupNotFound
            default: throw GroupSettlementError.unavailable
            }
        }
    }
}
