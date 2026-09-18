import BackgroundTasks
import FirebaseAuth
import FirebaseCore
import OSLog
import UIKit
import UserNotifications

@MainActor
final class PokeBackgroundRefresh {
    static let shared = PokeBackgroundRefresh()
    static let identifier = "con.sylvia.group.poke-refresh"
    // A requested earliest start, not an iOS-guaranteed refresh interval.
    static let minimumDelay: TimeInterval = 15 * 60
    private let logger = Logger(subsystem: "con.sylvia.group", category: "PokeBackgroundRefresh")

    func register() {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.identifier, using: .main
        ) { task in
            Task { @MainActor in
                self.run(task)
            }
        }
        if !registered { logger.error("Could not register poke background refresh") }
    }

    func schedule() {
        guard FirebaseApp.app() != nil,
              Auth.auth().currentUser != nil,
              PokeDeliveryState.shared.notificationsEnabled else {
            cancel()
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.minimumDelay)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled poke refresh no earlier than 15 minutes from now")
        } catch {
            logger.error("Could not schedule poke refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
    }

    private func run(_ task: BGTask) {
        schedule()
        var completed = false
        let finish: (Bool) -> Void = { success in
            guard !completed else { return }
            completed = true
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        }
        let operation = Task { @MainActor in
            do {
                try await self.checkForPokes()
                self.logger.info("Poke background refresh completed")
                finish(!Task.isCancelled)
            } catch {
                self.logger.error("Poke refresh failed: \(error.localizedDescription, privacy: .public)")
                finish(false)
            }
        }
        task.expirationHandler = {
            operation.cancel()
            Task { @MainActor in finish(false) }
        }
    }

    /// Uses server reads; an offline/cache result must never consume an unseen poke.
    func checkForPokes() async throws {
        guard FirebaseApp.app() != nil,
              let uid = Auth.auth().currentUser?.uid,
              PokeDeliveryState.shared.notificationsEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let groups = try await GroupJoinRepository().fetchAccessibleGroups()
        let repository = PokeRepository()
        var firstError: Error?

        for group in groups {
            try Task.checkCancellation()
            guard Auth.auth().currentUser?.uid == uid,
                  PokeDeliveryState.shared.notificationsEnabled,
                  UIApplication.shared.applicationState == .background else { return }
            do {
                let reception = try await repository.latestIncomingPoke(groupID: group.pathID, recipientUID: uid)
                try Task.checkCancellation()
                guard Auth.auth().currentUser?.uid == uid,
                      PokeDeliveryState.shared.notificationsEnabled,
                      UIApplication.shared.applicationState == .background else { return }
                let latestCount = reception?.pokeCount ?? 0
                let unseen = PokeDeliveryState.shared.unseenCount(
                    latestCount: latestCount, uid: uid, groupID: group.pathID
                )
                guard unseen > 0, let reception else { continue }
                try await PokeNotificationService().deliverSummary(
                    reception: reception, unseenCount: unseen, uid: uid, groupID: group.pathID
                )
                // Only acknowledge after the system accepts the notification request.
                PokeDeliveryState.shared.markHandled(count: latestCount, uid: uid, groupID: group.pathID)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
