import SwiftUI
import UIKit

/// Third tab: profile, reports, and general preferences.
struct SettingsView: View {
    let model: GroupBombModel
    let authSession: AuthSessionStore
    let onReplayTutorial: () -> Void
    @State private var showsNotificationTest = false
    @State private var showsSignOutConfirmation = false

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NavigationLink {
                        ProfileDetailView(model: model)
                    } label: {
                        ProfileCard(
                            name: model.profileName.isEmpty
                                ? (authSession.currentUserEmail ?? "我的帳號")
                                : model.profileName,
                            role: model.profileRole,
                            groupName: model.groups.first?.name,
                            avatarSymbol: model.profileAvatarSymbol,
                            avatarData: model.profileAvatarData
                        )
                    }
                    .buttonStyle(.plain)

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

                    SettingsSection(title: "教學專區") {
                        Button(action: onReplayTutorial) {
                            SettingsRow(
                                icon: "book.pages.fill",
                                title: "新手入門",
                                subtitle: "建立專案、分配任務與查看進度"
                            )
                        }
                        .buttonStyle(.plain)
                    }

#if DEBUG
                    SettingsSection(title: "開發工具") {
                        TestModeSettingsRow(model: model)
                    }
#endif

                    SettingsSection(title: "帳號") {
                        Button {
                            showsSignOutConfirmation = true
                        } label: {
                            SettingsRow(
                                icon: "rectangle.portrait.and.arrow.right",
                                title: "登出",
                                subtitle: authSession.currentUserEmail ?? "目前帳號"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .padding(.bottom, 132)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: "設定") {
                EmptyView()
            } trailing: {
                EmptyView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showsNotificationTest) {
            NotificationTestView(model: model)
        }
        .confirmationDialog("確定要登出嗎？", isPresented: $showsSignOutConfirmation) {
            Button("登出", role: .destructive) {
                authSession.signOut()
            }
            Button("取消", role: .cancel) { }
        }
    }
}

private struct ProfileCard: View {
    let name: String
    let role: String
    let groupName: String?
    let avatarSymbol: String
    let avatarData: Data?

    var body: some View {
        HStack(spacing: 16) {
            ProfileAvatarImage(data: avatarData, fallbackSymbol: avatarSymbol)
            .frame(width: 76, height: 76)
            .clipShape(.circle)

            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.title2.weight(.black))
                if !role.isEmpty {
                    Text(role).font(.subheadline.bold()).foregroundStyle(.secondary)
                }
                if let groupName {
                    Label(groupName, systemImage: "person.3.fill")
                        .font(.caption.bold())
                }
            }
            Spacer()
            Image(systemName: "pencil.circle.fill").font(.title2)
        }
        .comicCard()
    }
}

#if DEBUG
private struct TestModeSettingsRow: View {
    let model: GroupBombModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(BombTheme.yellow)
                .clipShape(.circle)
            Text("測試模式").font(.body.weight(.bold))
            Spacer()
            Toggle("測試模式", isOn: Binding(
                get: { model.isDemoMode },
                set: { model.setDemoMode($0) }
            ))
            .labelsHidden()
            .tint(BombTheme.green)
        }
        .foregroundStyle(BombTheme.ink)
        .padding(.vertical, 8)
    }
}
#endif

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
                .accessibilityLabel("返回設定")
            } trailing: {
                EmptyView()
            }
        }
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
