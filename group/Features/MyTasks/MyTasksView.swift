import SwiftUI

/// Second tab: aggregates the current user's tasks and links back to the owning group.
struct MyTasksView: View {
    let model: GroupBombModel
    @State private var showCompleted = false

    var body: some View {
        List {
            Section {
                Picker("任務狀態", selection: $showCompleted) {
                    Text("待完成").tag(false)
                    Text("已完成").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section(showCompleted ? "已完成" : "待完成") {
                let tasks = showCompleted ? [] : model.tasks.filter { $0.owner == model.userName }
                if tasks.isEmpty {
                    ContentUnavailableView(showCompleted ? "還沒有完成任務" : "目前沒有待完成任務", systemImage: "checkmark.circle")
                } else {
                    ForEach(tasks) { task in
                        NavigationLink {
                            MissionBoardView(model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).font(.headline)
                                Text("期末報告拆彈小隊・\(task.detail)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("我的任務")
    }
}
