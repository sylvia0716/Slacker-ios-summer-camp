import SwiftUI

/// Second tab: aggregates the current user's tasks and opens task delivery details.
struct MyTasksView: View {
    let model: GroupBombModel
    @State private var showCompleted = false

    private var visibleTasks: [ProjectTask] {
        model.projectTasks.filter {
            $0.ownerMemberID == model.currentUserID && $0.isCompleted == showCompleted
        }
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("我的任務")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))

                    if let group = model.groups.first {
                        GroupTaskSummary(
                            groupName: group.name,
                            taskCount: model.tasks(for: model.currentUserID, in: group.id).count,
                            progress: model.memberProgress(for: model.currentUserID, in: group.id)
                        )
                    }

                    Picker("任務狀態", selection: $showCompleted) {
                        Text("待完成").tag(false)
                        Text("已完成").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if visibleTasks.isEmpty {
                        ContentUnavailableView(
                            showCompleted ? "還沒有完成任務" : "目前沒有待完成任務",
                            systemImage: showCompleted ? "checkmark.seal.fill" : "bolt.fill"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                    } else {
                        ForEach(visibleTasks) { task in
                            let group = model.groups.first { $0.id == task.groupID }
                            NavigationLink {
                                MyTaskDetailView(model: model, taskID: task.id)
                            } label: {
                                MyTaskCard(task: task, groupName: group?.name ?? "", deadline: group?.deadline)
                            }
                            .buttonStyle(.plain)
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

private struct GroupTaskSummary: View {
    let groupName: String
    let taskCount: Int
    let progress: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(groupName).font(.title3.weight(.black))
                Spacer()
                Image(systemName: "bolt.fill").foregroundStyle(BombTheme.yellow)
            }
            HStack(spacing: 18) {
                Label("\(taskCount) 項任務", systemImage: "checklist")
                Label("剩 2 天", systemImage: "timer")
            }
            .font(.subheadline.bold())
            ProgressView(value: Double(progress), total: 100).tint(BombTheme.yellow)
            Text("個人進度 \(progress)%").font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(BombTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct MyTaskCard: View {
    let task: ProjectTask
    let groupName: String
    let deadline: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.title3.weight(.black))
                    Text(groupName).font(.caption.bold()).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(task.progress)%")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
            }
            ProgressView(value: Double(task.progress), total: 100)
                .tint(task.isCompleted ? BombTheme.green : BombTheme.red)
            HStack {
                if let deadline {
                    Label { Text(deadline, style: .relative) } icon: { Image(systemName: "clock.fill") }
                }
                Spacer()
                Label("查看任務", systemImage: "chevron.right")
            }
            .font(.caption.bold())
        }
        .comicCard()
    }
}

private struct MyTaskDetailView: View {
    let model: GroupBombModel
    let taskID: UUID

    private var task: ProjectTask? { model.projectTasks.first { $0.id == taskID } }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            if let task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(model.groups.first { $0.id == task.groupID }?.name ?? "")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(BombTheme.ink)
                            .foregroundStyle(BombTheme.yellow)
                            .clipShape(.capsule)

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(task.title).font(.title2.weight(.black))
                                Spacer()
                                Text("\(task.progress)%").font(.title3.weight(.black))
                            }
                            Text(task.detail).font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: Double(task.progress), total: 100)
                                .tint(task.isCompleted ? BombTheme.green : BombTheme.red)
                        }
                        .comicCard()

                        Text("子任務").font(.title2.weight(.black))
                        VStack(spacing: 0) {
                            ForEach(task.subtasks) { subtask in
                                Button {
                                    model.toggleSubtask(taskID: task.id, subtaskID: subtask.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: subtask.isComplete ? "checkmark.square.fill" : "square")
                                            .font(.title3)
                                            .foregroundStyle(subtask.isComplete ? BombTheme.green : BombTheme.ink)
                                        Text(subtask.title)
                                            .font(.body.weight(.bold))
                                            .strikethrough(subtask.isComplete)
                                        Spacer()
                                    }
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
                                if subtask.id != task.subtasks.last?.id { Divider() }
                            }
                        }
                        .comicCard()

                        Text("成果交付").font(.title2.weight(.black))
                        VStack(alignment: .leading, spacing: 12) {
                            if let deliverable = task.deliverable {
                                HStack {
                                    Image(systemName: deliverable.url == nil ? "doc.fill" : "link")
                                    Text(deliverable.title).font(.subheadline.bold()).lineLimit(1)
                                    Spacer()
                                    Text(deliverable.isApproved ? "已驗收" : "待驗收")
                                        .font(.caption.bold())
                                        .foregroundStyle(deliverable.isApproved ? BombTheme.green : .secondary)
                                }
                            }
                            Button {
                                model.submitDeliverable(
                                    taskID: task.id,
                                    deliverable: Deliverable(
                                        id: UUID(), title: "新增成果連結", url: URL(string: "https://example.com"),
                                        submittedAt: .now, isApproved: false
                                    )
                                )
                            } label: {
                                Label("上傳檔案或貼上連結", systemImage: "paperclip")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BombTheme.ink)
                        }
                        .comicCard()
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("我的任務")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BombTheme.yellow, for: .navigationBar)
    }
}
