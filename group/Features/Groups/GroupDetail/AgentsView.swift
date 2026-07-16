import SwiftUI

/// Legacy member-progress screen. Future work: embed MemberProgressCard in GroupDetailView.
struct AgentsView: View {
    let model: GroupBombModel
    @State private var selectedAgent: Agent?

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("特工狀態").font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text("全員一起戳，催進度不尷尬。").font(.subheadline.bold())
                    ForEach(model.agents) { agent in
                        Button { selectedAgent = agent } label: { AgentCard(agent: agent) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("特工")
        .sheet(item: $selectedAgent) { agent in PokeSheet(agent: agent, model: model) }
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

/// Reminder sheet. Future work: record a group-scoped poke event in AppStore.
private struct PokeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let agent: Agent
    let model: GroupBombModel
    @State private var selectedStyle: PokeStyle = .gentle

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: agent.isShielded ? "shield.fill" : "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 58))
                    .foregroundStyle(agent.isShielded ? BombTheme.green : BombTheme.red)
                Text(agent.isShielded ? "\(agent.name) 正在努力，先別戳。" : "戳一下 \(agent.name)")
                    .font(.title2.weight(.black))

                if !agent.isShielded {
                    Picker("戳法", selection: $selectedStyle) {
                        ForEach(PokeStyle.allCases) { style in
                            Label(style.rawValue, systemImage: style.icon).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    Text(selectedStyle.message)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BombTheme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Button {
                        model.poke(agentID: agent.id, style: selectedStyle)
                        dismiss()
                    } label: {
                        Label("發動 \(selectedStyle.rawValue)", systemImage: "hand.tap.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BombTheme.red)
                    .sensoryFeedback(.impact(weight: .heavy), trigger: selectedStyle)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("集體催進度")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
