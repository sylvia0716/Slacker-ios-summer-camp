import SwiftUI

/// Third tab: profile, reports, and general preferences.
struct SettingsView: View {
    let model: GroupBombModel

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
                        SettingsRow(icon: "person.crop.circle.fill", title: "個人資料", subtitle: model.profileName)
                        Divider()
                        Toggle(isOn: Binding(
                            get: { model.notificationsEnabled },
                            set: { model.notificationsEnabled = $0 }
                        )) {
                            Label("通知設定", systemImage: "bell.fill")
                                .font(.body.weight(.bold))
                        }
                        .tint(BombTheme.green)
                        .padding(.vertical, 8)
                        Divider()
                        NavigationLink { GroupManagementView(model: model) } label: {
                            SettingsRow(
                                icon: "person.2.badge.gearshape.fill",
                                title: "群組管理",
                                subtitle: "邀請組員或離開群組"
                            )
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BombTheme.yellow, for: .navigationBar)
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

private struct GroupManagementView: View {
    let model: GroupBombModel

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("群組管理").font(.largeTitle.weight(.black))
                ForEach(model.groups) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(group.name).font(.title3.weight(.black))
                        Button("複製邀請碼", systemImage: "doc.on.doc.fill") {
                            model.lastEvent = "邀請碼已複製"
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BombTheme.ink)
                        Button("離開群組", role: .destructive) {}
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
    }
}
