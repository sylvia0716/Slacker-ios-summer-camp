import SwiftUI

/// Legacy member-progress screen. Future work: embed MemberProgressCard in GroupDetailView.
struct AgentsView: View {
    let model: GroupBombModel
    @State private var selectedAgent: Agent?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ZStack {
                    BombTheme.yellow.ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("特工狀態").font(.system(.largeTitle, design: .rounded, weight: .black))
                            Text("全員一起戳，催進度不尷尬。").font(.subheadline.bold())
                            ForEach(model.agents) { agent in
                                Button {
                                    withAnimation(.snappy) { selectedAgent = agent }
                                } label: {
                                    AgentCard(agent: agent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }

                if let selectedAgent {
                    BombTheme.ink.opacity(0.16)
                        .ignoresSafeArea(edges: .top)
                        .onTapGesture { closeSheet() }
                        .transition(.opacity)

                    PokeSheet(agent: selectedAgent, onCancel: closeSheet)
                        .frame(height: proxy.size.height * 0.78)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("特工")
    }

    private func closeSheet() {
        withAnimation(.snappy) { selectedAgent = nil }
    }
}

/// Reusable visual for a member's progress and shield state.
private struct AgentCard: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(agent.isShielded ? BombTheme.green : BombTheme.ink)
                Text(String(agent.name.prefix(1))).font(.title.bold()).foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(agent.name).font(.headline)
                    Text(agent.role).font(.caption.bold()).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(agent.progress), total: 100)
                    .tint(agent.isShielded ? BombTheme.green : BombTheme.red)
                Text(agent.isShielded ? "護盾已啟動" : agent.status)
                    .font(.caption.bold())
                    .foregroundStyle(agent.isShielded ? BombTheme.green : .secondary)
            }
            Spacer()
            Image(systemName: agent.isShielded ? "shield.fill" : "hand.point.right.fill")
                .foregroundStyle(agent.isShielded ? BombTheme.green : BombTheme.ink)
        }
        .comicCard()
    }
}

/// Page-local reminder sheet. It intentionally stays above the tab bar instead of using
/// a system sheet, whose material obscures the member page and covers the tab bar.
private struct PokeSheet: View {
    let agent: Agent
    let onCancel: () -> Void
    @State private var selectedStyle: PokeStyle = .gentle
    @State private var isSent = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(BombTheme.ink.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if isSent {
                successContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                reminderContent
                    .transition(.opacity)
            }
        }
        .background(BombTheme.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(BombTheme.ink, lineWidth: 3)
        }
        .shadow(color: BombTheme.ink.opacity(0.3), radius: 14, y: 4)
        .sensoryFeedback(.success, trigger: isSent)
    }

    private var reminderContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("戳一下 \(agent.name)")
                            .font(.system(.title2, design: .rounded, weight: .black))
                        Text("選擇一種提醒方式")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.65))
                    }

                    memberSummary

                    VStack(spacing: 9) {
                        ForEach(PokeStyle.allCases) { style in
                            optionCard(for: style)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            actionBar
        }
    }

    private var memberSummary: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(BombTheme.ink)
                Text(String(agent.name.prefix(1)))
                    .font(.title3.weight(.black))
                    .foregroundStyle(BombTheme.yellow)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.headline.weight(.black))
                Text("角色：\(displayRole) · 目前進度：\(displayProgress)%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(displayStatus)
                .font(.caption2.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(BombTheme.red)
                .clipShape(.capsule)
        }
        .comicCard()
    }

    private func optionCard(for style: PokeStyle) -> some View {
        let isSelected = selectedStyle == style

        return Button {
            selectedStyle = style
        } label: {
            HStack(spacing: 12) {
                Image(systemName: style.icon)
                    .font(.headline.weight(.black))
                    .foregroundStyle(style == .alarm ? BombTheme.red : BombTheme.ink)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(optionTitle(for: style))
                        .font(.subheadline.weight(.black))
                    Text(optionDescription(for: style))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BombTheme.ink.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.black))
                    .foregroundStyle(BombTheme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? BombTheme.paper : BombTheme.paper.opacity(0.66))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BombTheme.ink, lineWidth: isSelected ? 4 : 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.snappy) { isSent = true }
            } label: {
                Label("發送提醒", systemImage: "paperplane.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)

            Button("取消", action: onCancel)
                .font(.subheadline.weight(.black))
                .foregroundStyle(BombTheme.ink)
                .buttonStyle(.plain)
                .padding(.vertical, 5)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .safeAreaPadding(.bottom, 8)
        .background(BombTheme.yellow)
    }

    private var successContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            ZStack {
                Circle().fill(BombTheme.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(BombTheme.yellow)
            }
            .frame(width: 82, height: 82)
            .symbolEffect(.bounce, value: isSent)

            Text("提醒已送出")
                .font(.system(.title2, design: .rounded, weight: .black))

            Text("已用「\(optionTitle(for: selectedStyle))」提醒 \(agent.name)")
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.center)

            Text("這則提醒只會顯示給對方")
                .font(.caption.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.6))

            Spacer()

            Button("回到成員進度", action: onCancel)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(BombTheme.ink)
                .clipShape(.capsule)
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .safeAreaPadding(.bottom, 14)
        }
        .padding(.top, 4)
    }

    private func optionTitle(for style: PokeStyle) -> String {
        switch style {
        case .gentle: "輕敲提醒"
        case .meme: "迷因轟炸"
        case .alarm: "警報催命"
        }
    }

    private func optionDescription(for style: PokeStyle) -> String {
        switch style {
        case .gentle: "溫和提醒對方更新進度"
        case .meme: "用輕鬆方式提醒對方"
        case .alarm: "高強度提醒，請謹慎使用"
        }
    }

    /// The current legacy Agent data differs from the approved sheet mock for 米米.
    /// Keep the requested presentation values local so the shared model remains untouched.
    private var displayRole: String {
        agent.name == "米米" ? "簡報設計" : agent.role
    }

    private var displayProgress: Int {
        agent.name == "米米" ? 45 : agent.progress
    }

    private var displayStatus: String {
        agent.name == "米米" ? "進度落後" : agent.status
    }
}
