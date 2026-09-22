import SwiftUI
import UIKit

/// Group detail backed by the app's shared Group, Member, and ProjectTask data.
struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bombSafeAreaInsets) private var safeAreaInsets
    let group: Group
    let model: AppStore
    private let tutorialStep: Binding<TutorialStep?>?

    @State private var showsCopiedFeedback = false
    @State private var showsLeaderPicker = false
    @State private var selectedLeader: Member?
    @State private var selectedElectionID: String?
    @State private var isChoosingLeader = false
    @State private var leaderError: String?
    @State private var showsLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var pendingDepartureID: String?
    @State private var departureError: String?
    @State private var leaveError: String?
    @State private var showsPublishTaskSheet = false
    @State private var expandedMemberID: UUID?
    @State private var reviewDeferred = true
    @State private var peerReviewStartsAtOutcomeSummary = false
    @State private var peerReviewRevision = 0
    @State private var showsPeerReviewPage = false
    @State private var showsBattleReport = false
    @State private var showsExplosionMeme = false
    @State private var showsSuccessMeme = false
    @State private var hasConfiguredOutcomePresentation = false
    @State private var showsDeadlineSheet = false
    @State private var deadlineDraft = Date.now
    @State private var deadlineError: String?
    @State private var showsNameSheet = false
    @State private var nameDraft = ""
    @State private var nameError: String?
    @State private var pokeButtonEmoji: String?
    @State private var pokeButtonEmojiMemberID: String?
    @State private var isPokeButtonEmojiShaking = false

    init(
        group: Group,
        model: AppStore,
        tutorialStep: Binding<TutorialStep?>? = nil,
        opensPeerReview: Bool = false
    ) {
        self.group = group
        self.model = model
        self.tutorialStep = tutorialStep
        _peerReviewStartsAtOutcomeSummary = State(initialValue: !opensPeerReview)
        _showsExplosionMeme = State(initialValue: !opensPeerReview)
        _showsSuccessMeme = State(initialValue: !opensPeerReview)
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
                                VStack(alignment: .leading, spacing: 12) {
                                    groupIdentity
                                    if deadlineOutcome(now: context.date) == .active {
                                        countdownCard(now: context.date)
                                    } else {
                                        settlementSection(outcome: deadlineOutcome(now: context.date))
                                    }
                                }

                                if deadlineOutcome(now: context.date) == .active {
                                    memberSection
                                }
                                if currentGroup.leaderElectionID != nil { leadershipSection }
                                departedTasksSection
                                Button(role: .destructive) {
                                    showsLeaveConfirmation = true
                                } label: {
                                    Label(isLeaving ? L10n.text("退出中…") : L10n.text("退出群組"), systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(BombTheme.paper)
                                        .frame(width: (proxy.size.width - 32) * 0.6, height: 52)
                                        .background(BombTheme.red, in: Capsule())
                                        .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .disabled(isLeaving)
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
                            onPublish: { title, detail, subtaskTitles, assigneeID, deadline in
                                try await model.publishTask(
                                    title: title,
                                    detail: detail,
                                    subtaskTitles: subtaskTitles,
                                    groupID: group.id,
                                    assigneeMemberID: assigneeID,
                                    deadline: deadline
                                )
                            },
                            onCancel: closePublishTaskSheet
                        )
                        .frame(height: proxy.size.height * 0.82)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8 - safeAreaInsets.bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

#if DEBUG
                    if showsDebugPanel {
                        debugPanel
                            .zIndex(30)
                            .transition(.opacity)
                    }
#endif
                }
                .onChange(of: deadlineOutcome(now: context.date)) { oldValue, newValue in
                    if oldValue == .active, newValue != .active {
                        presentOutcomeMemeIfNeeded(outcome: newValue)
                    }
                }
            }
        }
        .bombDialog(L10n.format("確定退出「{0}」？", String(describing: currentGroup.name)), isPresented: $showsLeaveConfirmation, destructiveIsRed: true) {
            Button(L10n.text("取消"), role: .cancel) { }
            Button(L10n.text("退出群組"), role: .destructive) {
                isLeaving = true
                Task {
                    defer { isLeaving = false }
                    do {
                        try await model.leaveGroup(groupID: group.id)
                        dismiss()
                    } catch { leaveError = L10n.text("退出失敗，請確認網路後重試。") }
                }
            }
        } message: {
            Text(L10n.text("退出後將無法查看此群組。最後一位成員退出後，群組資料會永久刪除。"))
        }
        .bombDialog(L10n.text("無法退出群組"), isPresented: Binding(
            get: { leaveError != nil }, set: { if !$0 { leaveError = nil } }
        )) {
            Button(L10n.text("知道了")) { }
        } message: { Text(leaveError ?? "") }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showsPeerReviewPage) {
            peerReviewDestination
        }
        .navigationDestination(isPresented: $showsBattleReport) {
            PeerReviewReportView(model: model, group: currentGroup)
        }
        .bombTabBarHidden(
            showsPublishTaskSheet
                || shouldShowExplosionMeme(now: .now)
                || shouldShowSuccessMeme(now: .now)
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .overlayPreferenceValue(PokeButtonAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let pokeButtonEmoji,
                   let pokeButtonEmojiMemberID,
                   let anchor = anchors[pokeButtonEmojiMemberID] {
                    let buttonFrame = proxy[anchor]
                    Text(pokeButtonEmoji)
                        .font(.system(size: 48))
                        .position(x: buttonFrame.midX, y: buttonFrame.midY)
                        .offset(y: -46)
                        .rotationEffect(.degrees(isPokeButtonEmojiShaking ? 12 : -12))
                        .scaleEffect(isPokeButtonEmojiShaking ? 1.16 : 0.72)
                        .id(pokeButtonEmoji)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(100)
        }
        .animation(.bouncy, value: pokeButtonEmoji)
        .overlay {
            if shouldShowExplosionMeme(now: .now) {
                ExplosionMemeOverlay(
                    groupName: group.name,
                    progress: model.projectProgress(for: group.id),
                    incompleteTaskCount: model.projectTasks.filter {
                        $0.groupID == group.id && $0.progress < 100
                    }.count,
                    onDismiss: dismissOutcomeMeme
                )
                .transition(.opacity)
                .zIndex(200)
            } else if shouldShowSuccessMeme(now: .now) {
                SuccessMemeOverlay(
                    groupName: group.name,
                    onDismiss: dismissOutcomeMeme
                )
                .transition(.opacity)
                .zIndex(200)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shouldShowExplosionMeme(now: .now))
        .animation(.easeOut(duration: 0.2), value: shouldShowSuccessMeme(now: .now))
        .onAppear {
            deadlineDraft = currentGroup.deadline
            configureOutcomePresentation()
        }
        .sheet(isPresented: $showsLeaderPicker) {
            NavigationStack {
                ScrollView { leadershipSection.padding(16) }
                    .background(BombTheme.yellow)
                    .navigationTitle(L10n.text("更換組長"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("完成")) { showsLeaderPicker = false }
                                .disabled(isChoosingLeader)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled(isChoosingLeader)
        }
        .sheet(isPresented: $showsDeadlineSheet) {
            DeadlineEditorSheet(deadline: $deadlineDraft, onSave: saveDeadline)
        }
        .sheet(isPresented: $showsNameSheet) {
            GroupNameEditorSheet(name: $nameDraft, onSave: saveName)
        }
        .bombDialog(L10n.text("無法修改期限"), isPresented: Binding(
            get: { deadlineError != nil },
            set: { if !$0 { deadlineError = nil } }
        )) {
            Button(L10n.text("知道了")) { }
        } message: {
            Text(deadlineError ?? "")
        }
        .bombDialog(L10n.text("無法修改群組名稱"), isPresented: Binding(
            get: { nameError != nil },
            set: { if !$0 { nameError = nil } }
        )) {
            Button(L10n.text("知道了")) { }
        } message: {
            Text(nameError ?? "")
        }
    }

    private var topBar: some View {
        BombHeader(title: L10n.text("專案任務")) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(BombHeaderButtonStyle())
            .accessibilityLabel(L10n.text("返回群組"))
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
                .accessibilityLabel(L10n.text("聊天室"))
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
            Text(L10n.text("測試"))
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
                        Text(L10n.text("測試工具"))
                            .font(.title2.weight(.black))
                        Spacer()
                        Button(L10n.text("關閉")) { showsDebugPanel = false }
                            .font(.caption.weight(.black))
                            .foregroundStyle(BombTheme.ink)
                            .buttonStyle(.plain)
                    }

                    debugAction(L10n.text("測試被戳特效")) {
                        NotificationCenter.default.post(
                            name: .pokeReceived,
                            object: PokeReception(
                                groupName: currentGroup.name,
                                pokeCount: 1,
                                style: .alarm,
                                recipientUID: model.firebaseUID
                            )
                        )
                    }
                    debugAction(L10n.text("正常進行中")) {
                        debugDeadlineOutcome = .active
                        reviewDeferred = false
                        showsExplosionMeme = false
                        showsSuccessMeme = false
                        peerReviewStartsAtOutcomeSummary = true
                        peerReviewRevision += 1
                    }
                    debugAction(L10n.text("成功拆彈摘要")) {
                        presentDebugPeerReview(outcome: .completed, startsAtSummary: true)
                    }
                    debugAction(L10n.text("直接顯示成功梗圖")) {
                        presentDebugSuccessMeme()
                    }
                    debugAction(L10n.text("直接顯示爆炸梗圖")) {
                        presentDebugExplosionMeme()
                    }
                    debugAction(L10n.text("關閉爆炸梗圖")) {
                        debugDeadlineOutcome = .incomplete
                        showsExplosionMeme = false
                        reviewDeferred = true
                    }
                    debugAction(L10n.text("重新顯示爆炸梗圖")) {
                        presentDebugExplosionMeme()
                    }
                    debugAction(L10n.text("直接跳到戰損摘要")) {
                        presentDebugPeerReview(outcome: .incomplete, startsAtSummary: true)
                    }
                    debugAction(L10n.text("直接跳到雷包點點名")) {
                        let outcome = debugDeadlineOutcome == .completed ? GroupDeadlineOutcome.completed : .incomplete
                        presentDebugPeerReview(outcome: outcome, startsAtSummary: false, resetReviews: true)
                    }
                    debugAction(L10n.text("模擬部分成員已評分")) {
                        seedCurrentUserReviews(count: 1)
                        presentDebugPeerReview(outcome: .incomplete, startsAtSummary: false)
                    }
                    debugAction(L10n.text("模擬全部評分完成")) {
                        seedAllPeerReviews()
                        presentDebugPeerReview(outcome: .incomplete, startsAtSummary: false)
                    }
                    debugAction(L10n.text("重設互評進度")) {
                        let outcome = debugDeadlineOutcome == .completed ? GroupDeadlineOutcome.completed : .incomplete
                        presentDebugPeerReview(outcome: outcome, startsAtSummary: true, resetReviews: true)
                    }
                    debugAction(L10n.text("重新顯示結果摘要")) {
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
            .compositingGroup()
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
        showsPeerReviewPage = true
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

    private func shouldShowExplosionMeme(now: Date) -> Bool {
        deadlineOutcome(now: now) == .incomplete
            && showsExplosionMeme
    }

    private func shouldShowSuccessMeme(now: Date) -> Bool {
        deadlineOutcome(now: now) == .completed
            && showsSuccessMeme
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
                Text(L10n.text("尚有匿名互評未完成"))
                    .font(.headline.weight(.black))
            }

            HStack {
                Text(L10n.format("還剩 {0} 位隊員", String(describing: remainingReviewCount)))
                    .font(.subheadline.weight(.bold))

                Spacer()

                Button(L10n.text("繼續評分")) {
                    peerReviewStartsAtOutcomeSummary = false
                    peerReviewRevision += 1
                    reviewDeferred = false
                    showsPeerReviewPage = true
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

    private func configureOutcomePresentation() {
        guard !hasConfiguredOutcomePresentation else { return }
        hasConfiguredOutcomePresentation = true
        presentOutcomeMemeIfNeeded(outcome: deadlineOutcome(now: .now))
    }

    private func presentOutcomeMemeIfNeeded(outcome: GroupDeadlineOutcome) {
        guard outcome != .active,
              !UserDefaults.standard.bool(forKey: outcomeMemeSeenKey) else { return }

        reviewDeferred = true
        withAnimation(.easeOut(duration: 0.2)) {
            showsExplosionMeme = outcome == .incomplete
            showsSuccessMeme = outcome == .completed
        }
    }

    private func dismissOutcomeMeme() {
        UserDefaults.standard.set(true, forKey: outcomeMemeSeenKey)
        reviewDeferred = true
        withAnimation(.easeOut(duration: 0.2)) {
            showsExplosionMeme = false
            showsSuccessMeme = false
        }
    }

    private func showOutcomeMeme() {
        let outcome = deadlineOutcome(now: .now)
        guard outcome != .active else { return }

        reviewDeferred = true
        withAnimation(.easeOut(duration: 0.2)) {
            showsExplosionMeme = outcome == .incomplete
            showsSuccessMeme = outcome == .completed
        }
    }

    private func beginPeerReview() {
        peerReviewStartsAtOutcomeSummary = false
        peerReviewRevision += 1
        showsExplosionMeme = false
        showsSuccessMeme = false
        reviewDeferred = false
        showsPeerReviewPage = true
    }

    private var peerReviewDestination: some View {
        PeerReviewOverlay(
            group: currentGroup,
            outcome: deadlineOutcome(now: .now),
            projectProgress: model.projectProgress(for: group.id),
            startsAtOutcomeSummary: startsAtPeerReviewSummary,
            members: groupMembers,
            currentUserID: model.currentUserID,
            tasks: model.projectTasks.filter { $0.groupID == group.id },
            reviews: model.reviews(for: group.id),
            completedReviewerCount: model.completedPeerReviewerCount(in: group.id),
            peerReviewParticipantCount: model.peerReviewParticipantCount(in: group.id),
            syncError: model.peerReviewSyncError(for: group.id),
            onReturnToMeme: returnFromPeerReviewToMeme,
            onSubmit: { revieweeID, taskScore, discussionScore, collaborationScore, ideaScore, reliabilityScore, comment in
                _ = try await model.submitPeerReviewToCloud(
                    groupID: group.id,
                    reviewerID: model.currentUserID,
                    revieweeID: revieweeID,
                    taskCompletionScore: taskScore,
                    discussionScore: discussionScore,
                    collaborationScore: collaborationScore,
                    ideaScore: ideaScore,
                    reliabilityScore: reliabilityScore,
                    comment: comment,
                    now: reviewSubmissionDate(now: .now)
                )
            },
            onLater: closePeerReviewPage
        )
        .id(peerReviewOverlayIdentity)
    }

    private func closePeerReviewPage() {
        reviewDeferred = true
        showsPeerReviewPage = false
    }

    private func returnFromPeerReviewToMeme() {
        closePeerReviewPage()
        Task { @MainActor in
            await Task.yield()
            showOutcomeMeme()
        }
    }

    private var outcomeMemeSeenKey: String {
        "groupBomb.outcomeMemeSeen.\(model.currentUserID.uuidString).\(group.id.uuidString)"
    }

    private func settlementSection(outcome: GroupDeadlineOutcome) -> some View {
        ProjectSettlementSection(
            group: currentGroup,
            outcome: outcome,
            progress: model.projectProgress(for: group.id),
            tasks: model.projectTasks.filter { $0.groupID == group.id },
            members: groupMembers,
            currentUserID: model.currentUserID,
            reviews: model.reviews(for: group.id),
            reviewSummary: model.peerReviewSummary(for: group.id),
            personalReviewProject: model.personalPeerReviewProject(for: currentGroup),
            personalResultSyncError: model.personalPeerReviewSyncError,
            reviewComments: model.receivedPeerReviewComments(for: group.id),
            completedReviewerCount: model.completedPeerReviewerCount(in: group.id),
            syncError: model.peerReviewSyncError(for: group.id),
            onShowMeme: showOutcomeMeme,
            onShowBattleReport: { showsBattleReport = true },
            onBeginReview: beginPeerReview
        )
    }

    private var groupIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentGroup.name)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: copyInviteCode) {
                    HStack(spacing: 5) {
                        Text(showsCopiedFeedback
                            ? L10n.format("已複製：{0}", String(describing: currentGroup.inviteCode))
                            : L10n.format("群組代碼：{0}", String(describing: currentGroup.inviteCode)))
                        Image(systemName: showsCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.caption2.weight(.black))
                    }
                    .font(.caption.weight(.black))
                    .foregroundStyle(showsCopiedFeedback ? BombTheme.green : BombTheme.ink)
                    .lineLimit(1)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsCopiedFeedback
                    ? L10n.text("群組代碼已複製")
                    : L10n.format("複製群組代碼 {0}", String(describing: currentGroup.inviteCode)))

                Spacer(minLength: 0)

                ShareLink(
                    item: L10n.format(
                        "一起加入「{0}」！\n在 Group Bomb 輸入邀請碼：{1}",
                        String(describing: currentGroup.name),
                        String(describing: currentGroup.inviteCode)
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(BombTheme.ink)
                        .clipShape(.circle)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.text("分享群組邀請"))

                Menu {
                    Button(L10n.text("修改群組名稱"), systemImage: "pencil") {
                        nameDraft = currentGroup.name
                        showsNameSheet = true
                    }

                    Button(L10n.text("修改截止時間"), systemImage: "calendar.badge.clock") {
                        deadlineDraft = currentGroup.deadline
                        showsDeadlineSheet = true
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(BombTheme.ink)
                        .clipShape(.circle)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.text("修改群組"))
            }
            .tutorialTarget(
                .inviteCode,
                enabled: tutorialStep?.wrappedValue == .inviteCode
            )
        }
    }

    private func countdownCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(BombTheme.yellow)
                Text(L10n.text("專案倒數"))
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(L10n.text("LIVE"))
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
                Text(L10n.text("成員進度"))
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Button {
                    withAnimation(.snappy) { showsPublishTaskSheet = true }
                } label: {
                    Text(isGroupDeadlinePassed ? L10n.text("已截止") : L10n.text("＋ 發布任務"))
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
                    model: model,
                    firestoreGroupID: currentGroup.firestoreDocumentID,
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
                        Task { await model.toggleSubtask(taskID: taskID, subtaskID: subtaskID) }
                    },
                    onConfirmDeliverable: { taskID in
                        model.confirmDeliverable(taskID: taskID, memberID: model.currentUserID)
                    },
                    onPoke: { style in
                        model.poke(memberID: member.id, in: group.id, style: style)
                    },
                    onPokeEmoji: showPokeButtonEmoji,
                    onChangeLeader: member.id == model.currentUserID && member.role == .leader
                        ? { selectedLeader = nil; selectedElectionID = nil; leaderError = nil; showsLeaderPicker = true } : nil
                )
                .tutorialTarget(
                    .memberProgress,
                    enabled: tutorialStep?.wrappedValue == .memberProgress
                        && member.id == groupMembers.first?.id
                )
            }
        }
    }

    private var leadershipSection: some View {
        let leader = groupMembers.first { $0.role == .leader }
        let electionID = currentGroup.leaderElectionID
        let canChoose = leader?.id == model.currentUserID || electionID != nil
        let validSelection = selectedLeader.map { candidate in
            groupMembers.contains { $0.id == candidate.id } && candidate.id != leader?.id
                && selectedElectionID == electionID
        } ?? false
        return VStack(alignment: .leading, spacing: 20) {
            if showsLeaderPicker || electionID != nil {
                if electionID != nil {
                    Text(L10n.text("投票選組長")).font(.headline)
                    Text(L10n.format("需 {0} 票當選，可更改投票", String(groupMembers.count / 2 + 1)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top), count: 3), spacing: 20) {
                    ForEach(groupMembers) { member in
                        Button {
                            selectedElectionID = electionID
                            selectedLeader = member
                            leaderError = nil
                        } label: {
                            VStack(spacing: 10) {
                                MemberPhotoAvatar(groupID: currentGroup.firestoreDocumentID,
                                    uid: member.firebaseUID, name: member.name, size: 64)
                                    .overlay {
                                        Circle().strokeBorder(selectedLeader?.id == member.id ? BombTheme.yellow : .clear, lineWidth: 3)
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if member.role == .leader {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.black))
                                                .foregroundStyle(BombTheme.paper)
                                                .frame(width: 24, height: 24)
                                                .background(BombTheme.green, in: Circle())
                                                .overlay(Circle().stroke(BombTheme.paper, lineWidth: 2))
                                        }
                                    }
                                Text(member.name)
                                    .font(.subheadline.weight(.bold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3, reservesSpace: true)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel(member.name)
                                if electionID != nil {
                                    Text(L10n.format("{0} 票", String(currentGroup.leaderVotes.values.filter { $0 == member.id }.count)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(canChoose && !isChoosingLeader)
                        .accessibilityValue(member.role == .leader ? MemberRole.leader.title : member.role.title)
                        .accessibilityAddTraits(selectedLeader?.id == member.id ? .isSelected : [])
                    }
                }
                if groupMembers.count == 1 {
                    Text(L10n.text("其他成員加入後即可更換組長")).font(.caption)
                }
                if let leaderError { Text(leaderError).font(.caption).foregroundStyle(BombTheme.red) }
                Button {
                    if let selectedLeader { chooseLeader(selectedLeader, electionID: selectedElectionID) }
                } label: {
                    HStack {
                        if isChoosingLeader { ProgressView().tint(BombTheme.paper) }
                        Text(L10n.text("確認")).font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(BombTheme.paper)
                    .background(BombTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canChoose || !validSelection || isChoosingLeader)
                .opacity(canChoose && validSelection && !isChoosingLeader ? 1 : 0.45)
            }
        }
        .foregroundStyle(BombTheme.ink)
        .padding(.vertical, 12)
    }

    private func chooseLeader(_ member: Member, electionID: String?) {
        isChoosingLeader = true
        leaderError = nil
        Task {
            defer { isChoosingLeader = false }
            do {
                try await model.chooseGroupLeader(groupID: group.id, candidateID: member.id, electionID: electionID)
                selectedLeader = nil
                showsLeaderPicker = false
            } catch {
                leaderError = L10n.text("無法儲存，請稍後再試。")
            }
        }
    }

    private var departedTasksSection: some View {
        let tasks = model.projectTasks.filter { $0.groupID == group.id && $0.departureID != nil }
        let departures = Dictionary(grouping: tasks, by: { $0.departureID! })
        let isLeader = groupMembers.contains { $0.id == model.currentUserID && $0.role == .leader }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(departures.keys.sorted(), id: \.self) { departureID in
                if let items = departures[departureID], let first = items.first {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.format("{0} 的離開前任務", first.departedMemberName ?? ""))
                            .font(.headline)
                        ForEach(items) { task in
                            HStack {
                                Text(task.title)
                                Spacer()
                                Text("\(task.progress)%").monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                        Text(L10n.text(first.departureReviewed
                            ? (first.includedInProgress ? "已計入專案進度" : "已排除專案進度")
                            : "目前計入專案進度，等待組長決定"))
                            .font(.caption).foregroundStyle(.secondary)
                        if isLeader {
                            HStack {
                                Button(L10n.text("保留計入")) { decideDeparture(departureID, included: true) }
                                Button(L10n.text("排除計算")) { decideDeparture(departureID, included: false) }
                                if pendingDepartureID == departureID { ProgressView() }
                            }
                            .buttonStyle(.bordered)
                            .tint(BombTheme.ink)
                            .disabled(pendingDepartureID != nil)
                        }
                    }
                    .comicCard()
                }
            }
            if let departureError {
                Text(departureError).font(.caption).foregroundStyle(BombTheme.red)
            }
        }
    }

    private func decideDeparture(_ departureID: String, included: Bool) {
        pendingDepartureID = departureID
        departureError = nil
        Task {
            defer { pendingDepartureID = nil }
            do {
                try await model.setDepartedTasksInclusion(groupID: group.id, departureID: departureID, included: included)
            } catch {
                departureError = L10n.text("無法儲存，請稍後再試。")
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

    private func showPokeButtonEmoji(for memberID: String, emoji: String?) {
        pokeButtonEmoji = emoji
        pokeButtonEmojiMemberID = emoji == nil ? nil : memberID

        guard emoji != nil else {
            isPokeButtonEmojiShaking = false
            return
        }

        isPokeButtonEmojiShaking = false
        Task {
            await Task.yield()
            withAnimation(.bouncy(duration: 0.14).repeatCount(7, autoreverses: true)) {
                isPokeButtonEmojiShaking = true
            }
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

    private func remainingTime(now: Date) -> String {
        let remaining = max(0, Int(currentGroup.deadline.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = remaining % 86_400 / 3_600
        let minutes = remaining % 3_600 / 60

        if remaining == 0 {
            return L10n.text("已截止")
        }

        return L10n.format("{0} 天 {1} 小時 {2} 分鐘", String(describing: days), String(describing: hours), String(describing: minutes))
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
            currentTask: currentTask?.title ?? L10n.text("尚未指派任務"),
            status: currentTask?.status.title ?? L10n.text("待命"),
            showsNudge: member.id != model.currentUserID && progress <= 90
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
                    L10n.text("截止時間"),
                    selection: $deadline,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .navigationTitle(L10n.text("修改截止時間"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("儲存")) { onSave() }
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
                TextField(L10n.text("群組名稱"), text: $name)
            }
            .navigationTitle(L10n.text("修改群組名稱"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("儲存")) { onSave() }
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
    let onDismiss: () -> Void
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
                                Text(L10n.text("任務爆炸"))
                                    .font(.system(.title, design: .rounded, weight: .black))
                                Text(L10n.text("截止時間已到"))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(BombTheme.paper)
                                    .frame(width: 40, height: 40)
                                    .background(BombTheme.ink)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("關閉梗圖"))
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
                            .accessibilityLabel(L10n.text("爆炸專案梗圖"))

                        VStack(spacing: 9) {
                            Text(groupName)
                                .font(.title3.weight(.black))
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                Text(L10n.format("完成率 {0}%", String(describing: progress)))
                                Text("｜")
                                    .foregroundStyle(.secondary)
                                Text(L10n.format("未完成任務 {0} 項", String(describing: incompleteTaskCount)))
                            }
                            .font(.subheadline.weight(.black))
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(BombTheme.yellow.opacity(0.32))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))

                        Text(L10n.text("本次任務未能如期完成，\n請查看團隊戰報並完成匿名隊員互評。"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.76))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if let shareImage {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview(L10n.format("{0} 任務結算", String(describing: groupName)), image: shareImage)
                            ) {
                                Label(L10n.text("分享梗圖"), systemImage: "square.and.arrow.up")
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

                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .background(BombTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 3))
                .frame(maxWidth: 560)
                .frame(maxHeight: max(320, proxy.size.height - 64))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
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
                        .frame(width: proxy.size.width * 0.70)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: 30)
                    Spacer()
                    MemeCaption(
                        text: L10n.text("已讀不回的組員"),
                        fontSize: proxy.size.width * 0.05
                    )
                    // Keep this caption to the right of the person's face.
                    .frame(width: proxy.size.width * 0.50)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: 15)
                    Spacer()
                    MemeCaption(text: L10n.text("我要放暑假了！"), fontSize: proxy.size.width * 0.07)
                        .frame(width: proxy.size.width * 0.64)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: -20)
                }
                .padding(.vertical, proxy.size.height * 0.08)
                .padding(.horizontal, proxy.size.width * 0.06)
            }
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(L10n.format("{0} 的任務爆炸梗圖，完成率 {1}%，尚有 {2} 項任務未完成", String(describing: groupName), String(describing: progress), String(describing: incompleteTaskCount)))
    }
}

private struct SuccessMemeOverlay: View {
    let groupName: String
    let onDismiss: () -> Void
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
                                Text(L10n.text("成功拆彈"))
                                    .font(.system(.title, design: .rounded, weight: .black))
                                Text(L10n.text("任務已全數完成"))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(BombTheme.paper)
                                    .frame(width: 40, height: 40)
                                    .background(BombTheme.ink)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("關閉梗圖"))
                        }

                        SuccessMemeImage(groupName: groupName)
                            .frame(maxWidth: min(260, proxy.size.width - 64))
                            .accessibilityLabel(L10n.text("成功拆彈梗圖"))

                        Text(L10n.text("這次任務如期完成，\n請完成匿名隊員互評。"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.76))
                            .multilineTextAlignment(.center)

                        if let shareImage {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview(L10n.format("{0} 成功拆彈", String(describing: groupName)), image: shareImage)
                            ) {
                                Label(L10n.text("分享梗圖"), systemImage: "square.and.arrow.up")
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

                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .background(BombTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 3))
                .frame(maxWidth: 560)
                .frame(maxHeight: max(320, proxy.size.height - 64))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
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
                    MemeCaption(text: L10n.text("你有多猛"), fontSize: proxy.size.width * 0.09)
                        .offset(y: 140)
                    Spacer()
                    MemeCaption(
                        text: L10n.format("我完成了{0}", String(describing: groupName)),
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
        .accessibilityLabel(L10n.format("{0} 的成功拆彈梗圖", String(describing: groupName)))
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
