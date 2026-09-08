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
                    TaskProgressDashboard(progress: personalProgress)

                    Picker("任務狀態", selection: $showCompleted) {
                        Text("待完成").tag(false)
                        Text("已完成").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .tint(.white)

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
                .padding(.horizontal, 18)
                .padding(.bottom, 112)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: "我的任務") {
                EmptyView()
            } trailing: {
                EmptyView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            model.startAttachmentSync(
                for: model.projectTasks.filter { $0.ownerMemberID == model.currentUserID }.map(\.id)
            )
        }
    }

    private var personalProgress: Int {
        guard let group = model.groups.first else { return 0 }
        return model.memberProgress(for: model.currentUserID, in: group.id)
    }
}

/// 半圓進度儀表板由新版子任務完成比例驅動，不再建立第二份進度資料。
private struct TaskProgressDashboard: View {
    let progress: Int
    @State private var animatedProgress = 0.0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            ProgressDial(progress: animatedProgress)

            VStack(spacing: 7) {
                Text("\(Int(animatedProgress.rounded()))%")
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
        .frame(height: 260)
        .onAppear {
            animateProgress(fromZero: true)
        }
        .onDisappear {
            animationTask?.cancel()
            animatedProgress = 0
        }
        .onChange(of: progress) {
            animateProgress(fromZero: false)
        }
    }

    private func animateProgress(fromZero: Bool) {
        animationTask?.cancel()

        let target = Double(min(max(progress, 0), 100))
        let start = fromZero ? 0 : animatedProgress
        if fromZero {
            animatedProgress = 0
        }

        animationTask = Task { @MainActor in
            if fromZero {
                try? await Task.sleep(for: .milliseconds(140))
            }

            let frameCount = 52
            for frame in 1...frameCount {
                guard !Task.isCancelled else { return }
                let time = Double(frame) / Double(frameCount)
                let eased = 1 - (1 - time) * (1 - time) * (1 - time)
                animatedProgress = start + (target - start) * eased
                try? await Task.sleep(for: .milliseconds(18))
            }

            animatedProgress = target
        }
    }
}

/// 儀表板的 Canvas 繪製；只負責視覺，不含任務商業邏輯。
private struct ProgressDial: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.78)
            let radius = min(size.width * 0.44, size.height * 0.64)
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
    let task: ProjectTask
    let groupName: String
    let deadline: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.title2.weight(.black))
                    Text(groupName).font(.body.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(task.progress)%")
                    .font(.title3.monospacedDigit().weight(.black))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
            }
            ProgressView(value: Double(task.progress), total: 100)
                .tint(task.isCompleted ? BombTheme.green : BombTheme.red)
                .scaleEffect(y: 1.6)
            HStack {
                if let deadline {
                    Label { Text(TaskRemainingTime(deadline: deadline).text) } icon: { Image(systemName: "clock.fill") }
                }
                Spacer()
                Label("查看任務", systemImage: "chevron.right")
            }
            .font(.body.weight(.bold))
        }
        .comicCard()
        .padding(.vertical, 2)
    }
}

private struct TaskRemainingTime {
    let deadline: Date

    var text: String {
        let seconds = max(0, Int(deadline.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days) day, \(hours) hr" }
        return "\(hours) hr, \(minutes) min"
    }
}

private struct MyTaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let model: GroupBombModel
    let taskID: UUID
    @State private var showsSubmissionSheet = false

    private var task: ProjectTask? { model.projectTasks.first { $0.id == taskID } }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            if let task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 22) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(task.title).font(.system(size: 32, weight: .black, design: .rounded))
                                    Spacer()
                                    Text("\(task.progress)%").font(.system(size: 32, weight: .black, design: .rounded))
                                }
                                Text(task.detail).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                                ProgressView(value: Double(task.progress), total: 100)
                                    .tint(task.isCompleted ? BombTheme.green : BombTheme.red)
                                    .scaleEffect(y: 1.7)

                                Text("子任務").font(.system(size: 30, weight: .black, design: .rounded))
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

                                Text("成果交付").font(.system(size: 30, weight: .black, design: .rounded))
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
                                showsSubmissionSheet = true
                            } label: {
                                Label("上傳檔案或貼上連結", systemImage: "paperclip")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BombTheme.ink)
                            .controlSize(.large)
                            }
                            .comicCard()
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 112)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .bombTabBarHidden()
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(
                title: "任務詳情",
                subtitle: task.flatMap { task in
                    model.groups.first { $0.id == task.groupID }?.name
                }
            ) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel("返回我的任務")
            } trailing: {
                EmptyView()
            }
        }
        .task { model.startAttachmentSync(for: taskID) }
        .sheet(isPresented: $showsSubmissionSheet) {
            if let task {
                DeliverableSubmissionSheet(task: task) { deliverable in
                    model.submitDeliverable(taskID: task.id, deliverable: deliverable)
                }
            }
        }
    }
}
