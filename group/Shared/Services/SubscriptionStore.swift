import Foundation
import Observation
import RevenueCat

@MainActor @Observable
final class SubscriptionStore {
    private(set) var isPro = false
    private(set) var monthlyPackage: Package?
    private(set) var isWorking = false
    var errorMessage: String?
    private var userID: String?

    func syncUser(_ newUserID: String?) async {
        guard userID != newUserID else { return }
        let previousUserID = userID
        userID = newUserID
        isPro = false
        monthlyPackage = nil
        errorMessage = nil
        #if DEBUG
        if previousUserID != nil { _ = try? await Purchases.shared.logOut() }
        guard let newUserID, userID == newUserID else { return }
        do {
            let login = try await Purchases.shared.logIn(newUserID)
            guard userID == newUserID, Purchases.shared.appUserID == newUserID else { return }
            update(login.customerInfo)
            let offerings = try await Purchases.shared.offerings()
            guard userID == newUserID else { return }
            monthlyPackage = offerings.current?.monthly
        } catch {
            guard userID == newUserID else { return }
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func listenForUpdates() async {
        #if DEBUG
        for await info in Purchases.shared.customerInfoStream {
            guard let userID, Purchases.shared.appUserID == userID else { continue }
            update(info)
        }
        #endif
    }

    func refresh() async {
        #if DEBUG
        guard let userID, Purchases.shared.appUserID == userID else { return }
        do {
            Purchases.shared.invalidateCustomerInfoCache()
            let info = try await Purchases.shared.customerInfo()
            update(info)
            if monthlyPackage == nil {
                let offerings = try await Purchases.shared.offerings()
                monthlyPackage = offerings.current?.monthly
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func purchaseMonthly() async {
        #if DEBUG
        guard let userID, Purchases.shared.appUserID == userID,
              let monthlyPackage, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let result = try await Purchases.shared.purchase(package: monthlyPackage)
            if !result.userCancelled { update(result.customerInfo) }
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    func restore() async {
        #if DEBUG
        guard let userID, Purchases.shared.appUserID == userID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            update(try await Purchases.shared.restorePurchases())
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }

    private func update(_ info: CustomerInfo) {
        isPro = info.entitlements.active["oops_bomb_pro"] != nil
    }
}
