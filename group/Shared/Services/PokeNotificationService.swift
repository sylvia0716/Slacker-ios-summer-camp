import Foundation
import UserNotifications

/// Delivers the prototype's poke alerts as device notifications.
@MainActor
final class PokeNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func deliver(group: Group, pokeCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "有人在找你"
        content.body = message(for: group.name, pokeCount: pokeCount)
        content.sound = .default
        content.userInfo = ["groupID": group.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "poke-\(group.id.uuidString)-\(pokeCount)",
            content: content,
            trigger: nil
        )
        center.add(request)
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
