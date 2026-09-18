import SwiftUI

/// 截止後的互評頁面，集中處理隊員列表、評分、確認與完成狀態。
struct PeerReviewOverlay: View {
    let group: Group
    let outcome: GroupDeadlineOutcome
    let projectProgress: Int
    let startsAtOutcomeSummary: Bool
    let members: [Member]
    let currentUserID: UUID
    let tasks: [ProjectTask]
    let reviews: [PeerReview]
    let completedReviewerCount: Int
    let peerReviewParticipantCount: Int
    let syncError: String?
    let onReturnToMeme: () -> Void
    let onSubmit: (UUID, Int, Int, Int, Int, Int, String) async throws -> Void
    let onLater: () -> Void

    @State private var selectedMemberID: UUID?
    @State private var submittedMemberID: UUID?
    @State private var scores: [ReviewCriterion: Int] = [:]
    @State private var comment = ""
    @State private var showsConfirmation = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showsResultsPlaceholder = false
    @State private var hasEnteredReview = false
    @State private var showsExitReviewConfirmation = false
    @FocusState private var isCommentFocused: Bool

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    SwiftUI.Group {
                        if startsAtOutcomeSummary && !hasEnteredReview {
                            outcomeSummary
                        } else if let submittedMember {
                            submissionSuccess(for: submittedMember)
                        } else if let selectedMember {
                            reviewForm(for: selectedMember)
                        } else if hasCompletedAllReviews {
                            completionContent
                        } else {
                            memberList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isCommentFocused = false
                        }
                }
                .onChange(of: isCommentFocused) { _, isFocused in
                    guard isFocused else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.snappy) {
                            proxy.scrollTo("peer-review-comment", anchor: .center)
                        }
                    }
                }
                .onChange(of: comment) { _, _ in
                    guard isCommentFocused else { return }
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo("peer-review-comment", anchor: .bottom)
                    }
                }
            }

            if showsConfirmation, let selectedMember {
                confirmationOverlay(for: selectedMember)
            }

        }
        .accessibilityElement(children: .contain)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .bombTabBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: "匿名互評", subtitle: group.name) {
                Button(action: handleHeaderBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel(selectedMember == nil ? "返回群組" : "返回隊員列表")
            } trailing: {
                EmptyView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedMember != nil,
               submittedMember == nil,
               !showsConfirmation,
               !isCommentFocused {
                reviewSubmitBar
            }
        }
        .overlay {
            if showsExitReviewConfirmation {
                exitReviewConfirmationOverlay
            }
        }
    }

    private var outcomeSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: onReturnToMeme) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回梗圖")

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: theme.iconName)
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 58, height: 58)
                    .background(theme.iconBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(BombTheme.ink, lineWidth: 3))

                VStack(alignment: .leading, spacing: 5) {
                    Text(theme.outcomeTitle)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text(theme.outcomeSubtitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(label: "群組名稱", value: group.name, font: .subheadline)
                summaryRow(label: theme.progressLabel, value: "\(clampedProjectProgress)%", font: .subheadline)
                summaryRow(
                    label: theme.completedTaskLabel,
                    value: "\(completedTaskCount) / \(tasks.count)",
                    font: .subheadline
                )

                if theme.isIncident {
                    summaryRow(label: "未完成任務數", value: "\(incompleteTaskCount)", font: .subheadline)
                }

                summaryRow(label: "截止時間", value: formattedDeadline, font: .subheadline)
            }
            .padding(14)
            .background(theme.summaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 2))

            if theme.isIncident && !unfinishedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未完成工作")
                        .font(.headline.weight(.black))

                    ForEach(unfinishedTasks) { task in
                        Label(task.title, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BombTheme.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.red, lineWidth: 2))
            }

            Button(theme.startButtonTitle) {
                withAnimation(.snappy) { hasEnteredReview = true }
            }
            .primaryReviewButton()
        }
    }

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if startsAtOutcomeSummary {
                returnToOutcomeSummaryButton
            }

            titleBlock

            if let syncError {
                Label(syncError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BombTheme.red)
            }

            Text("已完成 \(completedReviewCount) / \(otherMembers.count)")
                .font(.subheadline.weight(.black))

            ForEach(otherMembers) { member in
                memberRow(member)
            }

            anonymityNotice

            Button(action: onLater) {
                Text("稍後再評")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("雷包點點名")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            Text("匿名隊員互評")
                .font(.headline.weight(.black))
            Text(theme.instruction)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func memberRow(_ member: Member) -> some View {
        let isSubmitted = hasReviewed(member.id)

        return HStack(spacing: 12) {
            avatar(for: member, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name).font(.headline.weight(.black))
                Text(member.role.title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(isSubmitted ? "已評分" : "尚未評分")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(isSubmitted ? BombTheme.green : BombTheme.red)
            }

            Spacer(minLength: 8)

            Button(isSubmitted ? "已評分" : "開始評分") {
                beginReview(member)
            }
            .font(.caption.weight(.black))
            .foregroundStyle(isSubmitted ? Color.secondary : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSubmitted ? Color.white.opacity(0.5) : BombTheme.ink)
            .clipShape(.capsule)
            .overlay(Capsule().stroke(BombTheme.ink, lineWidth: isSubmitted ? 1.5 : 0))
            .buttonStyle(.plain)
            .disabled(isSubmitted)
        }
        .padding(12)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 2))
    }

    private func reviewForm(for member: Member) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                avatar(for: member, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name).font(.title2.weight(.black))
                    Text(member.role.title).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isCommentFocused = false
            }

            objectiveSummary(for: member)
                .contentShape(Rectangle())
                .onTapGesture {
                    isCommentFocused = false
                }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ReviewCriterion.allCases.enumerated()), id: \.offset) { index, criterion in
                    ratingRow(criterion)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                isCommentFocused = false
                            }
                        )

                    if index < ReviewCriterion.allCases.count - 1 {
                        Divider()
                            .overlay(BombTheme.ink.opacity(0.18))
                    }
                }

                Divider()
                    .overlay(BombTheme.ink.opacity(0.18))

                commentEditor
                    .padding(.vertical, 14)
            }
            .padding(.horizontal, 14)
            .background {
                BombTheme.paper
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isCommentFocused = false
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 2))

            anonymityNotice
                .contentShape(Rectangle())
                .onTapGesture {
                    isCommentFocused = false
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }
        }
    }

    private func objectiveSummary(for member: Member) -> some View {
        let memberTasks = tasks.filter { $0.ownerMemberID == member.id }
        let subtasks = memberTasks.flatMap(\.subtasks)
        let completedSubtasks = subtasks.filter(\.isComplete).count
        let hasDeliverable = memberTasks.contains { $0.deliverable != nil }

        return VStack(alignment: .leading, spacing: 8) {
            Text("客觀紀錄摘要").font(.subheadline.weight(.black))

            if memberTasks.isEmpty {
                Text("尚無指派任務")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                summaryRow(label: "完成子任務", value: "\(completedSubtasks) / \(subtasks.count)")
                summaryRow(label: "成果證明", value: hasDeliverable ? "已上傳" : "尚未上傳")
            }
        }
        .padding(12)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))
    }

    private func summaryRow(label: String, value: String, font: Font = .caption) -> some View {
        HStack {
            Text(label).font(font.weight(.bold))
            Spacer()
            Text(value).font(font.weight(.black))
        }
    }

    private func ratingRow(_ criterion: ReviewCriterion) -> some View {
        let score = scores[criterion] ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(criterion.title).font(.subheadline.weight(.black))
                Spacer()
                Text(score == 0 ? "尚未評分" : "\(score) / 5")
                    .font(.caption.weight(.black))
                    .foregroundStyle(score == 0 ? Color.secondary : theme.accentColor)
            }

            Text(criterion.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        isCommentFocused = false
                        withAnimation(.snappy) {
                            scores[criterion] = value
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(value <= score ? theme.ratingFill : Color.clear)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(BombTheme.ink, lineWidth: 2))

                            Text(value == 1 || value == 5 ? "\(value)" : " ")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(BombTheme.ink.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(criterion.title) \(value) 分")
                    .accessibilityAddTraits(value == score ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var reviewSubmitBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(BombTheme.ink.opacity(0.2))

            Button {
                isCommentFocused = false
                showsConfirmation = true
            } label: {
                Text(allScoresComplete ? "送出匿名評價" : "尚有 \(ReviewCriterion.allCases.count - completedScoreCount) 項未評分")
                    .font(.headline.weight(.black))
                    .foregroundStyle(allScoresComplete ? Color.white : BombTheme.ink.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(allScoresComplete ? BombTheme.ink : BombTheme.paper)
                    .clipShape(.capsule)
                    .overlay(
                        Capsule()
                            .stroke(BombTheme.ink, lineWidth: allScoresComplete ? 0 : 2)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!allScoresComplete)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(BombTheme.yellow)
    }

    private var commentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.commentSectionTitle).font(.subheadline.weight(.black))

            if let commentGuidance = theme.commentGuidance {
                Label(commentGuidance, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BombTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .topLeading) {
                if comment.isEmpty {
                    Text(theme.commentPlaceholder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $comment)
                    .font(.subheadline)
                    .focused($isCommentFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 112)
                    .onChange(of: comment) { _, newValue in
                        if newValue.count > 200 {
                            comment = String(newValue.prefix(200))
                        }
                    }
            }
            .padding(8)
            .id("peer-review-comment")
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))

            Text("\(comment.count) / 200")
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func confirmationOverlay(for member: Member) -> some View {
        ZStack {
            BombTheme.ink.opacity(0.48).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(theme.confirmationTitle).font(.title2.weight(.black))
                Text(theme.confirmationMessage)
                    .font(.subheadline.weight(.bold))

                HStack(spacing: 10) {
                    Button("返回修改") { showsConfirmation = false }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)

                    Button {
                        Task { await submitReview(for: member) }
                    } label: {
                        SwiftUI.Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("確認送出")
                            }
                        }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
            }
            .padding(20)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
        }
    }

    private var exitReviewConfirmationOverlay: some View {
        ZStack {
            BombTheme.ink.opacity(0.48)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Label("尚未送出評價", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.black))
                    .foregroundStyle(BombTheme.red)

                Text("目前填寫的評分與評語尚未送出，確定要離開嗎？")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BombTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("繼續填寫") {
                        withAnimation(.snappy) {
                            showsExitReviewConfirmation = false
                        }
                    }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
                    .buttonStyle(.plain)

                    Button("確定離開") {
                        withAnimation(.snappy) {
                            showsExitReviewConfirmation = false
                        }
                        returnToList()
                    }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(BombTheme.red)
                    .clipShape(.capsule)
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
        }
        .transition(.opacity)
        .zIndex(2)
    }

    private func submissionSuccess(for member: Member) -> some View {
        let remainingCount = pendingMembers.count

        return VStack(alignment: .leading, spacing: 18) {
            titleBlock
            Label(theme.submissionSuccessMessage(for: member.name), systemImage: theme.successIconName)
                .font(.title3.weight(.black))
                .foregroundStyle(theme.accentColor)

            Text("剩餘 \(remainingCount) 位隊員尚未評價")
                .font(.subheadline.weight(.bold))

            if let nextMember = pendingMembers.first {
                Button("評下一位") { beginReview(nextMember) }
                    .primaryReviewButton()
            }

            Button(remainingCount == 0 ? "查看完成狀態" : "返回隊員列表") {
                submittedMemberID = nil
            }
            .secondaryReviewButton()
        }
    }

    private var completionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if startsAtOutcomeSummary {
                returnToOutcomeSummaryButton
            }

            titleBlock
            Text(theme.completionTitle).font(.title2.weight(.black))
            Text(theme.completionMessage)
                .font(.subheadline.weight(.bold))

            VStack(alignment: .leading, spacing: 8) {
                summaryRow(label: "你已評完的隊友", value: "\(completedReviewCount) / \(otherMembers.count) 位")
                summaryRow(label: "完成全部互評的成員", value: "\(completedReviewerCount) / \(peerReviewParticipantCount) 位")
            }

            Text(completedReviewerCount >= peerReviewParticipantCount ? theme.everyoneCompletedMessage : theme.waitingMessage)
                .font(.subheadline.weight(.black))
                .foregroundStyle(completedReviewerCount >= peerReviewParticipantCount ? theme.accentColor : BombTheme.red)

            anonymityNotice

            if showsResultsPlaceholder {
                Text(theme.resultsPlaceholder)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }

            Button("返回群組", action: onLater)
                .primaryReviewButton()

            Button(theme.resultsButtonTitle) {
                showsResultsPlaceholder = true
            }
            .secondaryReviewButton()
        }
    }

    private var anonymityNotice: some View {
        Label("所有評價皆為匿名，請依實際合作表現客觀填寫。", systemImage: "lock.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func avatar(for member: Member, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(BombTheme.ink)
            Image(systemName: member.avatarSymbol)
                .font(.system(size: size * 0.4, weight: .black))
                .foregroundStyle(BombTheme.yellow)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var otherMembers: [Member] {
        members.filter { $0.id != currentUserID }
    }

    private var theme: PeerReviewTheme {
        PeerReviewTheme(outcome: outcome)
    }

    private var clampedProjectProgress: Int {
        if outcome == .completed { return 100 }
        return min(max(projectProgress, 0), 100)
    }

    private var completedTaskCount: Int {
        if outcome == .completed { return tasks.count }
        return tasks.filter { $0.progress >= 100 }.count
    }

    private var incompleteTaskCount: Int {
        unfinishedTasks.count
    }

    private var unfinishedTasks: [ProjectTask] {
        tasks.filter { $0.progress < 100 }
    }

    private var formattedDeadline: String {
        group.deadline.formatted(date: .abbreviated, time: .shortened)
    }

    private var selectedMember: Member? {
        members.first { $0.id == selectedMemberID }
    }

    private var submittedMember: Member? {
        members.first { $0.id == submittedMemberID }
    }

    private var completedReviewCount: Int {
        otherMembers.filter { hasReviewed($0.id) }.count
    }

    private var pendingMembers: [Member] {
        otherMembers.filter { !hasReviewed($0.id) }
    }

    private var hasCompletedAllReviews: Bool {
        !otherMembers.isEmpty && pendingMembers.isEmpty
    }

    private var completedScoreCount: Int {
        ReviewCriterion.allCases.filter { (1...5).contains(scores[$0] ?? 0) }.count
    }

    private var allScoresComplete: Bool {
        ReviewCriterion.allCases.allSatisfy { (1...5).contains(scores[$0] ?? 0) }
    }

    private func hasReviewed(_ memberID: UUID) -> Bool {
        reviews.contains {
            $0.reviewerMemberID == currentUserID && $0.revieweeMemberID == memberID
        }
    }

    private func beginReview(_ member: Member) {
        guard !hasReviewed(member.id) else { return }
        selectedMemberID = member.id
        submittedMemberID = nil
        scores = [:]
        comment = ""
        errorMessage = nil
        isCommentFocused = false
    }

    private func returnToList() {
        selectedMemberID = nil
        scores = [:]
        comment = ""
        errorMessage = nil
        isCommentFocused = false
    }

    private func handleHeaderBack() {
        isCommentFocused = false
        if selectedMemberID != nil {
            withAnimation(.snappy) {
                showsExitReviewConfirmation = true
            }
        } else {
            onLater()
        }
    }

    private var returnToOutcomeSummaryButton: some View {
        Button(action: returnToOutcomeSummary) {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.black))
                .foregroundStyle(BombTheme.ink)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.isIncident ? "返回戰損摘要" : "返回結算摘要")
    }

    private func returnToOutcomeSummary() {
        selectedMemberID = nil
        submittedMemberID = nil
        scores = [:]
        comment = ""
        showsConfirmation = false
        errorMessage = nil
        showsResultsPlaceholder = false
        isCommentFocused = false
        withAnimation(.snappy) { hasEnteredReview = false }
    }

    private func submitReview(for member: Member) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onSubmit(
                member.id,
                scores[.taskCompletion] ?? 0,
                scores[.discussion] ?? 0,
                scores[.collaboration] ?? 0,
                scores[.idea] ?? 0,
                scores[.reliability] ?? 0,
                comment
            )
            showsConfirmation = false
            selectedMemberID = nil
            submittedMemberID = nil
            errorMessage = nil
        } catch {
            showsConfirmation = false
            errorMessage = error.localizedDescription
        }
    }
}

