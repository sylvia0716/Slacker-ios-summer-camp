import Foundation

@MainActor
final class ProfileNicknameRepository {
    struct Client {
        let currentUID: () -> String?
        let saveAccountName: (String) async throws -> Void
        let saveMemberName: (String, String, String) async throws -> Void
    }
    private let client: Client
    init(client: Client) { self.client = client }

    static func normalized(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 60,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw NicknameError.invalid
        }
        return name
    }

    func save(_ value: String, groupIDs: [String]) async throws -> String {
        let name = try Self.normalized(value)
        guard let uid = client.currentUID() else { throw NicknameError.signedOut }
        try await client.saveAccountName(name)
        guard client.currentUID() == uid else { throw NicknameError.accountChanged }
        var failed = false
        for groupID in Set(groupIDs).sorted() {
            guard client.currentUID() == uid else { throw NicknameError.accountChanged }
            do { try await client.saveMemberName(groupID, uid, name) }
            catch { failed = true }
        }
        guard client.currentUID() == uid else { throw NicknameError.accountChanged }
        if failed { throw NicknameError.partial }
        return name
    }
}

enum NicknameError: LocalizedError, Equatable {
    case invalid, signedOut, accountChanged, partial, network
    var errorDescription: String? {
        switch self {
        case .invalid: "暱稱需為 1 至 60 個字元，且不可包含換行或控制字元。"
        case .signedOut: "請先登入再儲存暱稱。"
        case .accountChanged: "帳號已變更，請重新編輯。"
        case .partial: "帳號暱稱已儲存，但部分群組尚未同步。請再次按儲存重試。"
        case .network: "暱稱儲存失敗，請確認網路後重試。"
        }
    }
}
