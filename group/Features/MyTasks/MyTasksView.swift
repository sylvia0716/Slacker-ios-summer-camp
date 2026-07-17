import SwiftUI

/// Second tab: aggregates the current user's tasks and opens task delivery details.
struct MyTasksView: View {
    let model: GroupBombModel
    @State private var showCompleted = false

    private var visibleTasks: [MissionTask] {
        model.tasks.filter {
            $0.owner == model.userName && $0.isComplete == showCompleted
        }
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("我的任務")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))

                    TaskProgressDashboard(progress: personalProgress)

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
                            NavigationLink {
                                MyTaskDetailView(model: model, taskID: task.id)
                            } label: {
                                MyTaskCard(task: task, groupName: model.groups.first?.name ?? "")
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

    private var personalProgress: Int {
        let mine = model.tasks.filter { $0.owner == model.userName }
        guard !mine.isEmpty else { return 0 }
        return mine.reduce(0) { $0 + $1.progress } / mine.count
    }
}

private struct TaskProgressDashboard: View {
    let progress: Int

    var body: some View {
        ZStack {
            ProgressDial(progress: Double(progress))
                .animation(.spring(duration: 0.65, bounce: 0.22), value: progress)

            VStack(spacing: 7) {
                Text("\(progress)%")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BombTheme.ink)

                Text("整體任務進度")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BombTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 1.5))
            }
            .offset(y: 31)
        }
        .frame(height: 190)
    }
}

private struct ProgressDial: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.82)
            let radius = min(size.width * 0.43, size.height * 0.70)
            let startAngle = 180.0
            let sweep = 180.0
            let clampedProgress = min(max(progress, 0), 100)

            let track = arcPath(center: center, radius: radius, start: startAngle, sweep: sweep)
            context.stroke(track, with: .color(.white.opacity(0.52)), style: StrokeStyle(lineWidth: 16, lineCap: .round))

            let progressPath = arcPath(
                center: center,
                radius: radius,
                start: startAngle,
                sweep: sweep * clampedProgress / 100
            )
            context.stroke(progressPath, with: .color(BombTheme.ink), style: StrokeStyle(lineWidth: 16, lineCap: .round))

            for tick in 0...10 {
                let angle = startAngle + sweep * Double(tick) / 10
                let outer = point(center: center, radius: radius - 17, angle: angle)
                let inner = point(center: center, radius: radius - (tick.isMultiple(of: 5) ? 34 : 28), angle: angle)
                var tickPath = Path()
                tickPath.move(to: inner)
                tickPath.addLine(to: outer)
                context.stroke(tickPath, with: .color(BombTheme.ink.opacity(0.42)), lineWidth: tick.isMultiple(of: 5) ? 2.5 : 1.3)
            }

            for marker in [0, 100] {
                let angle = startAngle + sweep * Double(marker) / 100
                let location = point(center: center, radius: radius + 22, angle: angle)
                context.draw(
                    Text("\(marker)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BombTheme.ink.opacity(0.62)),
                    at: location
                )
            }

        }
    }

    private func arcPath(center: CGPoint, radius: Double, start: Double, sweep: Double) -> Path {
        var path = Path()
        let steps = max(1, Int(abs(sweep) / 3))
        for step in 0...steps {
            let angle = start + sweep * Double(step) / Double(steps)
            let location = point(center: center, radius: radius, angle: angle)
            step == 0 ? path.move(to: location) : path.addLine(to: location)
        }
        return path
    }

    private func point(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }
}

private struct MyTaskCard: View {
    let task: MissionTask
    let groupName: String

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
                .tint(task.isComplete ? BombTheme.green : BombTheme.red)
            HStack {
                Label {
                    Text(task.deadline, style: .relative)
                } icon: {
                    Image(systemName: "clock.fill")
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

    private var task: MissionTask? {
        model.tasks.first { $0.id == taskID }
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            if let task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(task.title).font(.title2.weight(.black))
                                Spacer()
                                Text("\(task.progress)%").font(.title3.weight(.black))
                            }
                            Text(task.detail).font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: Double(task.progress), total: 100)
                                .tint(task.isComplete ? BombTheme.green : BombTheme.red)

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

                            Text("成果交付").font(.title2.weight(.black))
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(task.deliverables) { deliverable in
                                    HStack {
                                        Image(systemName: deliverable.url == nil ? "doc.fill" : "link")
                                        Text(deliverable.title).font(.subheadline.bold()).lineLimit(1)
                                        Spacer()
                                        Text(deliverable.isApproved ? "已驗收" : "待驗收")
                                            .font(.caption.bold())
                                            .foregroundStyle(deliverable.isApproved ? BombTheme.green : .secondary)
                                    }
                                }
                                HStack {
                                    Spacer()
                                    Button {
                                        model.addMockDeliverable(to: task.id)
                                    } label: {
                                        Label("上傳檔案或貼上連結", systemImage: "paperclip")
                                            .padding(.horizontal, 10)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(BombTheme.ink)
                                    .fixedSize()
                                    Spacer()
                                }
                            }
                        }
                        .comicCard()
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(model.groups.first?.name ?? "我的任務")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BombTheme.yellow, for: .navigationBar)
    }
}
