import SwiftUI
import RevenueCat

struct SubscriptionView: View {
    let subscription: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BombFormSheet(title: L10n.text("Oops Bomb Pro"), backgroundColor: BombTheme.yellow) {
            VStack(alignment: .leading, spacing: 18) {
                Text(subscription.isPro
                     ? L10n.text("已解鎖不限數量的未結束專案")
                     : L10n.text("免費最多 2 個未結束專案；升級後不限數量。"))
                    .font(.title3.bold())
                if let package = subscription.monthlyPackage, !subscription.isPro {
                    Text(L10n.text("月訂閱") + " · " + package.localizedPriceString)
                        .font(.headline)
                }
                if let errorMessage = subscription.errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(BombTheme.red)
                }
                #if !DEBUG
                Text(L10n.text("訂閱功能尚未在正式版開放。"))
                    .font(.footnote)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .comicCard()
        } actions: {
            VStack(spacing: 12) {
                #if DEBUG
                if !subscription.isPro {
                    Button(L10n.text("訂閱 Oops Bomb Pro")) {
                        Task { await subscription.purchaseMonthly() }
                    }
                    .buttonStyle(BombFormPrimaryButtonStyle())
                    .disabled(subscription.monthlyPackage == nil || subscription.isWorking)
                }
                Button(L10n.text("恢復購買")) {
                    Task { await subscription.restore() }
                }
                .disabled(subscription.isWorking)
                #endif
                Button(L10n.text("關閉")) { dismiss() }
            }
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium])
        .task { await subscription.refresh() }
    }
}
