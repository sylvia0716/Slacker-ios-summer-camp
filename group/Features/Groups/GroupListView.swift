import SwiftUI

/// First tab: lists groups the current user has joined and opens their detail screen.
struct GroupListView: View {
    let model: GroupBombModel

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("我的群組")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text("選一組，繼續拆彈。")
                        .font(.subheadline.bold())

                    ForEach(model.groups) { group in
                        NavigationLink {
                            MissionBoardView(model: model)
                        } label: {
                            GroupRow(group: group, progress: model.teamProgress, memberCount: model.agents.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("群組")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("建立群組", systemImage: "plus") { model.lastEvent = "建立群組功能準備中" }
                    Button("加入群組", systemImage: "person.badge.plus") { model.lastEvent = "加入群組功能準備中" }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

/// One group entry. Future work: show the real member and task counts from Group relationships.
private struct GroupRow: View {
    let group: Group
    let progress: Int
    let memberCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(BombTheme.yellow)
                Text(group.name).font(.title3.weight(.black))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold())
            }
            HStack {
                Label("剩 2 天", systemImage: "timer")
                Spacer()
                Label("\(memberCount) 位特工", systemImage: "person.3.fill")
            }
            .font(.caption.bold())
            ProgressView(value: Double(progress), total: 100).tint(BombTheme.yellow)
            Text("專案進度 \(progress)%").font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(BombTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
