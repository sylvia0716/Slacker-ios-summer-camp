import SwiftUI

/// 截止後的單一互評視窗，集中處理隊員列表、評分、確認與完成狀態。
struct PeerReviewOverlay: View {
    let group: Group
    let members: [Member]
    let currentUserID: UUID
    let tasks: [ProjectTask]
    let reviews: [PeerReview]
    let completedReviewerCount: Int
    let onSubmit: (UUID, Int, Int, Int, Int, Int, String) throws -> Void
    let onLater: () -> Void

    @State private var selectedMemberID: UUID?
    @State private var submittedMemberID: UUID?
    @State private var scores: [ReviewCriterion: Int] = [:]
    @State private var comment = ""
    @State private var showsConfirmation = false
    @State private var errorMessage: String?
    @State private var showsResultsPlaceholder = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BombTheme.ink.opacity(0.6)
                    .ignoresSafeArea()

                ScrollView {
                    SwiftUI.Group {
                        if let submittedMember {
                            submissionSuccess(for: submittedMember)
                        } else if let selectedMember {
                            reviewForm(for: selectedMember)
                        } else if hasCompletedAllReviews {
                            completionContent
                        } else {
                            memberList
                        }
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

                if showsConfirmation, let selectedMember {
                    confirmationOverlay(for: selectedMember)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .accessibilityElement(children: .contain)
    }

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock

            Text("已完成 \(completedReviewCount) / \(otherMembers.count)")
                .font(.subheadline.weight(.black))

            ForEach(otherMembers) { member in
                memberRow(member)
            }

            anonymityNotice

            Button("稍後再評", action: onLater)
                .font(.subheadline.weight(.black))
                .foregroundStyle(BombTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                .buttonStyle(.plain)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("雷包點點名")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            Text("匿名隊員互評")
                .font(.headline.weight(.black))
            Text("請根據隊友在本次任務中的實際表現完成匿名互評。")
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
                Text(isSubmitted ? "已完成" : "尚未評分")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(isSubmitted ? BombTheme.green : BombTheme.red)
            }

            Spacer(minLength: 8)

            Button(isSubmitted ? "已送出" : "開始評分") {
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
        .background(Color.white.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 2))
    }

    private func reviewForm(for member: Member) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                returnToList()
            } label: {
                Label("返回隊員列表", systemImage: "chevron.left")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BombTheme.ink)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                avatar(for: member, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name).font(.title2.weight(.black))
                    Text(member.role.title).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                }
            }

            objectiveSummary(for: member)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(ReviewCriterion.allCases) { criterion in
                    ratingRow(criterion)
                }
            }

            commentEditor
            anonymityNotice

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }

            Button {
                showsConfirmation = true
            } label: {
                Text("送出匿名評價")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(allScoresComplete ? BombTheme.ink : BombTheme.ink.opacity(0.35))
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!allScoresComplete)
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
        .background(BombTheme.yellow.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption.weight(.bold))
            Spacer()
            Text(value).font(.caption.weight(.black))
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
                    .foregroundStyle(score == 0 ? Color.secondary : BombTheme.green)
            }

            Text(criterion.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        scores[criterion] = value
                    } label: {
                        Circle()
                            .fill(value <= score ? BombTheme.ink : Color.clear)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(BombTheme.ink, lineWidth: 2))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(criterion.title) \(value) 分")
                }
            }
        }
    }

    private var commentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("匿名評語").font(.subheadline.weight(.black))

            ZStack(alignment: .topLeading) {
                if comment.isEmpty {
                    Text("寫下這位組員做得好的地方，或可以改進的地方")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $comment)
                    .font(.subheadline)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 112)
                    .onChange(of: comment) { _, newValue in
                        if newValue.count > 200 {
                            comment = String(newValue.prefix(200))
                        }
                    }
            }
            .padding(8)
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
                Text("確認送出？").font(.title2.weight(.black))
                Text("送出後本次匿名評價將無法修改。")
                    .font(.subheadline.weight(.bold))

                HStack(spacing: 10) {
                    Button("返回修改") { showsConfirmation = false }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                        .buttonStyle(.plain)

                    Button("確認送出") { submitReview(for: member) }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                        .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
            .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)
        }
    }

    private func submissionSuccess(for member: Member) -> some View {
        let remainingCount = pendingMembers.count

        return VStack(alignment: .leading, spacing: 18) {
            titleBlock
            Label("已完成對\(member.name)的匿名評價", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.black))
                .foregroundStyle(BombTheme.green)

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
            titleBlock
            Text("互評完成").font(.title2.weight(.black))
            Text("你已完成所有隊員的匿名互評。")
                .font(.subheadline.weight(.bold))

            VStack(alignment: .leading, spacing: 8) {
                summaryRow(label: "已評價人數", value: "\(completedReviewCount) / \(otherMembers.count)")
                summaryRow(label: "整體互評完成進度", value: "\(completedReviewerCount) / \(members.count) 位")
            }

            Text(completedReviewerCount == members.count ? "所有匿名互評已完成" : "等待其他隊員完成互評")
                .font(.subheadline.weight(.black))
                .foregroundStyle(completedReviewerCount == members.count ? BombTheme.green : BombTheme.red)

            anonymityNotice

            if showsResultsPlaceholder {
                Text("互評結果將於下一階段開放")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }

            Button("返回群組", action: onLater)
                .primaryReviewButton()

            Button("查看互評結果") {
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
    }

    private func returnToList() {
        selectedMemberID = nil
        scores = [:]
        comment = ""
        errorMessage = nil
    }

    private func submitReview(for member: Member) {
        do {
            try onSubmit(
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
            submittedMemberID = member.id
            errorMessage = nil
        } catch {
            showsConfirmation = false
            errorMessage = error.localizedDescription
        }
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
