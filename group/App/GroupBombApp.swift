import SwiftUI
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging
import FirebaseStorage
import OSLog
import RevenueCat

/// Application entry point. It deliberately only wires the root view.
@main
struct GroupBombApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-preview-smart-agenda") {
                SmartAgendaPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-preview-entry-animation") {
                BombEntryAnimationPreview()
            } else {
                AppRootView()
            }
            #else
            AppRootView()
            #endif
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
        #if DEBUG
        Purchases.configure(withAPIKey: "test_CfkQYcYBQWfDqAEBkeFlMYKVUPF")
        #endif
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            #if DEBUG
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
            #else
            AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
            #endif
            FirebaseApp.configure()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-use-firebase-emulators") {
                Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
                Firestore.firestore().useEmulator(withHost: "127.0.0.1", port: 8080)
                Functions.functions(region: "asia-east1").useEmulator(withHost: "127.0.0.1", port: 5001)
                Storage.storage().useEmulator(withHost: "127.0.0.1", port: 9199)
            }
            #endif
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
        if let reception = PokeNotificationService.reception(from: notification),
           !PokeDeliveryState.shared.receivesPokes
            || !PokeDeliveryState.accepts(recipientUID: reception.recipientUID,
                                          currentUID: Auth.auth().currentUser?.uid) {
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
              let reception = PokeNotificationService.reception(from: notification),
              PokeDeliveryState.accepts(recipientUID: reception.recipientUID,
                                        currentUID: Auth.auth().currentUser?.uid) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pokeReceived, object: reception)
        }
    }
}
