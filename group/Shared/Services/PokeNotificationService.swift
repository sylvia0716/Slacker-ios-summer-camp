import Foundation
import UIKit
import UserNotifications

struct PokeReception: Equatable {
    let groupName: String
    let pokeCount: Int
    let style: PokeStyle

    init(groupName: String, pokeCount: Int, style: PokeStyle) {
        self.groupName = groupName
        self.pokeCount = pokeCount
        self.style = pokeCount >= 15 ? .alarm : style
    }
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

    func cancelPendingPokes() {
        Task {
            let pending = await center.pendingNotificationRequests()
            guard !PokeDeliveryState.shared.receivesPokes else { return }
            center.removePendingNotificationRequests(withIdentifiers:
                pending.filter { $0.identifier.hasPrefix("poke-") }.map(\.identifier))
        }
    }

    func deliver(group: Group, pokeCount: Int, style: PokeStyle) {
        guard PokeDeliveryState.shared.receivesPokes else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.text("有人在找你")
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
        guard PokeDeliveryState.shared.receivesPokes else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.text("隊友在找你")
        content.body = L10n.format("你在「{0}」又被戳了 {1} 下！", String(describing: reception.groupName), String(describing: unseenCount))
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
            L10n.format("你被{0}的隊員戳了{1} 下！", String(describing: groupName), String(describing: pokeCount))
        case 5...9:
            L10n.text("你的組員一直在戳你‼️快回來啦🫨")
        default:
            L10n.text("檢舉雷包，人人有責😤")
        }
    }
}
