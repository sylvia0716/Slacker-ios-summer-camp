import SwiftUI
import UIKit

/// Third tab: profile, reports, and general preferences.
struct SettingsView: View {
    let model: GroupBombModel
    @State private var showsNotificationTest = false

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("設定")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))

                    ProfileCard(name: model.profileName)

                    SettingsSection(title: "戰情報告") {
                        NavigationLink { PeerReviewReportView(model: model) } label: {
                            SettingsRow(
                                icon: "scope",
                                title: "戰力報告",
                                subtitle: "AI 分析、互評與貢獻雷達"
                            )
                        }
                    }

                    SettingsSection(title: "一般設定") {
                        NotificationSettingsRow(model: model) {
                            showsNotificationTest = true
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BombTheme.yellow, for: .navigationBar)
        .navigationDestination(isPresented: $showsNotificationTest) {
            NotificationTestView(model: model)
        }
    }
}

private struct ProfileCard: View {
    let name: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(BombTheme.ink)
                Text(String(name.prefix(1)))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.title2.weight(.black))
                Text("拆彈手").font(.subheadline.bold()).foregroundStyle(.secondary)
                Label("期末報告拆彈小隊", systemImage: "person.3.fill")
                    .font(.caption.bold())
            }
            Spacer()
            Image(systemName: "pencil.circle.fill").font(.title2)
        }
        .comicCard()
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.weight(.black))
            VStack(spacing: 0) { content }
                .comicCard()
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(BombTheme.yellow)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.bold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold())
        }
        .foregroundStyle(BombTheme.ink)
        .padding(.vertical, 8)
    }
}

private struct NotificationSettingsRow: View {
    let model: GroupBombModel
    let showsTestPage: () -> Void
    @State private var titleTapCount = 0

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.fill")
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(BombTheme.yellow)
                .clipShape(.circle)
            Button {
                titleTapCount += 1
                guard titleTapCount == 5 else { return }
                titleTapCount = 0
                showsTestPage()
            } label: {
                Text("通知設定").font(.body.weight(.bold))
            }
            .buttonStyle(.plain)
            Spacer()
            Toggle("通知設定", isOn: Binding(
                get: { model.notificationsEnabled },
                set: { model.notificationsEnabled = $0 }
            ))
            .labelsHidden()
            .tint(BombTheme.green)
        }
        .foregroundStyle(BombTheme.ink)
        .padding(.vertical, 8)
    }
}

private struct NotificationTestView: View {
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

                if pokeCount > 0 {
                    Text("已戳自己 \(pokeCount) 下")
                        .font(.headline.weight(.black))
                }
            }
            .padding(24)
        }
        .navigationTitle("通知測試")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BombTheme.yellow, for: .navigationBar)
        .onAppear {
            selectedGroupID = selectedGroupID ?? model.groups.first?.id
        }
        .alert("通知設定已關閉", isPresented: $showsNotificationsDisabledAlert) {
            Button("好", role: .cancel) { }
        }
    }
}

private struct GroupManagementView: View {
    let model: GroupBombModel
    @State private var groupToLeave: Group?
    @State private var showsLeaveConfirmation = false

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("群組管理").font(.largeTitle.weight(.black))
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(group.name).font(.title3.weight(.black))
                        Button("複製邀請碼", systemImage: "doc.on.doc.fill") {
                            UIPasteboard.general.string = group.inviteCode
                            model.lastEvent = "邀請碼已複製"
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BombTheme.ink)
                        Button("離開群組", role: .destructive) {
                            groupToLeave = group
                            showsLeaveConfirmation = true
                        }
                            .font(.body.bold())
                    }
                    .comicCard()
                }
                Spacer()
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BombTheme.yellow, for: .navigationBar)
        .confirmationDialog(
            "確定要離開「\(groupToLeave?.name ?? "")」嗎？",
            isPresented: $showsLeaveConfirmation
        ) {
            Button("離開群組", role: .destructive) {
                guard let groupToLeave else { return }
                model.leaveGroup(groupID: groupToLeave.id)
            }
            Button("取消", role: .cancel) { }
        }
    }
}
