import SwiftUI

/// Legacy mission-board screen preserved from the first prototype.
/// Future work: evolve this into GroupDetailView after Group and ProjectTask models are connected.
struct MissionBoardView: View {
    let model: GroupBombModel
    let group: Group
    let showsNewGroupPrompt: Bool
    @State private var shieldOpen = false
    @State private var isTaskPromptPresented = false

    init(model: GroupBombModel, group: Group, showsNewGroupPrompt: Bool = false) {
        self.model = model
        self.group = group
        self.showsNewGroupPrompt = showsNewGroupPrompt
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    ProjectStatusHeader(name: group.name, progress: model.teamProgress)
                    HStack {
                        Stat(value: "\(model.claimedCount)", label: "我的任務")
                        Stat(value: "\(model.teamProgress)%", label: "拆彈進度")
                        Stat(value: "2天", label: "剩餘時間")
                    }
                    .comicCard()

                    HStack {
                        Text("任務看板").font(.system(.title2, design: .rounded, weight: .black))
                        Spacer()
                        Button { shieldOpen = true } label: {
                            Label("我在做了", systemImage: "shield.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BombTheme.green)
                    }

                    ForEach(model.tasks) { task in
                        MissionCard(task: task) { model.claim(task.id) }
                    }
                    Text(model.lastEvent).font(.footnote.bold()).padding(.top, 4)
                }
                .padding(16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AgentsView(model: model) } label: {
                    Image(systemName: "person.3.fill")
                }
            }
        }
        .sheet(isPresented: $shieldOpen) { ShieldSheet(model: model) }
        .bombDialog("群組已建立", isPresented: $isTaskPromptPresented) {
            Button("知道了") { }
        } message: {
            Text("現在可以新增任務，邀請隊友一起拆彈。")
        }
        .onAppear {
            isTaskPromptPresented = showsNewGroupPrompt
        }
    }
}

/// Group status header: shows the deadline countdown and total project progress.
struct ProjectStatusHeader: View {
    let name: String
    let progress: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "timer").foregroundStyle(BombTheme.yellow)
                Text("行動代號：\(name)").font(.headline)
                Spacer()
                Text("LIVE").font(.caption.weight(.black)).foregroundStyle(BombTheme.red)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("48:16:09").font(.system(size: 38, weight: .black, design: .monospaced))
                Spacer()
                Text("\(progress)%").font(.title3.weight(.black))
            }
            ProgressView(value: Double(progress), total: 100).tint(BombTheme.yellow)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(BombTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .top) {
            HazardStripe().clipShape(.capsule).padding(.horizontal, 20).offset(y: -5)
        }
    }
}

/// Small statistic used by the legacy mission board.
private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack {
            Text(value).font(.title2.weight(.black))
            Text(label).font(.caption.bold())
        }
        .frame(maxWidth: .infinity)
    }
}

/// A task card; future work moves task completion into SubtaskRow and TaskCompletionSheet.
private struct MissionCard: View {
    let task: MissionTask
    let claim: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(task.title).font(.headline)
                Spacer()
                Text("+\(task.points) XP").font(.caption.weight(.black)).padding(6)
                    .background(BombTheme.yellow).clipShape(.capsule)
            }
            Text(task.detail).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                if let owner = task.owner {
                    Label(owner == "我" ? "由我拆彈" : "\(owner) 處理中", systemImage: owner == "我" ? "checkmark.seal.fill" : "person.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(owner == "我" ? BombTheme.green : .secondary)
                } else {
                    Text("尚未認領").font(.subheadline.bold())
                    Spacer()
                    Button("認領任務", action: claim)
                        .buttonStyle(.borderedProminent)
                        .tint(BombTheme.ink)
                        .sensoryFeedback(.success, trigger: task.owner)
                }
            }
        }
        .comicCard()
        .accessibilityElement(children: .contain)
    }
}

/// Temporary self-report sheet. Future work: attach it to a task in My Tasks.
private struct ShieldSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: GroupBombModel
    @State private var minutes = 30
    @State private var note = "正在完成資料整理"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("護盾時間", selection: $minutes) {
                        Text("15 分鐘").tag(15)
                        Text("30 分鐘").tag(30)
                        Text("60 分鐘").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
                Section("進度廣播") { TextField("我正在做⋯", text: $note) }
                Section {
                    Button {
                        model.shield(minutes: minutes, note: note)
                        dismiss()
                    } label: {
                        Label("啟動護盾", systemImage: "shield.checkered").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BombTheme.green)
                }
            }
            .navigationTitle("我在做了")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
