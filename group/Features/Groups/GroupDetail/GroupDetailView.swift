import SwiftUI
import UIKit

/// Group detail backed by the app's shared Group, Member, and ProjectTask data.
struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let group: Group
    let model: AppStore
    private let tutorialStep: Binding<TutorialStep?>?

    @State private var showsCopiedFeedback = false
    @State private var showsPublishTaskSheet = false
    @State private var expandedMemberID: UUID?
    @State private var reviewDeferred = false
    @State private var peerReviewStartsAtOutcomeSummary = true
    @State private var peerReviewRevision = 0
    @State private var showsExplosionMeme = true
    @State private var showsSuccessMeme = true
    @State private var showsDeadlineSheet = false
    @State private var deadlineDraft = Date.now
    @State private var deadlineError: String?
    @State private var showsNameSheet = false
    @State private var nameDraft = ""
    @State private var nameError: String?

    init(
        group: Group,
        model: AppStore,
        tutorialStep: Binding<TutorialStep?>? = nil
    ) {
        self.group = group
        self.model = model
        self.tutorialStep = tutorialStep
    }

#if DEBUG
    @State private var debugDeadlineOutcome: GroupDeadlineOutcome?
    @State private var showsDebugPanel = false
#endif

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    ZStack {
                        BombTheme.yellow.ignoresSafeArea()

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                if shouldShowContinueReviewBanner(now: context.date) {
                                    continueReviewBanner(now: context.date)
                                }
                                groupIdentity
                                countdownCard(now: context.date)
                                memberSection
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 120)
                        }
                        .scrollIndicators(.hidden)
                    }

                    if showsPublishTaskSheet {
                        BombTheme.ink.opacity(0.16)
                            .ignoresSafeArea(edges: .top)
                            .onTapGesture { closePublishTaskSheet() }
                            .transition(.opacity)

                        PublishTaskSheet(
                            group: currentGroup,
                            members: groupMembers,
                            onPublish: { title, detail, assigneeID, deadline in
                                try model.publishTask(
                                    title: title,
                                    detail: detail,
                                    groupID: group.id,
                                    assigneeMemberID: assigneeID,
                                    deadline: deadline
                                )
                            },
                            onCancel: closePublishTaskSheet
                        )
                        .frame(height: proxy.size.height * 0.82)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if shouldShowPeerReview(now: context.date) {
                        let outcome = deadlineOutcome(now: context.date)
                        let projectProgress = model.projectProgress(for: group.id)

                        PeerReviewOverlay(
                            group: currentGroup,
                            outcome: outcome,
                            projectProgress: projectProgress,
                            startsAtOutcomeSummary: startsAtPeerReviewSummary,
                            members: groupMembers,
                            currentUserID: model.currentUserID,
                            tasks: model.projectTasks.filter { $0.groupID == group.id },
                            reviews: model.reviews(for: group.id),
                            completedReviewerCount: model.completedPeerReviewerCount(in: group.id),
                            onSubmit: { revieweeID, taskScore, discussionScore, collaborationScore, ideaScore, reliabilityScore, comment in
                                try model.submitPeerReview(
                                    groupID: group.id,
                                    reviewerID: model.currentUserID,
                                    revieweeID: revieweeID,
                                    taskCompletionScore: taskScore,
                                    discussionScore: discussionScore,
                                    collaborationScore: collaborationScore,
                                    ideaScore: ideaScore,
                                    reliabilityScore: reliabilityScore,
                                    comment: comment,
                                    now: reviewSubmissionDate(now: context.date)
                                )
                            },
                            onLater: {
                                withAnimation(.snappy) { reviewDeferred = true }
                            }
                        )
                        .id(peerReviewOverlayIdentity)
                        .zIndex(20)
                        .transition(.opacity)
                    }

                    if shouldShowExplosionMeme(now: context.date) {
                        ExplosionMemeOverlay(
                            groupName: group.name,
                            progress: model.projectProgress(for: group.id),
                            incompleteTaskCount: model.projectTasks.filter {
                                $0.groupID == group.id && $0.progress < 100
                            }.count,
                            onViewDamage: {
                                peerReviewStartsAtOutcomeSummary = true
                                peerReviewRevision += 1
                                withAnimation(.snappy) { showsExplosionMeme = false }
                            },
                            onLater: {
                                withAnimation(.snappy) {
                                    showsExplosionMeme = false
                                    reviewDeferred = true
                                }
                            }
                        )
                        .zIndex(25)
                        .transition(.opacity)
                    }

                    if shouldShowSuccessMeme(now: context.date) {
                        SuccessMemeOverlay(
                            groupName: group.name,
                            onViewSummary: {
                                peerReviewStartsAtOutcomeSummary = true
                                peerReviewRevision += 1
                                withAnimation(.snappy) { showsSuccessMeme = false }
                            },
                            onLater: {
                                withAnimation(.snappy) {
                                    showsSuccessMeme = false
                                    reviewDeferred = true
                                }
                            }
                        )
                        .zIndex(25)
                        .transition(.opacity)
                    }

#if DEBUG
                    if showsDebugPanel {
                        debugPanel
                            .zIndex(30)
                            .transition(.opacity)
                    }
#endif
                }
                .animation(.snappy, value: shouldShowPeerReview(now: context.date))
                .animation(.snappy, value: shouldShowExplosionMeme(now: context.date))
                .animation(.snappy, value: shouldShowSuccessMeme(now: context.date))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .onAppear { deadlineDraft = currentGroup.deadline }
        .sheet(isPresented: $showsDeadlineSheet) {
            DeadlineEditorSheet(deadline: $deadlineDraft, onSave: saveDeadline)
        }
        .sheet(isPresented: $showsNameSheet) {
            GroupNameEditorSheet(name: $nameDraft, onSave: saveName)
        }
        .alert("無法修改期限", isPresented: Binding(
            get: { deadlineError != nil },
            set: { if !$0 { deadlineError = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(deadlineError ?? "")
        }
        .alert("無法修改群組名稱", isPresented: Binding(
            get: { nameError != nil },
            set: { if !$0 { nameError = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(nameError ?? "")
        }
    }

    private var topBar: some View {
        BombHeader(title: "專案任務", subtitle: currentGroup.name) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(BombHeaderButtonStyle())
            .accessibilityLabel("返回群組")
        } trailing: {
            HStack(spacing: 8) {
#if DEBUG
                debugMenu
#endif
                NavigationLink {
                    ChatRoomView(model: model, group: currentGroup, tutorialStep: tutorialStep)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel("聊天室")
                .tutorialTarget(
                    .chatButton,
                    enabled: tutorialStep?.wrappedValue == .chatEntry
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if tutorialStep?.wrappedValue == .chatEntry {
                            tutorialStep?.wrappedValue = .aiChat
                        }
                    }
                )
            }
        }
    }

#if DEBUG
    private var debugMenu: some View {
        Button {
            showsDebugPanel = true
        } label: {
            Text("測試")
                .font(.caption2.weight(.black))
                .foregroundStyle(BombTheme.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(BombTheme.paper)
                .clipShape(.capsule)
                .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var debugPanel: some View {
        ZStack {
            BombTheme.ink.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { showsDebugPanel = false }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("互評測試")
                            .font(.title2.weight(.black))
                        Spacer()
                        Button("關閉") { showsDebugPanel = false }
                            .font(.caption.weight(.black))
                            .foregroundStyle(BombTheme.ink)
                            .buttonStyle(.plain)
                    }

                    debugAction("正常進行中") {
                        debugDeadlineOutcome = .active
                        reviewDeferred = false
                        showsExplosionMeme = false
                        showsSuccessMeme = false
                        peerReviewStartsAtOutcomeSummary = true
                        peerReviewRevision += 1
                    }
                    debugAction("成功拆彈摘要") {
                        presentDebugPeerReview(outcome: .completed, startsAtSummary: true)
                    }
                    debugAction("直接顯示成功梗圖") {
                        presentDebugSuccessMeme()
                    }
                    debugAction("直接顯示爆炸梗圖") {
                        presentDebugExplosionMeme()
                    }
                    debugAction("關閉爆炸梗圖") {
                        debugDeadlineOutcome = .incomplete
                        showsExplosionMeme = false
                        reviewDeferred = true
                    }
                    debugAction("重新顯示爆炸梗圖") {
                        presentDebugExplosionMeme()
                    }
                    debugAction("直接跳到戰損摘要") {
                        presentDebugPeerReview(outcome: .incomplete, startsAtSummary: true)
                    }
                    debugAction("直接跳到雷包點點名") {
                        let outcome = debugDeadlineOutcome == .completed ? GroupDeadlineOutcome.completed : .incomplete
                        presentDebugPeerReview(outcome: outcome, startsAtSummary: false, resetReviews: true)
                    }
                    debugAction("模擬部分成員已評分") {
                        seedCurrentUserReviews(count: 1)
                        presentDebugPeerReview(outcome: .incomplete, startsAtSummary: false)
                    }
                    debugAction("模擬全部評分完成") {
                        seedAllPeerReviews()
                        presentDebugPeerReview(outcome: .incomplete, startsAtSummary: false)
                    }
                    debugAction("重設互評進度") {
                        let outcome = debugDeadlineOutcome == .completed ? GroupDeadlineOutcome.completed : .incomplete
                        presentDebugPeerReview(outcome: outcome, startsAtSummary: true, resetReviews: true)
                    }
                    debugAction("重新顯示結果摘要") {
                        let outcome = debugDeadlineOutcome == .completed ? GroupDeadlineOutcome.completed : .incomplete
                        presentDebugPeerReview(outcome: outcome, startsAtSummary: true)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 360, maxHeight: 620)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
            .shadow(color: BombTheme.ink, radius: 0, x: 6, y: 6)
            .padding(18)
        }
    }

    private func debugAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showsDebugPanel = false
        } label: {
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(BombTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(BombTheme.yellow.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(BombTheme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func seedCurrentUserReviews(count: Int) {
        model.resetPeerReviews(for: group.id)
        for member in groupMembers.filter({ $0.id != model.currentUserID }).prefix(count) {
            seedPeerReview(reviewerID: model.currentUserID, revieweeID: member.id)
        }
    }

    private func seedAllPeerReviews() {
        model.resetPeerReviews(for: group.id)
        for reviewer in groupMembers {
            for reviewee in groupMembers where reviewer.id != reviewee.id {
                seedPeerReview(reviewerID: reviewer.id, revieweeID: reviewee.id)
            }
        }
    }

    private func seedPeerReview(reviewerID: UUID, revieweeID: UUID) {
        _ = try? model.submitPeerReview(
            groupID: group.id,
            reviewerID: reviewerID,
            revieweeID: revieweeID,
            taskCompletionScore: 4,
            discussionScore: 4,
            collaborationScore: 4,
            ideaScore: 4,
            reliabilityScore: 4,
            comment: "",
            now: currentGroup.deadline.addingTimeInterval(1)
        )
    }

    private func presentDebugPeerReview(
        outcome: GroupDeadlineOutcome,
        startsAtSummary: Bool,
        resetReviews: Bool = false
    ) {
        if resetReviews {
            model.resetPeerReviews(for: group.id)
        }
        debugDeadlineOutcome = outcome
        showsExplosionMeme = false
        showsSuccessMeme = false
        peerReviewStartsAtOutcomeSummary = startsAtSummary
        reviewDeferred = false
        peerReviewRevision += 1
    }

    private func presentDebugExplosionMeme() {
        debugDeadlineOutcome = .incomplete
        showsExplosionMeme = true
        showsSuccessMeme = false
        reviewDeferred = false
        peerReviewStartsAtOutcomeSummary = true
        peerReviewRevision += 1
    }

    private func presentDebugSuccessMeme() {
        debugDeadlineOutcome = .completed
        showsExplosionMeme = false
        showsSuccessMeme = true
        reviewDeferred = false
        peerReviewStartsAtOutcomeSummary = true
        peerReviewRevision += 1
    }
#endif

    private func deadlineOutcome(now: Date) -> GroupDeadlineOutcome {
#if DEBUG
        if let debugDeadlineOutcome { return debugDeadlineOutcome }
#endif
        return GroupDeadlineOutcome.resolve(
            deadline: currentGroup.deadline,
            progress: model.projectProgress(for: group.id),
            now: now
        )
    }

    private func shouldShowPeerReview(now: Date) -> Bool {
        deadlineOutcome(now: now) != .active
            && !reviewDeferred
            && !shouldShowExplosionMeme(now: now)
            && !shouldShowSuccessMeme(now: now)
    }

    private func shouldShowExplosionMeme(now: Date) -> Bool {
        deadlineOutcome(now: now) == .incomplete
            && showsExplosionMeme
            && !reviewDeferred
    }

    private func shouldShowSuccessMeme(now: Date) -> Bool {
        deadlineOutcome(now: now) == .completed
            && showsSuccessMeme
            && !reviewDeferred
    }

    private func isBlockingOverlayVisible(now: Date) -> Bool {
        shouldShowPeerReview(now: now)
            || shouldShowExplosionMeme(now: now)
            || shouldShowSuccessMeme(now: now)
    }

    private var startsAtPeerReviewSummary: Bool {
        peerReviewStartsAtOutcomeSummary
    }

    private var peerReviewOverlayIdentity: String {
        "\(group.id.uuidString)-\(peerReviewRevision)"
    }

    private func shouldShowContinueReviewBanner(now: Date) -> Bool {
        deadlineOutcome(now: now) != .active
            && reviewDeferred
            && remainingReviewCount > 0
    }

    private var remainingReviewCount: Int {
        let reviewedMemberIDs = Set(
            model.reviews(for: group.id)
                .filter { $0.reviewerMemberID == model.currentUserID }
                .map(\.revieweeMemberID)
        )
        return group.memberIDs
            .filter { $0 != model.currentUserID && !reviewedMemberIDs.contains($0) }
            .count
    }

    private func continueReviewBanner(now: Date) -> some View {
        let alertOrange = Color(red: 0.94, green: 0.34, blue: 0.12)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(BombTheme.ink)
                Text("尚有匿名互評未完成")
                    .font(.headline.weight(.black))
            }

            HStack {
                Text("還剩 \(remainingReviewCount) 位隊員")
                    .font(.subheadline.weight(.bold))

                Spacer()

                Button("繼續評分") {
                    peerReviewStartsAtOutcomeSummary = false
                    peerReviewRevision += 1
                    withAnimation(.snappy) { reviewDeferred = false }
                }
                .font(.subheadline.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BombTheme.ink)
                .clipShape(.capsule)
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(alertOrange)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, lineWidth: 3))
    }

    private func reviewSubmissionDate(now: Date) -> Date {
#if DEBUG
        if debugDeadlineOutcome == .completed || debugDeadlineOutcome == .incomplete {
            return currentGroup.deadline.addingTimeInterval(1)
        }
#endif
        return now
    }

    private var groupIdentity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentGroup.name)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("群組代碼：\(currentGroup.inviteCode)")
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)

                Button(action: copyInviteCode) {
                    Label("複製", systemImage: "doc.on.doc.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)

                ShareLink(
                    item: "加入「\(currentGroup.name)」的群組，邀請碼：\(currentGroup.inviteCode)"
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }

                Menu {
                    Button("修改群組名稱", systemImage: "pencil") {
                        nameDraft = currentGroup.name
                        showsNameSheet = true
                    }

                    Button("修改截止時間", systemImage: "calendar.badge.clock") {
                        deadlineDraft = currentGroup.deadline
                        showsDeadlineSheet = true
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
                .accessibilityLabel("修改群組")
            }
            .tutorialTarget(
                .inviteCode,
                enabled: tutorialStep?.wrappedValue == .inviteCode
            )

            if showsCopiedFeedback {
                Text("群組代碼已複製")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func countdownCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(BombTheme.yellow)
                Text("行動代號：\(missionName)")
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text("LIVE")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(remainingTime(now: now))
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)

                Text("\(groupProgress)%")
                    .font(.system(.title2, design: .rounded, weight: .black))
            }

            ProgressView(value: Double(groupProgress), total: 100)
                .tint(BombTheme.yellow)
                .scaleEffect(y: 1.8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(BombTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .top) {
            HazardStripe()
                .clipShape(.capsule)
                .padding(.horizontal, 22)
                .offset(y: -5)
        }
    }

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("成員進度")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Button {
                    withAnimation(.snappy) { showsPublishTaskSheet = true }
                } label: {
                    Text(isGroupDeadlinePassed ? "已截止" : "＋ 發布任務")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .tutorialTarget(
                    .publishTask,
                    enabled: tutorialStep?.wrappedValue == .publishTask
                )
                .disabled(isGroupDeadlinePassed)
                .opacity(isGroupDeadlinePassed ? 0.45 : 1)
            }

            ForEach(groupMembers) { member in
                MemberProgressCard(
                    member: memberProgressItem(for: member),
                    tasks: model.tasks(for: member.id, in: group.id),
                    groupMemberIDs: currentGroup.memberIDs,
                    currentUserID: model.currentUserID,
                    isCurrentUser: member.id == model.currentUserID,
                    isExpanded: expandedMemberID == member.id,
                    onToggleExpanded: {
                        withAnimation(.snappy) {
                            expandedMemberID = expandedMemberID == member.id ? nil : member.id
                        }
                    },
                    onSubmitDeliverable: { taskID, deliverable in
                        model.submitDeliverable(taskID: taskID, deliverable: deliverable)
                    },
                    onToggleSubtask: { taskID, subtaskID in
                        model.toggleSubtask(taskID: taskID, subtaskID: subtaskID)
                    },
                    onConfirmDeliverable: { taskID in
                        model.confirmDeliverable(taskID: taskID, memberID: model.currentUserID)
                    },
                    onPoke: { style in
                        model.poke(memberID: member.id, in: group.id, style: style)
                    }
                )
                .tutorialTarget(
                    .memberProgress,
                    enabled: tutorialStep?.wrappedValue == .memberProgress
                        && member.id == groupMembers.first?.id
                )
            }
        }
    }

    private var groupMembers: [Member] {
        currentGroup.memberIDs.compactMap { memberID in
            guard var member = model.members.first(where: { $0.id == memberID }) else { return nil }
            member.role = currentGroup.memberRoles[memberID] ?? member.role
            return member
        }
    }

    private var currentGroup: Group {
        model.groups.first(where: { $0.id == group.id }) ?? group
    }

    private var groupProgress: Int {
        model.projectProgress(for: group.id)
    }

    private var isGroupDeadlinePassed: Bool {
        currentGroup.deadline <= .now
    }

    private var missionName: String {
        let name = currentGroup.name.replacingOccurrences(of: "拆彈小隊", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? currentGroup.name : name
    }

    private func remainingTime(now: Date) -> String {
        let remaining = max(0, Int(currentGroup.deadline.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = remaining % 86_400 / 3_600
        let minutes = remaining % 3_600 / 60

        if remaining == 0 {
            return "已截止"
        }

        return "\(days) 天 \(hours) 小時 \(minutes) 分鐘"
    }

    private func memberProgressItem(for member: Member) -> MemberProgressPreviewItem {
        let tasks = model.tasks(for: member.id, in: group.id)
        let currentTask = tasks.max(by: { $0.createdAt < $1.createdAt })
        let progress = model.memberProgress(for: member.id, in: group.id)

        return MemberProgressPreviewItem(
            id: member.id.uuidString,
            name: member.name,
            role: member.role.title,
            progress: progress,
            currentTask: currentTask?.title ?? "尚未指派任務",
            status: currentTask?.status.title ?? "待命",
            showsNudge: currentTask != nil && progress < 50
        )
    }

    private func copyInviteCode() {
        UIPasteboard.general.string = currentGroup.inviteCode
        withAnimation(.snappy) { showsCopiedFeedback = true }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { showsCopiedFeedback = false }
        }
    }

    private func closePublishTaskSheet() {
        withAnimation(.snappy) { showsPublishTaskSheet = false }
    }

    private func saveDeadline() {
        do {
            try model.updateGroupDeadline(groupID: group.id, deadline: deadlineDraft)
            showsDeadlineSheet = false
        } catch {
            deadlineError = error.localizedDescription
        }
    }

    private func saveName() {
        do {
            try model.updateGroupName(groupID: group.id, name: nameDraft)
            showsNameSheet = false
        } catch {
            nameError = error.localizedDescription
        }
    }
}

private struct DeadlineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var deadline: Date
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "截止時間",
                    selection: $deadline,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .navigationTitle("修改截止時間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { onSave() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GroupNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("群組名稱", text: $name)
            }
            .navigationTitle("修改群組名稱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { onSave() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ExplosionMemeOverlay: View {
    let groupName: String
    let progress: Int
    let incompleteTaskCount: Int
    let onViewDamage: () -> Void
    let onLater: () -> Void
    @State private var shareImage: Image?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BombTheme.ink.opacity(0.6)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 28, weight: .black))
                                .foregroundStyle(BombTheme.red)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("任務爆炸")
                                    .font(.system(.title, design: .rounded, weight: .black))
                                Text("截止時間已到")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }

                        FailureMemeImage(
                            groupName: groupName,
                            progress: progress,
                            incompleteTaskCount: incompleteTaskCount
                        )
                            .frame(
                                width: min(340, proxy.size.width - 64),
                                height: min(340, proxy.size.width - 64)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(BombTheme.ink, lineWidth: 2)
                            )
                            .accessibilityLabel("爆炸專案梗圖")

                        VStack(spacing: 9) {
                            Text(groupName)
                                .font(.title3.weight(.black))
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                Text("完成率 \(progress)%")
                                Text("｜")
                                    .foregroundStyle(.secondary)
                                Text("未完成任務 \(incompleteTaskCount) 項")
                            }
                            .font(.subheadline.weight(.black))
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(BombTheme.yellow.opacity(0.32))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))

                        Text("本次任務未能如期完成，\n請查看戰損並完成匿名隊員互評。")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.76))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if let shareImage {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview("\(groupName) 任務結算", image: shareImage)
                            ) {
                                Label("分享結算梗圖", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(BombTheme.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BombTheme.yellow)
                                    .clipShape(.capsule)
                                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }

                        Button("查看戰損", action: onViewDamage)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BombTheme.ink)
                            .clipShape(.capsule)
                            .buttonStyle(.plain)

                        Button("稍後查看", action: onLater)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(BombTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BombTheme.paper)
                            .clipShape(.capsule)
                            .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                            .buttonStyle(.plain)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .background(BombTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(BombTheme.ink, lineWidth: 4))
                .shadow(color: BombTheme.ink, radius: 0, x: 7, y: 7)
                .frame(maxWidth: 560)
                .frame(maxHeight: max(320, proxy.size.height - 32))
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .task {
            shareImage = renderedShareImage
        }
    }

    @MainActor
    private var renderedShareImage: Image? {
        let renderer = ImageRenderer(
            content: FailureMemeImage(
                groupName: groupName,
                progress: progress,
                incompleteTaskCount: incompleteTaskCount
            )
            .frame(width: 340, height: 340)
        )

        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}

