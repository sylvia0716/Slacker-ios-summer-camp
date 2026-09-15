import FirebaseAuth
import FirebaseFunctions
import Foundation
import Observation

struct GroupJoinResult: Sendable {
    let group: CloudGroupSummary
    let firebaseUID: String
    let wasAlreadyMember: Bool
}

struct GroupCreationResult: Sendable {
    let group: CloudGroupSummary
    let firebaseUID: String
}

enum GroupJoinError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidCode
    case inactiveCode
    case expiredCode
    case alreadyMember
    case network
    case permissionDenied
    case invalidGroupData
    case unavailable
    case invalidName
    case invalidDeadline

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "請先登入再加入群組。"
        case .invalidCode: "找不到這組邀請碼，請確認後再試一次。"
        case .inactiveCode: "這組邀請碼已失效。"
        case .expiredCode: "這組邀請碼已過期。"
        case .alreadyMember: "你已經是這個群組的成員。"
        case .network: "網路連線異常，請確認網路後再試。"
        case .permissionDenied: "目前帳號沒有加入這個群組的權限。"
        case .invalidGroupData: "群組資料格式不正確，請聯絡群組建立者。"
        case .unavailable: "目前無法加入群組，請稍後再試。"
        case .invalidName: "請輸入 60 個字以內的群組名稱。"
        case .invalidDeadline: "群組期限必須晚於目前時間。"
        }
    }
}

@MainActor
final class GroupJoinRepository {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "asia-east1")) {
        self.functions = functions
    }

    func join(inviteCode: String) async throws -> GroupJoinResult {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw GroupJoinError.notAuthenticated
        }

        let normalizedCode = Self.normalize(inviteCode)
        guard GroupInviteCode.isValid(normalizedCode) else { throw GroupJoinError.invalidCode }

        do {
            let callableResult = try await functions
                .httpsCallable("joinGroupByInviteCode")
                .call(["inviteCode": normalizedCode])
            let payload = try Self.dictionary(from: callableResult.data)
            let group = try Self.group(from: payload["group"])
            let wasAlreadyMember = payload["alreadyMember"] as? Bool ?? false
            guard Auth.auth().currentUser?.uid == uid else { throw GroupJoinError.notAuthenticated }
            return GroupJoinResult(
                group: group,
                firebaseUID: uid,
                wasAlreadyMember: wasAlreadyMember
            )
        } catch let error as GroupJoinError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func create(name: String, deadline: Date, displayName: String) async throws -> GroupCreationResult {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw GroupJoinError.notAuthenticated
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= 60 else {
            throw GroupJoinError.invalidName
        }
        guard deadline > .now else { throw GroupJoinError.invalidDeadline }

        do {
            let result = try await functions.httpsCallable("createGroup").call([
                "name": normalizedName,
                "deadlineMillis": deadline.timeIntervalSince1970 * 1_000,
                "displayName": String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
            ])
            let payload = try Self.dictionary(from: result.data)
            let group = try Self.group(from: payload["group"])
            guard Auth.auth().currentUser?.uid == uid else {
                throw GroupJoinError.notAuthenticated
            }
            return GroupCreationResult(group: group, firebaseUID: uid)
        } catch let error as GroupJoinError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func fetchAccessibleGroups() async throws -> [CloudGroupSummary] {
        guard Auth.auth().currentUser?.uid != nil else {
            throw GroupJoinError.notAuthenticated
        }

        do {
            let result = try await functions.httpsCallable("listMyGroups").call([:])
            let payload = try Self.dictionary(from: result.data)
            guard let rawGroups = payload["groups"] as? [Any] else {
                throw GroupJoinError.invalidGroupData
            }
            return try rawGroups.map(Self.group(from:))
        } catch let error as GroupJoinError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated static func normalize(_ inviteCode: String) -> String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func dictionary(from value: Any) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw GroupJoinError.invalidGroupData
        }
        return dictionary
    }

    private static func group(from value: Any?) throws -> CloudGroupSummary {
        let data = try dictionary(from: value as Any)
        guard let groupID = data["groupID"] as? String,
              let id = UUID(uuidString: groupID),
              let name = data["name"] as? String,
              !name.isEmpty else {
            throw GroupJoinError.invalidGroupData
        }
        let deadlineMilliseconds = (data["deadlineMillis"] as? NSNumber)?.doubleValue
        let deadline = deadlineMilliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) }
            ?? .distantFuture
        return CloudGroupSummary(
            id: id,
            name: name,
            deadline: deadline,
            inviteCode: (data["inviteCode"] as? String) ?? "",
            documentID: groupID
        )
    }

    private static func map(_ error: Error) -> GroupJoinError {
        let nsError = error as NSError
        let details = nsError.userInfo["details"] as? [String: Any]
        switch details?["reason"] as? String {
        case "not-authenticated": return .notAuthenticated
        case "invite-code-not-found": return .invalidCode
        case "invite-code-inactive": return .inactiveCode
        case "invite-code-expired": return .expiredCode
        case "group-not-found", "invalid-invite-data": return .invalidGroupData
        case "permission-denied": return .permissionDenied
        case "invalid-group-name", "invalid-display-name": return .invalidName
        case "invalid-group-deadline": return .invalidDeadline
        default: break
        }

        switch nsError.code {
        case 16: return .notAuthenticated
        case 3, 5: return .invalidCode
        case 7: return .permissionDenied
        case 9: return .inactiveCode
        case 14, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .network
        default: return .unavailable
        }
    }
}

enum GroupJoinUIState: Equatable {
    case idle
    case joining
    case success(wasAlreadyMember: Bool)
    case failure(GroupJoinError)
}

@MainActor @Observable
final class GroupJoinStore {
    private(set) var state = GroupJoinUIState.idle
    @ObservationIgnored private let repository: GroupJoinRepository

    init() {
        self.repository = GroupJoinRepository()
    }

    init(repository: GroupJoinRepository) {
        self.repository = repository
    }

    var isJoining: Bool { state == .joining }

    func reset() {
        guard !isJoining else { return }
        state = .idle
    }

    func join(inviteCode: String) async -> GroupJoinResult? {
        guard !isJoining else { return nil }
        state = .joining

        do {
            let result = try await repository.join(inviteCode: inviteCode)
            state = .success(wasAlreadyMember: result.wasAlreadyMember)
            return result
        } catch let error as GroupJoinError {
            state = .failure(error)
            return nil
        } catch {
            state = .failure(.unavailable)
            return nil
        }
    }
}
