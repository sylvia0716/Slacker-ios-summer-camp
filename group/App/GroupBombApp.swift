import SwiftUI
import UIKit
import UserNotifications
import FirebaseAppCheck
import FirebaseCore
import FirebaseMessaging
import OSLog

/// Application entry point. It deliberately only wires the root view.
@main
struct GroupBombApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

/// Keeps poke notifications visible while the app is open, so the prototype is testable in-app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    private let logger = Logger(subsystem: "con.sylvia.group", category: "Firebase")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            #if DEBUG
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
            #else
            AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
            #endif
            FirebaseApp.configure()
        } else {
            logger.error("Firebase was not configured because GoogleService-Info.plist is missing from the group app target.")
        }

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        PokeBackgroundRefresh.shared.register()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard fcmToken != nil else { return }
        NotificationCenter.default.post(name: .pokePushTokenUpdated, object: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if PokeNotificationService.reception(from: notification) != nil,
           !PokeDeliveryState.shared.receivesPokes {
            completionHandler([])
            return
        }
        announcePokeReception(for: notification)
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let destination = ReviewNotificationDestination(userInfo: response.notification.request.content.userInfo) {
            Task { @MainActor in ReviewNotificationRouter.shared.pending = destination }
        }
        announcePokeReception(for: response.notification)
        completionHandler()
    }

    private func announcePokeReception(for notification: UNNotification) {
        guard PokeDeliveryState.shared.receivesPokes,
              let reception = PokeNotificationService.reception(from: notification) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pokeReceived, object: reception)
        }
    }
}