private struct FailureMemeImage: View {
    let groupName: String
    let progress: Int
    let incompleteTaskCount: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("ExplosionMemeProject")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: 0) {
                    MemeCaption(text: groupName, fontSize: proxy.size.width * 0.08)
                        .offset(x: 30, y: 30)
                    Spacer()
                    MemeCaption(
                        text: "已讀不回的組員",
                        fontSize: proxy.size.width * 0.06
                    )
                    .offset(x: 45, y: 15)
                    Spacer()
                    MemeCaption(text: "我要放暑假了！", fontSize: proxy.size.width * 0.07)
                        .offset(x: -60, y: -20)
                }
                .padding(.vertical, proxy.size.height * 0.08)
                .padding(.horizontal, proxy.size.width * 0.06)
            }
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("\(groupName) 的任務爆炸梗圖，完成率 \(progress)%，尚有 \(incompleteTaskCount) 項任務未完成")
    }
}

private struct SuccessMemeOverlay: View {
    let groupName: String
    let onViewSummary: () -> Void
    let onLater: () -> Void
    @State private var shareImage: Image?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BombTheme.ink.opacity(0.6)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 28, weight: .black))
                                .foregroundStyle(BombTheme.green)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("成功拆彈")
                                    .font(.system(.title, design: .rounded, weight: .black))
                                Text("任務已全數完成")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }

                        SuccessMemeImage(groupName: groupName)
                            .frame(maxWidth: min(260, proxy.size.width - 64))
                            .accessibilityLabel("成功拆彈梗圖")

                        Text("這次任務如期完成，\n請完成匿名隊員互評。")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.76))
                            .multilineTextAlignment(.center)

                        if let shareImage {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview("\(groupName) 成功拆彈", image: shareImage)
                            ) {
                                Label("分享結算梗圖", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(BombTheme.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BombTheme.yellow)
                                    .clipShape(.capsule)
                                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }

                        Button("查看結算", action: onViewSummary)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BombTheme.ink)
                            .clipShape(.capsule)
                            .buttonStyle(.plain)

                        Button("稍後查看", action: onLater)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(BombTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BombTheme.paper)
                            .clipShape(.capsule)
                            .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                            .buttonStyle(.plain)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .background(BombTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(BombTheme.ink, lineWidth: 4))
                .shadow(color: BombTheme.ink, radius: 0, x: 7, y: 7)
                .frame(maxWidth: 560)
                .frame(maxHeight: max(320, proxy.size.height - 32))
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .task {
            shareImage = renderedShareImage
        }
    }

    @MainActor
    private var renderedShareImage: Image? {
        let renderer = ImageRenderer(
            content: SuccessMemeImage(groupName: groupName)
                .frame(width: 260, height: 425.1)
        )

        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}

