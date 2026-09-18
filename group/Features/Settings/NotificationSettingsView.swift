import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var model: GroupBombModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Toggle("允許通知", isOn: $model.notificationsEnabled)
                        .font(.headline)
                        .comicCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("通知分類").font(.title2.weight(.black))
                        VStack(spacing: 0) {
                            category("戳戳", icon: "hand.tap.fill", isOn: $model.notificationCategories.pokes)
                            Divider()
                            category("我的任務提醒", icon: "checklist", isOn: $model.notificationCategories.tasks)
                            Divider()
                            category("專案倒數", icon: "hourglass", isOn: $model.notificationCategories.projects)
                            Divider()
                            category("互評提醒", icon: "star.bubble.fill", isOn: $model.notificationCategories.reviews)
                        }
                        .comicCard()
                        .disabled(!model.notificationsEnabled)
                    }

                    NavigationLink {
                        NotificationTestView(model: model)
                    } label: {
                        HStack(spacing: 12) {
                            Label("通知測試", systemImage: "bell.badge.fill")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }
                        .comicCard()
                    }
                    .buttonStyle(.plain)
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
            BombHeader(title: "通知設定") {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel("返回設定")
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
