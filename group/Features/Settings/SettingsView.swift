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
                        NotificationSettingsRow(model: model)
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

private struct NotificationSettingsRow: View {
    let model: GroupBombModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.fill")
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(BombTheme.yellow)
                .clipShape(Circle())
            Text("通知設定").font(.body.weight(.bold))
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
