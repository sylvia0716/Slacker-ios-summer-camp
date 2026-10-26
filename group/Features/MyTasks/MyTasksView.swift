import SwiftUI

/// Second tab: aggregates the current user's tasks and opens task delivery details.
struct MyTasksView: View {
    let model: AppStore
    let isSelected: Bool
    @State private var showCompleted = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: AppStore, isSelected: Bool = true) {
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
                    if !pendingTasks.isEmpty || !completedTasks.isEmpty {
                        // 儀表環是尺寸固定的 Canvas，不會跟著文字長大，所以讀數無上限
                        // 放大時會撞出環外、蓋住 0／100 刻度。封頂只套在這張圖表上；
                        // 底下的任務清單不受影響，維持完整縮放。
                        //
                        // 封頂必須加在呼叫端：@ScaledMetric 讀的是父層傳入的環境，
                        // 在 TaskProgressDashboard 自己的 body 裡加沒有作用。
                        TaskProgressDashboard(progress: personalProgress, isActive: isSelected)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }

                    if model.cloudGroupSyncErrorMessage != nil && !model.projectTasks.isEmpty {
                        staleTasksBanner
                    }

                    taskStatusSwitch

                    if model.isLoadingCloudGroups && model.projectTasks.isEmpty {
                        ProgressView(L10n.text("正在同步任務…"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 42)
                    } else if let syncError = model.cloudGroupSyncErrorMessage,
                              model.projectTasks.isEmpty {
                        BombEmptyState(
                            systemImage: "exclamationmark.triangle.fill",
                            title: L10n.text("無法載入任務"),
                            message: syncError,
                            verticalPadding: 42
                        ) {
                            Button(L10n.text("重新整理")) {
                                Task { await model.reloadCloudGroups() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BombTheme.ink)
                            .padding(.top, 4)
                        }
                    } else if visibleTasks.isEmpty {
                        BombEmptyState(
                            systemImage: showCompleted ? "checkmark.seal.fill" : "bolt.fill",
                            title: showCompleted ? L10n.text("還沒有完成任務") : L10n.text("目前沒有待完成任務"),
                            verticalPadding: 42
                        )
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
            BombHeader(title: L10n.text("我的任務")) {
                NotificationBellButton(model: model)
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

    /// 兩個選項並排時各只分到約 135pt，輔助使用字級下三個中文字塞不下就會
    /// 折行成「待 完成」。這是內容不是外框，所以改排列方式而不是限制縮放：
    /// 大字級時改縱向，每個選項獨佔整個寬度。
    private var taskStatusSwitch: some View {
        let isAccessibility = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibility
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))

        return layout {
            ForEach([false, true], id: \.self) { completed in
                Button {
                    showCompleted = completed
                } label: {
                    Text(L10n.text(completed ? "已完成" : "待完成"))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(showCompleted == completed ? BombTheme.ink : BombTheme.paper)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(showCompleted == completed ? BombTheme.paper : .clear, in: Capsule())
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showCompleted == completed ? [.isSelected] : [])
            }
        }
        .padding(3)
        // 縱向時膠囊會變成細長的跑道形，所以外框改用卡片圓角。
        .background(BombTheme.ink, in: RoundedRectangle(cornerRadius: isAccessibility ? BombRadius.card : 999))
        .frame(maxWidth: isAccessibility ? .infinity : 280)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("任務狀態"))
    }

    private var staleTasksBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(L10n.text("任務同步失敗，顯示上次同步資料"))
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 8)
            Button(L10n.text("重試")) {
                Task { await model.reloadCloudGroups() }
            }
            .font(.subheadline.weight(.black))
        }
        .foregroundStyle(BombTheme.ink)
        .padding(12)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: BombRadius.control, style: .continuous))
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
    /// 百分比是儀表板的主要讀數；縮放上限由 minimumScaleFactor 擋住，避免溢出儀表。
    @ScaledMetric(relativeTo: .largeTitle) private var readoutSize: CGFloat = 46

    var body: some View {
        ZStack {
            ProgressDial(progress: animatedProgress)

            VStack(spacing: 7) {
                Text("\(Int(animatedProgress.rounded()))%")
                    .font(.system(size: readoutSize, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(BombTheme.ink)

                Text(L10n.text("待完成任務進度"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BombTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 1.5))
            }
            .offset(y: 31)
        }
        .frame(height: 220)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusDot: some View {
        Circle()
            .fill(task.isCompleted ? BombTheme.green : (isOverdue ? BombTheme.red : BombTheme.yellow))
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    private var titleText: some View {
        Text(task.title)
            .font(.system(.title3, design: .rounded, weight: .black))
            .foregroundStyle(task.isCompleted ? Color.secondary : BombTheme.ink)
            .strikethrough(task.isCompleted)
    }

    private var groupNameText: some View {
        Text(groupName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(BombTheme.secondaryText)
    }

    private var progressText: some View {
        Text("\(task.progress)%")
            .font(.system(.title3, design: .rounded, weight: .black).monospacedDigit())
            .fixedSize()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.body.weight(.black))
            .accessibilityHidden(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // 一般字級維持一整列；輔助使用字級下百分比（fixedSize）與箭頭會吃掉
            // 大半寬度，標題只剩幾個字，單純放寬 lineLimit 只會讓它逐字直排。
            // 所以改成標題獨佔一列、百分比與箭頭退到下一列。
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        statusDot
                        titleText
                    }
                    if !groupName.isEmpty { groupNameText }
                    HStack(spacing: 8) {
                        progressText
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            } else {
                HStack(spacing: 8) {
                    statusDot

                    VStack(alignment: .leading, spacing: 2) {
                        titleText.lineLimit(2)
                        if !groupName.isEmpty { groupNameText.lineLimit(1) }
                    }

                    Spacer(minLength: 0)

                    progressText
                    chevron
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if task.isCompleted {
                    Label(L10n.text("已完成"), systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BombTheme.green)
                } else if task.deadline != .distantFuture {
                    Label(TaskRemainingTime(deadline: task.deadline).text, systemImage: "clock")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isOverdue ? BombTheme.red : Color.secondary)
                }

                HStack(spacing: 16) {
                    ProgressView(value: Double(task.progress), total: 100)
                        .tint(BombTheme.ink)

                    Text("\(task.subtasks.filter(\.isComplete).count)/\(task.subtasks.count)")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .fixedSize()
                        .accessibilityLabel(L10n.format(
                            "{0}/{1} 子任務",
                            String(task.subtasks.filter(\.isComplete).count),
                            String(task.subtasks.count)
                        ))
                }
            }
        }
        .foregroundStyle(BombTheme.ink)
        .padding(16)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: BombRadius.panel))
        .overlay(RoundedRectangle(cornerRadius: BombRadius.panel).stroke(BombTheme.ink, lineWidth: 3))
        .padding(.vertical, 2)
    }

    private var isOverdue: Bool {
        !task.isCompleted && task.deadline < .now
    }
}

