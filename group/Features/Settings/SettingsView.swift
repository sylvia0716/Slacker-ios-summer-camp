import SwiftUI
import UIKit

/// Third tab: profile, reports, and general preferences.
struct SettingsView: View {
    let model: GroupBombModel
    let authSession: AuthSessionStore
    let onReplayTutorial: () -> Void

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
                                    ? (authSession.currentUserEmail ?? L10n.text("我的帳號"))
                                    : model.profileName,
                                role: model.profileRole,
                                avatarSymbol: model.profileAvatarSymbol,
                                avatarData: model.profileAvatarData
                            )
                        }
                        .buttonStyle(.plain)
                    } else if authSession.isAnonymous {
                        NavigationLink {
                            AccountSettingsView(model: model, authSession: authSession)
                        } label: {
                            SettingsRow(
                                icon: "person.crop.circle.badge.clock",
                                title: L10n.text("臨時帳號"),
                                subtitle: L10n.text("綁定 Email 以跨裝置同步")
                            )
                                .comicCard()
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 0) {
                        NavigationLink {
                            GeneralSettingsView(model: model)
                        } label: {
                            SettingsRow(icon: "gearshape.fill", title: L10n.text("一般"),
                                        subtitle: L10n.text("語言與通知"))
                        }
                        Divider()
                        NavigationLink {
                            AccountSettingsView(model: model, authSession: authSession)
                        } label: {
                            SettingsRow(icon: "person.crop.circle.fill", title: L10n.text("帳號"),
                                        subtitle: L10n.text("個人戰力檔案與帳號管理"))
                        }
                        Divider()
                        Button(action: onReplayTutorial) {
                            SettingsRow(icon: "book.pages.fill", title: L10n.text("新手教學"),
                                        subtitle: L10n.text("建立專案、分配任務與查看進度"))
                        }
                    }
                    .buttonStyle(.plain)
                    .comicCard()

#if DEBUG
                    NavigationLink {
                        DeveloperSettingsView(model: model, onReplayTutorial: onReplayTutorial)
                    } label: {
                        SettingsRow(icon: "wrench.and.screwdriver.fill", title: L10n.text("開發工具"),
                                    subtitle: L10n.text("測試模式與通知測試"))
                            .comicCard()
                    }
                    .buttonStyle(.plain)
#endif
                }
                .padding(16)
                .padding(.bottom, 132)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("設定")) {
                EmptyView()
            } trailing: {
                EmptyView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct GeneralSettingsView: View {
    let model: GroupBombModel

    var body: some View {
        SettingsPage(title: L10n.text("一般")) {
            SettingsSection(title: L10n.text("語言")) {
                Picker(L10n.text("介面語言"), selection: Binding(
                    get: { AppLanguageSettings.shared.preference },
                    set: { AppLanguageSettings.shared.preference = $0 }
                )) {
                    ForEach(AppLanguagePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .tint(BombTheme.ink)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            NavigationLink {
                NotificationSettingsView(model: model)
            } label: {
                SettingsRow(icon: "bell.fill", title: L10n.text("通知設定"),
                            subtitle: L10n.text("允許通知與通知分類"))
                    .comicCard()
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AccountSettingsView: View {
    let model: GroupBombModel
    let authSession: AuthSessionStore
    @State private var showsSignOutConfirmation = false
    @State private var showsPasswordReset = false
    @State private var showsAccountAccess = false

    var body: some View {
        SettingsPage(title: L10n.text("帳號")) {
            NavigationLink {
                PersonalBattleReportView(model: model)
            } label: {
                SettingsRow(icon: "chart.line.uptrend.xyaxis", title: L10n.text("個人戰力檔案"),
                            subtitle: L10n.text("累積每個專案收到的匿名互評"))
                    .comicCard()
            }
            .buttonStyle(.plain)
            SettingsSection(title: L10n.text("帳號")) {
                if authSession.isAnonymous {
                    Button { showsAccountAccess = true } label: {
                        SettingsRow(
                            icon: "person.crop.circle.badge.plus",
                            title: L10n.text("綁定 Email"),
                            subtitle: L10n.text("保留目前資料並開啟跨裝置登入")
                        )
                    }
                    .buttonStyle(.plain)
                } else if authSession.isAuthenticated {
                    Button { showsPasswordReset = true } label: {
                        SettingsRow(icon: "lock.rotation", title: L10n.text("重設密碼"), subtitle: L10n.text("透過電子郵件重設密碼"))
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                if authSession.isAuthenticated {
                    Button {
                        showsSignOutConfirmation = true
                    } label: {
                        SettingsRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: L10n.text("登出"),
                            subtitle: authSession.currentUserEmail ?? L10n.text("目前帳號")
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(authSession.isWorking)
                    if let message = authSession.signOutErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(BombTheme.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showsAccountAccess) {
            AuthenticationView(
                session: authSession,
                startsInRegistrationMode: true,
                onCompletion: { showsAccountAccess = false }
            )
        }
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetView(
                session: authSession,
                initialEmail: authSession.currentUserEmail ?? "",
                completionTitle: L10n.text("完成")
            )
        }
        .bombDialog(L10n.text("確定要登出嗎？"), isPresented: $showsSignOutConfirmation) {
            Button(L10n.text("取消"), role: .cancel) { }
            Button(L10n.text("登出"), role: .destructive) {
                authSession.signOut()
            }
        }
    }
}

#if DEBUG
private struct DeveloperSettingsView: View {
    let model: GroupBombModel
    let onReplayTutorial: () -> Void

    var body: some View {
        SettingsPage(title: L10n.text("開發工具")) {
            VStack(spacing: 0) {
                TestModeSettingsRow(model: model)
                Divider()
                debugMenu
                    .buttonStyle(.plain)

                Divider()
                NavigationLink {
                    NotificationTestView(model: model)
                } label: {
                    SettingsRow(icon: "bell.badge.fill", title: L10n.text("通知測試"),
                                subtitle: L10n.text("戳自己一下"))
                }
                .buttonStyle(.plain)
            }
            .comicCard()
        }
    }
    private var debugMenu: some View {
        Menu {
            SwiftUI.Group {
                Button(L10n.text("重設 iOS Summer Camp 互評")) {
                    resetReviews(inviteCode: "IOS100")
                }
                Button(L10n.text("重設電子電路期末互評")) {
                    resetReviews(inviteCode: "EE0073")
                }
                Divider()
                Button(L10n.text("完成 iOS Summer Camp 全部互評")) {
                    completeAllReviews(inviteCode: "IOS100")
                }
                Button(L10n.text("完成電子電路期末全部互評")) {
                    completeAllReviews(inviteCode: "EE0073")
                }
            }
            .disabled(!model.isDemoMode)
            Divider()
            Button(L10n.text("重新播放新手教學"), systemImage: "arrow.counterclockwise", action: onReplayTutorial)
        } label: {
            SettingsRow(icon: "wrench.and.screwdriver.fill", title: L10n.text("測試工具"),
                        subtitle: L10n.text("測試模式"))
        }
        .accessibilityLabel(L10n.text("測試工具"))
    }

    private func resetReviews(inviteCode: String) {
        guard model.isDemoMode, let group = model.groups.first(where: { $0.inviteCode == inviteCode }) else { return }
        model.resetPeerReviews(for: group.id)
    }

    private func completeAllReviews(inviteCode: String) {
        guard model.isDemoMode, let group = model.groups.first(where: { $0.inviteCode == inviteCode }) else { return }
        model.resetPeerReviews(for: group.id)

        for reviewerID in group.memberIDs {
            for revieweeID in group.memberIDs where reviewerID != revieweeID {
                _ = try? model.submitPeerReview(
                    groupID: group.id,
                    reviewerID: reviewerID,
                    revieweeID: revieweeID,
                    taskCompletionScore: 4,
                    discussionScore: 4,
                    collaborationScore: 4,
                    ideaScore: 4,
                    reliabilityScore: 4,
                    comment: "",
                    now: group.deadline.addingTimeInterval(1)
                )
            }
        }
    }

}
#endif

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .padding(16)
                    .padding(.bottom, 132)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: title) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel(L10n.text("返回設定"))
            } trailing: {
                EmptyView()
            }
        }
    }
}

private struct ProfileCard: View {
    let name: String
    let role: String
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
            Text(L10n.text("測試模式")).font(.body.weight(.bold))
            Spacer()
            Toggle(L10n.text("測試模式"), isOn: Binding(
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
                Text(L10n.text("群組管理")).font(.largeTitle.weight(.black))
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(group.name).font(.title3.weight(.black))
                        Button(L10n.text("複製邀請碼"), systemImage: "doc.on.doc.fill") {
                            UIPasteboard.general.string = group.inviteCode
                            model.lastEvent = L10n.text("邀請碼已複製")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BombTheme.ink)
                        Button(L10n.text("離開群組"), role: .destructive) {
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
            L10n.format("確定要離開「{0}」嗎？", String(describing: groupToLeave?.name ?? "")),
            isPresented: $showsLeaveConfirmation,
            destructiveIsRed: true
        ) {
            Button(L10n.text("取消"), role: .cancel) { }
            Button(L10n.text("離開群組"), role: .destructive) {
                guard let groupToLeave else { return }
                isLeaving = true
                Task {
                    defer { isLeaving = false }
                    do { try await model.leaveGroup(groupID: groupToLeave.id) }
                    catch { leaveError = L10n.text("退出失敗，請確認網路後重試。") }
                }
            }
        } message: {
            Text(L10n.text("退出後將無法查看此群組。最後一位成員退出後，群組資料會永久刪除。"))
        }
        .disabled(isLeaving)
        .bombDialog(L10n.text("無法退出群組"), isPresented: Binding(
            get: { leaveError != nil }, set: { if !$0 { leaveError = nil } }
        )) {
            Button(L10n.text("知道了")) { }
        } message: { Text(leaveError ?? "") }
    }
}