/// 單一互評流程的輕量視覺設定；只依截止結果切換文案與局部樣式。
private struct PeerReviewTheme {
    let outcome: GroupDeadlineOutcome

    var isIncident: Bool { outcome == .incomplete }

    var outcomeTitle: String {
        isIncident ? "任務爆炸" : "成功拆彈！"
    }

    var outcomeSubtitle: String {
        isIncident
            ? "截止時間已到，先查看戰損，再完成匿名隊員互評。"
            : "任務已完成，請進行匿名隊員互評。"
    }

    var instruction: String {
        isIncident
            ? "請根據本次任務中的實際合作表現完成匿名互評，找出這次任務卡住的原因。"
            : "請根據隊友在本次任務中的實際表現完成匿名互評。"
    }

    var iconName: String {
        isIncident ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    var successIconName: String {
        isIncident ? "doc.text.fill" : "checkmark.circle.fill"
    }

    var startButtonTitle: String {
        isIncident ? "開始戰損復盤" : "開始雷包點點名"
    }

    var progressLabel: String {
        isIncident ? "截止時完成率" : "最終進度"
    }

    var completedTaskLabel: String {
        isIncident ? "已完成任務數" : "完成任務數"
    }

    var commentSectionTitle: String {
        isIncident ? "事故報告" : "匿名評語"
    }

    var commentPlaceholder: String {
        isIncident
            ? "請寫下這次合作中做得好的地方，或造成任務卡住、延誤的原因。"
            : "寫下這位隊員做得好的地方，或可以改進的地方。"
    }

    var commentGuidance: String? {
        isIncident ? "請針對行為與合作狀況，不要進行人身攻擊。" : nil
    }

    var confirmationTitle: String {
        isIncident ? "確認提交事故報告？" : "確認送出？"
    }

    var confirmationMessage: String {
        isIncident ? "送出後，本次匿名評價將無法修改。" : "送出後本次匿名評價將無法修改。"
    }

    func submissionSuccessMessage(for memberName: String) -> String {
        isIncident
            ? "已完成對「\(memberName)」的匿名復盤"
            : "已完成對「\(memberName)」的匿名評價"
    }

    var completionTitle: String {
        isIncident ? "戰損分析完成" : "互評完成"
    }

    var completionMessage: String {
        "你已完成所有隊員的匿名互評。"
    }

    var everyoneCompletedMessage: String {
        isIncident ? "所有隊員皆已完成復盤" : "所有匿名互評已完成"
    }

    var waitingMessage: String {
        isIncident ? "等待其他隊員完成復盤" : "等待其他隊員完成互評"
    }

    var resultsButtonTitle: String {
        isIncident ? "查看戰損報告" : "查看互評結果"
    }

    var resultsPlaceholder: String {
        isIncident ? "戰損報告將於下一階段開放" : "互評結果將於下一階段開放"
    }

    var accentColor: Color {
        isIncident ? BombTheme.red : BombTheme.green
    }

    var ratingFill: Color {
        isIncident ? BombTheme.red : BombTheme.ink
    }

    var iconBackground: Color {
        isIncident ? BombTheme.red.opacity(0.14) : BombTheme.yellow
    }

    var summaryBackground: Color {
        isIncident ? Color.black.opacity(0.06) : BombTheme.yellow.opacity(0.34)
    }
}

private enum ReviewCriterion: String, CaseIterable, Identifiable {
    case taskCompletion
    case discussion
    case collaboration
    case idea
    case reliability

    var id: Self { self }

    var title: String {
        switch self {
        case .taskCompletion: "任務完成度"
        case .discussion: "討論參與度"
        case .collaboration: "主動協助程度"
        case .idea: "點子與問題解決"
        case .reliability: "準時與可靠度"
        }
    }

    var detail: String {
        switch self {
        case .taskCompletion: "是否完成被分配的工作與子任務。"
        case .discussion: "是否有參與團隊討論並提供回應。"
        case .collaboration: "是否主動協助其他組員完成工作。"
        case .idea: "是否提出有用的想法，或協助解決問題。"
        case .reliability: "是否準時完成、交付並更新進度。"
        }
    }
}

private extension View {
    func primaryReviewButton() -> some View {
        font(.subheadline.weight(.black))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(BombTheme.ink)
            .clipShape(.capsule)
            .buttonStyle(.plain)
    }

    func secondaryReviewButton() -> some View {
        font(.subheadline.weight(.black))
            .foregroundStyle(BombTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
            .buttonStyle(.plain)
    }
}
