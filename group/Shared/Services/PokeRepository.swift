import FirebaseAuth
import FirebaseFunctions
import FirebaseMessaging
import Foundation
import UIKit

enum PokeRepositoryError: LocalizedError {
    case notAuthenticated
    case notGroupMember
    case invalidRecipient
    case network
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "請先登入再戳隊友。"
        case .notGroupMember: "你必須先加入此群組才能戳隊友。"
        case .invalidRecipient: "只能戳同一群組的其他成員。"
        case .network: "網路連線異常，請確認網路後重試。"
        case .unavailable: "目前無法送出戳戳，請稍後再試。"
        }
    }
}

@MainActor
final class PokeRepository {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "asia-east1")) {
        self.functions = functions
    }

    func send(groupID: String, recipientUID: String, style: PokeStyle) async throws {
        guard Auth.auth().currentUser != nil else { throw PokeRepositoryError.notAuthenticated }
        do {
            _ = try await functions.httpsCallable("sendPoke").call([
                "groupID": groupID,
                "recipientUID": recipientUID,
                "style": style.rawValue,
            ])
        } catch {
            throw Self.map(error)
        }
    }

    func registerCurrentDevice() async throws {
        guard Auth.auth().currentUser != nil else { throw PokeRepositoryError.notAuthenticated }
        let token = try await Messaging.messaging().token()
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        do {
            _ = try await functions.httpsCallable("registerPokeDevice").call([
                "deviceID": deviceID,
                "token": token,
            ])
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> PokeRepositoryError {
        let nsError = error as NSError
        let reason = (nsError.userInfo["details"] as? [String: Any])?["reason"] as? String
        switch reason {
        case "not-authenticated": return .notAuthenticated
        case "not-group-member": return .notGroupMember
        case "invalid-recipient": return .invalidRecipient
        default: break
        }
        switch nsError.code {
        case 16: return .notAuthenticated
        case 7: return .notGroupMember
        case 3, 9: return .invalidRecipient
        case 14, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return .network
        default: return .unavailable
        }
    }
}
