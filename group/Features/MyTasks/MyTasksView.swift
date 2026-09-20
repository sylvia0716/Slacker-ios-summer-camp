import SwiftUI

/// Second tab: aggregates the current user's tasks and opens task delivery details.
struct MyTasksView: View {
    let model: GroupBombModel
    let isSelected: Bool
    @State private var showCompleted = false

    init(model: GroupBombModel, isSelected: Bool = true) {
        self.model = model
        self.isSelected = isSelected
    }

    private var pendingTasks: [ProjectTask] {
        model.projectTasks.filter {
            $0.ownerMemberID == model.currentUserID && !$0.isCompleted
        }
        .sorted(by: deadlineAscending)
    }

    private var completedTasks: [ProjectTask] {
        model.projectTasks.filter {
            $0.ownerMemberID == model.currentUserID && $0.isCompleted
        }
        .sorted(by: deadlineAscending)
    }

    private var visibleTasks: [ProjectTask] {
        showCompleted ? completedTasks : pendingTasks
    }

    private func deadlineAscending(_ lhs: ProjectTask, _ rhs: ProjectTask) -> Bool {
        if lhs.deadline != rhs.deadline { return lhs.deadline < rhs.deadline }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !showCompleted && !pendingTasks.isEmpty {
                        TaskProgressDashboard(progress: personalProgress, isActive: isSelected)
                    }

                    if model.cloudGroupSyncErrorMessage != nil && !model.projectTasks.isEmpty {
                        staleTasksBanner
                    }

                    Picker("任務狀態", selection: $showCompleted) {
                        Text("待完成").tag(false)
                        Text("已完成").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .tint(.white)

                    if model.isLoadingCloudGroups && model.projectTasks.isEmpty {
                        ProgressView("正在同步任務…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 42)
                    } else if let syncError = model.cloudGroupSyncErrorMessage,
                              model.projectTasks.isEmpty {
                        ContentUnavailableView {
                            Label("無法載入任務", systemImage: "exclamationmark.triangle.fill")
                        } description: {
                            Text(syncError)
                        } actions: {
                            Button("重新整理") {
                                Task { await model.reloadCloudGroups() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BombTheme.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                    } else if visibleTasks.isEmpty {
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
                                MyTaskCard(task: task, groupName: group?.name ?? "")
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
            for task in model.projectTasks where task.ownerMemberID == model.currentUserID {
                model.startAttachmentSync(for: task.id)
            }
        }
    }

    private var staleTasksBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("任務同步失敗，顯示上次同步資料")
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 8)
            Button("重試") {
                Task { await model.reloadCloudGroups() }
            }
            .font(.subheadline.weight(.black))
        }
        .foregroundStyle(BombTheme.ink)
        .padding(12)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var personalProgress: Int {
        model.pendingMemberProgress(for: model.currentUserID)
    }
}

/// 半圓進度儀表板由新版子任務完成比例驅動，不再建立第二份進度資料。
private struct TaskProgressDashboard: View {
    let progress: Int
    let isActive: Bool
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

                Text("待完成任務進度")
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
            if isActive { animateProgress(fromZero: true) }
        }
        .onDisappear {
            resetAnimation()
        }
        .onChange(of: isActive) { _, isActive in
            if isActive {
                animateProgress(fromZero: true)
            } else {
                resetAnimation()
            }
        }
        .onChange(of: progress) {
            if isActive {
                animateProgress(fromZero: false)
            } else {
                animatedProgress = 0
            }
        }
    }

    private func resetAnimation() {
        animationTask?.cancel()
        animationTask = nil
        animatedProgress = 0
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
                let endpoint = point(center: center, radius: radius, angle: angle)
                let location = CGPoint(
                    x: min(max(endpoint.x, 18), size.width - 18),
                    y: endpoint.y + 22
                )
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
                if task.deadline != .distantFuture {
                    Label { Text(TaskRemainingTime(deadline: task.deadline).text) } icon: { Image(systemName: "clock.fill") }
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
        let remainingInterval = deadline.timeIntervalSinceNow
        guard remainingInterval > 0 else { return "已逾期" }
        let seconds = Int(remainingInterval)
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
                    VStack(alignment: .leading, spacing: 0) {
                        taskOverview(task)

                        sectionDivider

                        subtaskSection(task)

                        sectionDivider

                        deliverableSection(task)
                    }
                    .taskDetailCard()
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
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

    private var sectionDivider: some View {
        Divider()
            .overlay(BombTheme.ink.opacity(0.18))
            .padding(.vertical, 18)
    }

    private func taskOverview(_ task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(task.status.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(task.isCompleted ? BombTheme.green : BombTheme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(task.isCompleted ? BombTheme.green.opacity(0.12) : BombTheme.yellow)
                        .clipShape(.capsule)
                }

                Spacer(minLength: 8)

                Text("\(task.progress)%")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(BombTheme.yellow)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
            }

            if !task.detail.isEmpty {
                Text(task.detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BombTheme.ink.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView(value: Double(task.progress), total: 100)
                .tint(task.isCompleted ? BombTheme.green : BombTheme.red)
                .scaleEffect(y: 1.35)

            Label(
                "\(task.subtasks.filter(\.isComplete).count) / \(task.subtasks.count) 項子任務完成",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(BombTheme.ink.opacity(0.62))
        }
    }

    private func subtaskSection(_ task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("子任務", systemImage: "checklist")
                    .font(.headline.weight(.black))
                Spacer()
                Text("\(task.subtasks.filter(\.isComplete).count) / \(task.subtasks.count)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 5)

            ForEach(task.subtasks) { subtask in
                Button {
                    Task { await model.toggleSubtask(taskID: task.id, subtaskID: subtask.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: subtask.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(subtask.isComplete ? BombTheme.green : BombTheme.ink.opacity(0.72))
                        Text(subtask.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(subtask.isComplete ? .secondary : BombTheme.ink)
                            .strikethrough(subtask.isComplete)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)

                if subtask.id != task.subtasks.last?.id {
                    Divider()
                }
            }
        }
    }

    private func deliverableSection(_ task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("成果交付", systemImage: "shippingbox.fill")
                .font(.headline.weight(.black))

            if let deliverable = task.deliverable {
                AttachmentActionButton(model: model, taskID: task.id, deliverable: deliverable) {
                    HStack(spacing: 12) {
                        Image(systemName: deliverable.url == nil ? "doc.fill" : "link")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(BombTheme.yellow.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        Text(deliverable.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Text(deliverable.isApproved ? "已驗收" : "待驗收")
                            .font(.caption.weight(.black))
                            .foregroundStyle(deliverable.isApproved ? BombTheme.green : BombTheme.ink.opacity(0.56))
                    }
                }
            } else {
                Text("尚未提交成果")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button {
                showsSubmissionSheet = true
            } label: {
                Label(task.deliverable == nil ? "提交成果" : "更新成果", systemImage: "paperclip")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(BombTheme.ink)
            .clipShape(.capsule)
        }
    }
}

private struct TaskDetailCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BombTheme.ink, lineWidth: 2)
            }
    }
}

private extension View {
    func taskDetailCard() -> some View {
        modifier(TaskDetailCard())
    }
}
