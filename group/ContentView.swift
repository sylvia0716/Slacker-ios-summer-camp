import SwiftUI
import UIKit

struct ContentView: View {
    @State private var model = GroupBombModel()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { MissionBoard(model: model) }.tabItem { Label("任務", systemImage: "bolt.fill") }.tag(0)
            NavigationStack { AgentsView(model: model) }.tabItem { Label("特工", systemImage: "person.3.fill") }.tag(1)
            NavigationStack { RadarView(model: model) }.tabItem { Label("雷達", systemImage: "scope") }.tag(2)
        }
        .tint(BombTheme.ink)
    }
}

struct MissionBoard: View {
    let model: GroupBombModel
    @State private var shieldOpen = false
    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView { VStack(spacing: 18) {
                LiveBombHeader(progress: model.teamProgress)
                HStack { Stat(value: "\(model.claimedCount)", label: "我的任務"); Stat(value: "\(model.teamProgress)%", label: "拆彈進度"); Stat(value: "2天", label: "剩餘時間") }.comicCard()
                HStack { Text("任務看板").font(.system(.title2, design: .rounded, weight: .black)); Spacer(); Button { shieldOpen = true } label: { Label("我在做了", systemImage: "shield.fill") }.buttonStyle(.borderedProminent).tint(BombTheme.green) }
                ForEach(model.tasks) { task in MissionCard(task: task) { model.claim(task.id) } }
                Text(model.lastEvent).font(.footnote.bold()).padding(.top, 4)
            }.padding(16).padding(.bottom, 20) }
        }
        .navigationTitle("GROUP BOMB")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $shieldOpen) { ShieldSheet(model: model) }
    }
}

struct LiveBombHeader: View {
    let progress: Int
    var body: some View {
        VStack(spacing: 10) {
            HStack { Image(systemName: "timer").foregroundStyle(BombTheme.yellow); Text("行動代號：期末報告").font(.headline); Spacer(); Text("LIVE").font(.caption.weight(.black)).foregroundStyle(BombTheme.red) }
            HStack(alignment: .firstTextBaseline) { Text("48:16:09").font(.system(size: 38, weight: .black, design: .monospaced)); Spacer(); Text("\(progress)%").font(.title3.weight(.black)) }
            ProgressView(value: Double(progress), total: 100).tint(BombTheme.yellow)
        }.foregroundStyle(.white).padding(18).background(BombTheme.ink).clipShape(RoundedRectangle(cornerRadius: 22)).overlay(alignment: .top) { HazardStripe().clipShape(.capsule).padding(.horizontal, 20).offset(y: -5) }
    }
}

struct Stat: View { let value: String; let label: String; var body: some View { VStack { Text(value).font(.title2.weight(.black)); Text(label).font(.caption.bold()) }.frame(maxWidth: .infinity) } }

struct MissionCard: View {
    let task: MissionTask; let claim: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(task.title).font(.headline); Spacer(); Text("+\(task.points) XP").font(.caption.weight(.black)).padding(6).background(BombTheme.yellow).clipShape(.capsule) }
            Text(task.detail).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                if let owner = task.owner { Label(owner == "我" ? "由我拆彈" : "\(owner) 處理中", systemImage: owner == "我" ? "checkmark.seal.fill" : "person.fill").font(.subheadline.bold()).foregroundStyle(owner == "我" ? BombTheme.green : .secondary) }
                else { Text("尚未認領").font(.subheadline.bold()); Spacer(); Button("認領任務", action: claim).buttonStyle(.borderedProminent).tint(BombTheme.ink).sensoryFeedback(.success, trigger: task.owner) }
            }
        }.comicCard().accessibilityElement(children: .contain)
    }
}