private struct TaskRemainingTime {
    let deadline: Date

    var text: String {
        let remainingInterval = deadline.timeIntervalSinceNow
        guard remainingInterval > 0 else { return L10n.text("已逾期") }
        let days = Int(remainingInterval / 86_400)
        let hours = Int(remainingInterval / 3_600)
        let minutes = max(1, Int(ceil(remainingInterval / 60)))
        if days > 0 { return L10n.format("剩 {0} 天", String(days)) }
        if hours > 0 { return L10n.format("剩 {0} 小時", String(hours)) }
        return L10n.format("剩 {0} 分鐘", String(minutes))
    }
}

struct MyTaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AppStore
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
                title: L10n.text("任務詳情"),
                subtitle: task.flatMap { task in
                    model.groups.first { $0.id == task.groupID }?.name
                }
            ) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel(L10n.text("返回我的任務"))
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
            .padding(.vertical, 14)
    }

    private func taskOverview(_ task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(L10n.text("任務"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(BombTheme.yellow, in: Capsule())

                Text(task.title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(task.isCompleted ? Color.secondary : BombTheme.ink)
                    .strikethrough(task.isCompleted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text("\(task.progress)%")
                    .font(.system(.title3, design: .rounded, weight: .black).monospacedDigit())
                    .monospacedDigit()
            }

            if !task.detail.isEmpty {
                Text(task.detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BombTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ProgressView(value: Double(task.progress), total: 100)
                    .tint(BombTheme.ink)

                Text(L10n.format(
                    "{0}/{1} 子任務",
                    String(describing: task.subtasks.filter(\.isComplete).count),
                    String(describing: task.subtasks.count)
                ))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BombTheme.secondaryText)
                .fixedSize()
            }
        }
    }

    private func subtaskSection(_ task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("子任務"), systemImage: "arrow.turn.down.right")
                    .font(.headline.weight(.black))
                Spacer()
                Text(L10n.format(
                    "已完成 {0}/{1}",
                    String(describing: task.subtasks.filter(\.isComplete).count),
                    String(describing: task.subtasks.count)
                ))
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(BombTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(task.subtasks) { subtask in
                    Button {
                        Task { await model.toggleSubtask(taskID: task.id, subtaskID: subtask.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: subtask.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(subtask.isComplete ? BombTheme.green : BombTheme.ink.opacity(0.55))
                            Text(subtask.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(subtask.isComplete ? .secondary : BombTheme.ink)
                                .strikethrough(subtask.isComplete)
                            Spacer(minLength: 0)
                            if model.pendingSubtaskUpdates[subtask.id] != nil {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .contentShape(.rect)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(BombTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: BombRadius.inner))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(BombTheme.yellow)
                    .frame(width: 4)
            }
        }
    }

    private func deliverableSection(_ task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.text("成果交付"), systemImage: "paperclip")
                .font(.headline.weight(.black))

            if let deliverable = task.deliverable {
                AttachmentActionButton(model: model, taskID: task.id, deliverable: deliverable) {
                    HStack(spacing: 12) {
                        Image(systemName: deliverable.url == nil ? "doc.fill" : "link")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(BombTheme.yellow.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: BombRadius.inner, style: .continuous))

                        Text(deliverable.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Text(deliverable.isApproved ? L10n.text("已驗收") : L10n.text("待驗收"))
                            .font(.caption.weight(.black))
                            .foregroundStyle(deliverable.isApproved ? BombTheme.green : BombTheme.secondaryText)
                    }
                }
            } else {
                Text(L10n.text("尚未提交成果"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BombTheme.secondaryText)
            }

            Button {
                showsSubmissionSheet = true
            } label: {
                Label(task.deliverable == nil ? L10n.text("提交成果") : L10n.text("更新成果"), systemImage: "paperclip")
            }
            .buttonStyle(BombFormPrimaryButtonStyle())
        }
    }
}

private struct TaskDetailCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: BombRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BombRadius.control, style: .continuous)
                    .stroke(BombTheme.ink, lineWidth: 3)
            }
    }
}

private extension View {
    func taskDetailCard() -> some View {
        modifier(TaskDetailCard())
    }
}
