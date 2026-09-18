import Foundation
import UIKit
import UserNotifications

struct PokeReception: Equatable {
    let groupName: String
    let pokeCount: Int
    let style: PokeStyle
}

extension Notification.Name {
    static let pokeReceived = Notification.Name("pokeReceived")
    static let pokePushTokenUpdated = Notification.Name("pokePushTokenUpdated")
    static let notificationAuthorizationUpdated = Notification.Name("notificationAuthorizationUpdated")
}

/// Delivers the prototype's poke alerts as device notifications.
@MainActor
final class PokeNotificationService {
    private let center = UNUserNotificationCenter.current()

    private enum UserInfoKey {
        static let groupID = "groupID"
        static let groupName = "groupName"
        static let pokeCount = "pokeCount"
        static let style = "style"
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                NotificationCenter.default.post(name: .notificationAuthorizationUpdated, object: nil)
            }
        }
    }

    func deliver(group: Group, pokeCount: Int, style: PokeStyle) {
        let content = UNMutableNotificationContent()
        content.title = "有人在找你"
        content.body = message(for: group.name, pokeCount: pokeCount)
        content.sound = .default
        content.userInfo = [
            UserInfoKey.groupID: group.id.uuidString,
            UserInfoKey.groupName: group.name,
            UserInfoKey.pokeCount: pokeCount,
            UserInfoKey.style: style.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "poke-\(group.id.uuidString)-\(pokeCount)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func deliverSummary(reception: PokeReception, unseenCount: Int, uid: String, groupID: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "隊友在找你"
        content.body = "你在「\(reception.groupName)」又被戳了 \(unseenCount) 下！"
        content.sound = .default
        content.userInfo = [
            UserInfoKey.groupID: groupID,
            UserInfoKey.groupName: reception.groupName,
            UserInfoKey.pokeCount: reception.pokeCount,
            UserInfoKey.style: reception.style.rawValue
        ]
        try await center.add(UNNotificationRequest(
            identifier: "poke-summary-\(uid)-\(groupID)-\(reception.pokeCount)",
            content: content,
            trigger: nil
        ))
    }

    nonisolated static func reception(from notification: UNNotification) -> PokeReception? {
        let userInfo = notification.request.content.userInfo
        guard let groupName = userInfo[UserInfoKey.groupName] as? String,
              let pokeCount = (userInfo[UserInfoKey.pokeCount] as? Int)
                ?? (userInfo[UserInfoKey.pokeCount] as? String).flatMap(Int.init),
              pokeCount > 0,
              let styleRawValue = userInfo[UserInfoKey.style] as? String,
              let style = PokeStyle(rawValue: styleRawValue) else { return nil }

        return PokeReception(groupName: groupName, pokeCount: pokeCount, style: style)
    }

    private func message(for groupName: String, pokeCount: Int) -> String {
        switch pokeCount {
        case 1...4:
            "你被\(groupName)的隊員戳了\(pokeCount) 下！"
        case 5...9:
            "你的組員一直在戳你‼️快回來啦🫨"
        default:
            "檢舉雷包，人人有責😤"
        }
    }
}
