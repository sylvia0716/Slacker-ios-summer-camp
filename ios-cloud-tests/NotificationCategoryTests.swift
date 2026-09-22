import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct NotificationCategoryTests {
    @Test func preferencesSurviveRestartAndMasterDoesNotEraseCategories() {
        let suite = "NotificationCategoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = PokeDeliveryState(defaults: defaults)
        #expect(state.categories == NotificationCategories())
        state.categories.pokes = false
        state.categories.tasks = false
        state.notificationsEnabled = false
        let restored = PokeDeliveryState(defaults: defaults)
        #expect(!restored.receivesPokes)
        restored.notificationsEnabled = true
        #expect(!restored.receivesPokes)
        #expect(!restored.categories.tasks)
        #expect(restored.categories.projects && restored.categories.reviews)
    }

    @Test func pokeDeliveryRequiresBothMasterAndPokeCategory() {
        let suite = "NotificationCategoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = PokeDeliveryState(defaults: defaults)
        for master in [false, true] {
            for pokes in [false, true] {
                state.notificationsEnabled = master
                state.categories.pokes = pokes
                #expect(state.receivesPokes == (master && pokes))
            }
        }
    }

    @Test func disablingEachReminderLeavesOtherCategoriesEnabled() {
        var categories = NotificationCategories()
        categories.tasks = false
        #expect(!categories.allowsReminder(isReview: false, isTask: true))
        #expect(categories.allowsReminder(isReview: false, isTask: false))
        #expect(categories.allowsReminder(isReview: true, isTask: false))
        categories.tasks = true
        categories.projects = false
        #expect(categories.allowsReminder(isReview: false, isTask: true))
        #expect(!categories.allowsReminder(isReview: false, isTask: false))
        categories.reviews = false
        #expect(!categories.allowsReminder(isReview: true, isTask: false))
    }
}
