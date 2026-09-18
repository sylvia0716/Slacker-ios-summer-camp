import SwiftUI

struct NotificationTestView: View {
    @Environment(\.dismiss) private var dismiss
    let model: GroupBombModel
    @State private var selectedGroupID: UUID?
    @State private var pokeCount = 0
    @State private var showsNotificationsDisabledAlert = false

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()

            VStack(spacing: 24) {
                Picker("小組", selection: $selectedGroupID) {
                    ForEach(model.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
                .font(.headline)

                Button {
                    guard let selectedGroupID,
                          let count = model.sendTestPoke(in: selectedGroupID) else {
                        showsNotificationsDisabledAlert = true
                        return
                    }
                    pokeCount = count
                } label: {
                    Label("戳自己一下", systemImage: "hand.tap.fill")
                        .font(.title3.weight(.black))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(selectedGroupID == nil)

                if model.groups.isEmpty {
                    Text("加入專案後即可測試").font(.subheadline)
                }

                if pokeCount > 0 {
                    Text("已戳自己 \(pokeCount) 下")
                        .font(.headline.weight(.black))
                }
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: "通知測試") {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel("返回通知設定")
            } trailing: {
                EmptyView()
            }
        }
        .onAppear {
            selectedGroupID = selectedGroupID ?? model.groups.first?.id
        }
        .bombDialog("請先開啟通知及戳戳提醒", isPresented: $showsNotificationsDisabledAlert) {
            Button("好") { }
        }
    }
}

