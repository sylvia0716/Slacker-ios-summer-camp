import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var model: GroupBombModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Toggle(L10n.text("允許通知"), isOn: $model.notificationsEnabled)
                        .font(.headline)
                        .comicCard()

                    if model.pokeNotificationSyncFailed {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("通知設定尚未同步，背景通知可能仍依原設定送出。"))
                                .font(.footnote)
                            Button(L10n.text("重試")) { model.registerPokeDevice() }
                                .font(.subheadline.bold())
                        }
                        .foregroundStyle(BombTheme.red)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text("通知分類")).font(.title2.weight(.black))
                        VStack(spacing: 0) {
                            category(L10n.text("戳戳"), icon: "hand.tap.fill", isOn: $model.notificationCategories.pokes)
                            Divider()
                            category(L10n.text("我的任務提醒"), icon: "checklist", isOn: $model.notificationCategories.tasks)
                            Divider()
                            category(L10n.text("專案倒數"), icon: "hourglass", isOn: $model.notificationCategories.projects)
                            Divider()
                            category(L10n.text("會議提醒"), icon: "calendar", isOn: $model.notificationCategories.meetings)
                            Divider()
                            category(L10n.text("互評提醒"), icon: "star.bubble.fill", isOn: $model.notificationCategories.reviews)
                        }
                        .comicCard()
                        .disabled(!model.notificationsEnabled)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text("提醒時間")).font(.title2.weight(.black))
                        VStack(alignment: .leading, spacing: 8) {
                            DatePicker(
                                L10n.text("任務與專案提醒時間"),
                                selection: $model.deadlineReminderTime,
                                displayedComponents: .hourAndMinute
                            )
                            .font(.body.bold())

                            Text(L10n.text("截止提醒會在指定時間送出；戳戳與互評仍會即時提醒。"))
                                .font(.caption)
                                .foregroundStyle(BombTheme.ink.opacity(0.6))
                        }
                        .comicCard()
                        .disabled(
                            !model.notificationsEnabled
                                || (!model.notificationCategories.tasks && !model.notificationCategories.projects)
                        )
                    }

                }
                .foregroundStyle(BombTheme.ink)
                .tint(BombTheme.green)
                .padding(16)
                .padding(.bottom, 132)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("通知設定")) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel(L10n.text("返回一般設定"))
            } trailing: {
                EmptyView()
            }
        }
    }

    private func category(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon).font(.body.bold())
        }
        .padding(.vertical, 14)
    }
}
