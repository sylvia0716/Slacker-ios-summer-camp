import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct PokeDeliveryStateTests {
    private func withState(_ body: (PokeDeliveryState, UserDefaults) -> Void) {
        let suite = "PokeDeliveryStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(PokeDeliveryState(defaults: defaults), defaults)
    }

    @Test func firstSnapshotDoesNotReplayHistory() {
        withState { state, _ in
            #expect(state.unseenCount(latestCount: 20, uid: "A", groupID: "one") == 0)
            #expect(state.unseenCount(latestCount: 23, uid: "A", groupID: "one") == 3)
        }
    }

    @Test func emptyGroupStillReceivesFirstPoke() {
        withState { state, _ in
            #expect(state.unseenCount(latestCount: 0, uid: "A", groupID: "one") == 0)
            #expect(state.unseenCount(latestCount: 1, uid: "A", groupID: "one") == 1)
        }
    }

    @Test func failedDeliveryCanRetryWithoutLosingPokes() {
        withState { state, _ in
            state.markHandled(count: 4, uid: "A", groupID: "one")
            #expect(state.unseenCount(latestCount: 7, uid: "A", groupID: "one") == 3)
            // No acknowledgement: a network or notification error must leave the count pending.
            #expect(state.unseenCount(latestCount: 8, uid: "A", groupID: "one") == 4)
            state.markHandled(count: 8, uid: "A", groupID: "one")
            #expect(state.unseenCount(latestCount: 8, uid: "A", groupID: "one") == 0)
        }
    }

    @Test func foregroundAndBackgroundSharePersistentCheckpoint() {
        withState { state, defaults in
            state.markHandled(count: 9, uid: "A", groupID: "one")
            let relaunched = PokeDeliveryState(defaults: defaults)
            #expect(relaunched.unseenCount(latestCount: 9, uid: "A", groupID: "one") == 0)
            #expect(relaunched.unseenCount(latestCount: 11, uid: "A", groupID: "one") == 2)
        }
    }

    @Test func accountsAndGroupsAreIsolated() {
        withState { state, _ in
            state.markHandled(count: 9, uid: "A", groupID: "one")
            #expect(state.unseenCount(latestCount: 30, uid: "B", groupID: "one") == 0)
            #expect(state.unseenCount(latestCount: 50, uid: "A", groupID: "two") == 0)
            #expect(state.unseenCount(latestCount: 10, uid: "A", groupID: "one") == 1)
        }
    }

    @Test func olderCallbackCannotMoveCheckpointBackwards() {
        withState { state, _ in
            state.markHandled(count: 10, uid: "A", groupID: "one")
            state.markHandled(count: 7, uid: "A", groupID: "one")
            #expect(state.unseenCount(latestCount: 10, uid: "A", groupID: "one") == 0)
        }
    }

    @Test func notificationPreferenceSurvivesRelaunch() {
        withState { state, defaults in
            #expect(state.notificationsEnabled)
            state.notificationsEnabled = false
            #expect(!PokeDeliveryState(defaults: defaults).notificationsEnabled)
        }
    }
}