private struct SuccessMemeImage: View {
    let groupName: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SuccessMemeProject")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: 0) {
                    MemeCaption(text: "你有多猛", fontSize: proxy.size.width * 0.09)
                        .offset(y: 140)
                    Spacer()
                    MemeCaption(
                        text: "我完成了\(groupName)",
                        fontSize: proxy.size.width * 0.075
                    )
                    .offset(y: 30)
                }
                .padding(.vertical, proxy.size.height * 0.1)
                .padding(.horizontal, proxy.size.width * 0.06)
            }
            .clipped()
        }
        .aspectRatio(600.0 / 981.0, contentMode: .fit)
        .accessibilityLabel("\(groupName) 的成功拆彈梗圖")
    }
}

private struct MemeCaption: View {
    let text: String
    let fontSize: CGFloat

    private let outlineOffsets: [CGFloat] = [-2, 0, 2]

    var body: some View {
        ZStack {
            ForEach(outlineOffsets, id: \.self) { horizontalOffset in
                ForEach(outlineOffsets, id: \.self) { verticalOffset in
                    if horizontalOffset != 0 || verticalOffset != 0 {
                        caption
                            .foregroundStyle(.black)
                            .offset(x: horizontalOffset, y: verticalOffset)
                    }
                }
            }

            caption
                .foregroundStyle(.white)
        }
        .padding(.horizontal, fontSize * 0.18)
    }

    private var caption: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .lineLimit(2)
    }
}

private struct GroupDetailPreview: View {
    @State private var model = AppStore(dataMode: .demo)

    var body: some View {
        NavigationStack {
            if let group = model.groups.first {
                GroupDetailView(group: group, model: model)
            }
        }
    }
}

#Preview("Group detail") {
    GroupDetailPreview()
}
