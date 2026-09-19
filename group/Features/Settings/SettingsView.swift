import SwiftUI
import UIKit

/// Third tab: profile, reports, and general preferences.
struct SettingsView: View {
    let model: GroupBombModel
    let authSession: AuthSessionStore
    let onReplayTutorial: () -> Void
    @State private var showsSignOutConfirmation = false
    @State private var showsPasswordReset = false

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if authSession.isAuthenticated {
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
                    } else {
                        Button { authSession.signOut() } label: {
                            SettingsRow(icon: "person.crop.circle", title: "尚未登入", subtitle: "登入以編輯個人資料")
                                .comicCard()
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsSection(title: "工作空間") {
                        NavigationLink {
                            PersonalBattleReportView(model: model)
                        } label: {
                            SettingsRow(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "個人戰力檔案",
                                subtitle: "累積每個專案收到的匿名互評"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()

                        NavigationLink {
                            NotificationSettingsView(model: model)
                        } label: {
                            SettingsRow(icon: "bell.fill", title: "通知設定",
                                        subtitle: "通知分類與測試")
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsSection(title: "支援") {
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
                        if authSession.isAuthenticated {
                            Button { showsPasswordReset = true } label: {
                                SettingsRow(icon: "lock.rotation", title: "重設密碼", subtitle: "透過電子郵件重設密碼")
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        Button {
                            if authSession.isAuthenticated {
                                showsSignOutConfirmation = true
                            } else {
                                authSession.signOut()
                            }
                        } label: {
                            SettingsRow(
                                icon: "rectangle.portrait.and.arrow.right",
                                title: authSession.isAuthenticated ? "登出" : "登入",
                                subtitle: authSession.isAuthenticated ? (authSession.currentUserEmail ?? "目前帳號") : "目前未登入"
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
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetView(
                session: authSession,
                initialEmail: authSession.currentUserEmail ?? "",
                completionTitle: "完成"
            )
        }
        .bombDialog("確定要登出嗎？", isPresented: $showsSignOutConfirmation) {
            Button("取消", role: .cancel) { }
            Button("登出", role: .destructive) {
                authSession.signOut()
            }
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

private struct GroupManagementView: View {
    let model: GroupBombModel
    @State private var groupToLeave: Group?
    @State private var showsLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var leaveError: String?

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
        .bombDialog(
            "確定要離開「\(groupToLeave?.name ?? "")」嗎？",
            isPresented: $showsLeaveConfirmation,
            destructiveIsRed: true
        ) {
            Button("取消", role: .cancel) { }
            Button("離開群組", role: .destructive) {
                guard let groupToLeave else { return }
                isLeaving = true
                Task {
                    defer { isLeaving = false }
                    do { try await model.leaveGroup(groupID: groupToLeave.id) }
                    catch { leaveError = "退出失敗，請確認網路後重試。" }
                }
            }
        } message: {
            Text("退出後將無法查看此群組。最後一位成員退出後，群組資料會永久刪除。")
        }
        .disabled(isLeaving)
        .bombDialog("無法退出群組", isPresented: Binding(
            get: { leaveError != nil }, set: { if !$0 { leaveError = nil } }
        )) {
            Button("知道了") { }
        } message: { Text(leaveError ?? "") }
    }
}