struct ShieldSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: GroupBombModel
    @State private var minutes = 30
    @State private var note = "正在完成資料整理"
    var body: some View {
        NavigationStack { Form {
            Section { Picker("護盾時間", selection: $minutes) { Text("15 分鐘").tag(15); Text("30 分鐘").tag(30); Text("60 分鐘").tag(60) }.pickerStyle(.segmented) }
            Section("進度廣播") { TextField("我正在做⋯", text: $note) }
            Section { Button { model.shield(minutes: minutes, note: note); dismiss() } label: { Label("啟動護盾", systemImage: "shield.checkered").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BombTheme.green) }
        }.navigationTitle("我在做了").navigationBarTitleDisplayMode(.inline) }
        .presentationDetents([.medium])
    }
}

struct AgentsView: View {
    let model: GroupBombModel
    @State private var selectedAgent: Agent?

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("特工狀態")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))

                    Text("全員一起戳，催進度不尷尬。")
                        .font(.subheadline.bold())

                    ForEach(model.agents) { agent in
                        Button { selectedAgent = agent } label: {
                            AgentCard(agent: agent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("特工")
        .sheet(item: $selectedAgent) { agent in
            PokeSheet(agent: agent, model: model)
        }
    }
}

struct AgentCard: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(agent.isShielded ? BombTheme.green : BombTheme.ink)
                Text(String(agent.name.prefix(1)))
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(agent.name).font(.headline)
                    Text(agent.role).font(.caption.bold()).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(agent.progress), total: 100).tint(agent.isShielded ? BombTheme.green : BombTheme.red)
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

struct PokeSheet: View {
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

                Text(agent.isShielded ? "(agent.name) 正在努力，先別戳。" : "戳一下 (agent.name)")
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
                        Label("發動 (selectedStyle.rawValue)", systemImage: "hand.tap.fill")
                            .frame(maxWidth: .infinity)
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

struct RadarView: View {
    let model: GroupBombModel

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("貢獻雷達")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text("匿名互評｜第 4 組")
                        .font(.subheadline.bold())

                    ContributionRadar(metrics: model.radar)
                        .frame(height: 310)
                        .comicCard()

                    ForEach(model.radar) { metric in
                        HStack {
                            Text(metric.title).font(.headline)
                            Spacer()
                            Text("\(Int(metric.score * 100)) 分").font(.headline.monospacedDigit())
                        }
                        .padding(.horizontal, 4)
                    }

                    Button { model.lastEvent = "PDF 戰報已準備完成" } label: {
                        Label("匯出貢獻戰報 PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BombTheme.ink)
                    Text(model.lastEvent).font(.footnote.bold())
                }
                .padding(16)
            }
        }
        .navigationTitle("雷達")
    }
}

struct ContributionRadar: View {
    let metrics: [RadarMetric]

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.32
            Canvas { context, size in
                let count = metrics.count
                guard count > 2 else { return }

                for level in 1...4 {
                    var ring = Path()
                    for index in 0..<count {
                        let point = radarPoint(index: index, count: count, radius: radius * Double(level) / 4, center: center)
                        index == 0 ? ring.move(to: point) : ring.addLine(to: point)
                    }
                    ring.closeSubpath()
                    context.stroke(ring, with: .color(BombTheme.ink.opacity(0.22)), lineWidth: 1)
                }

                var shape = Path()
                for (index, metric) in metrics.enumerated() {
                    let point = radarPoint(index: index, count: count, radius: radius * metric.score, center: center)
                    index == 0 ? shape.move(to: point) : shape.addLine(to: point)
                }
                shape.closeSubpath()
                context.fill(shape, with: .color(BombTheme.red.opacity(0.48)))
                context.stroke(shape, with: .color(BombTheme.ink), lineWidth: 3)
            }
            .overlay {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    let point = radarPoint(index: index, count: metrics.count, radius: radius * 1.28, center: center)
                    Text(metric.title)
                        .font(.caption.weight(.black))
                        .position(point)
                }
            }
        }
    }

    private func radarPoint(index: Int, count: Int, radius: Double, center: CGPoint) -> CGPoint {
        let angle = (Double(index) / Double(count) * 2 * .pi) - (.pi / 2)
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

#Preview { ContentView() }
