import SwiftUI

/// 專案結束後取代成員進度的結算內容。
struct ProjectSettlementSection: View {
    let group: Group
    let outcome: GroupDeadlineOutcome
    let progress: Int
    let tasks: [ProjectTask]
    let members: [Member]
    let currentUserID: UUID
    let reviews: [PeerReview]
    let reviewSummary: PeerReviewSummary?
    let personalReviewProject: PersonalPeerReviewProject?
    let personalResultSyncError: String?
    let reviewComments: [String]
    let completedReviewerCount: Int
    let syncError: String?
    let onShowMeme: () -> Void
    let onShowBattleReport: () -> Void
    let onBeginReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("專案結算")
                        .font(.system(.title2, design: .rounded, weight: .black))
                    Text(outcome == .completed ? "成功拆彈" : "任務爆炸")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(outcomeColor)
                }

                Spacer()

                Button(action: onShowMeme) {
                    Label("重看梗圖", systemImage: outcome == .completed ? "trophy.fill" : "burst.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(BombTheme.paper)
                        .clipShape(.capsule)
                        .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }

            damageSummary
            battleReportButton
            peerReviewProgress

            if everyoneCompletedReviews {
                reviewResults
            }
        }
    }

    private var battleReportButton: some View {
        Button(action: onShowBattleReport) {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.title2.weight(.black))
                    .frame(width: 44, height: 44)
                    .background(BombTheme.yellow)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("團隊戰報")
                        .font(.headline.weight(.black))
                    Text("查看 AI 分析")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.black))
            }
            .foregroundStyle(BombTheme.ink)
            .padding(16)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(BombTheme.ink, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看團隊戰報 AI 分析")
    }

    private var damageSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                outcome == .completed ? "任務結算摘要" : "戰損摘要",
                systemImage: outcome == .completed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline.weight(.black))
            .foregroundStyle(outcomeColor)

            HStack(spacing: 10) {
                metric(value: "\(clampedProgress)%", label: "完成率")
                metric(value: "\(completedTasks.count)", label: "已完成")
                metric(value: "\(unfinishedTasks.count)", label: "未完成")
            }

            if !unfinishedTasks.isEmpty {
                Divider().overlay(BombTheme.ink.opacity(0.2))

                VStack(alignment: .leading, spacing: 8) {
                    Text("未完成任務")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    ForEach(unfinishedTasks) { task in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(BombTheme.red)
                            Text(task.title)
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack {
                Text("截止時間")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(group.deadline.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.black))
            }
        }
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BombTheme.ink, lineWidth: 3))
    }

    private var peerReviewProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.2.badge.gearshape.fill")
                    .font(.title2.weight(.black))

                VStack(alignment: .leading, spacing: 3) {
                    Text("匿名互評")
                        .font(.headline.weight(.black))
                    Text(myReviewStatus)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("你已評 \(myCompletedReviewCount) / \(otherMemberCount) 位")
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
            }

            ProgressView(value: Double(myCompletedReviewCount), total: Double(max(otherMemberCount, 1)))
                .tint(BombTheme.ink)
                .scaleEffect(y: 1.6)

            if let syncError {
                Label(syncError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BombTheme.red)
            }

            HStack {
                Text("完成全部互評的成員")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completedReviewerCount) / \(reviewParticipantCount) 位")
                    .font(.caption.weight(.black))
            }

            if myCompletedReviewCount < otherMemberCount {
                Button(action: onBeginReview) {
                    Text(myCompletedReviewCount == 0 ? "開始互評" : "繼續互評")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            } else {
                Label(
                    everyoneCompletedReviews ? "全員已完成互評" : "你已完成，等待其他成員",
                    systemImage: everyoneCompletedReviews ? "checkmark.circle.fill" : "clock.fill"
                )
                .font(.subheadline.weight(.black))
                .foregroundStyle(everyoneCompletedReviews ? BombTheme.green : .secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BombTheme.ink, lineWidth: 3))
    }

    private var reviewResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("我的互評結果", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline.weight(.black))

            Text("只顯示你在本次專案收到的匿名評分")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if personalReviewProject == nil {
                if let personalResultSyncError {
                    Label(personalResultSyncError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BombTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(BombTheme.ink)
                        Text("正在整理你的互評結果…")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
            } else {
                ForEach(reviewMetrics) { metric in
                    HStack(spacing: 10) {
                        Text(metric.title)
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        ProgressView(value: metric.average, total: 5)
                            .tint(BombTheme.green)
                            .frame(width: 92)
                        Text(metric.average.formatted(.number.precision(.fractionLength(1))))
                            .font(.subheadline.monospacedDigit().weight(.black))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }

            Divider()
                .overlay(BombTheme.ink.opacity(0.18))

            VStack(alignment: .leading, spacing: 10) {
                Text("收到的匿名評語")
                    .font(.subheadline.weight(.black))

                if reviewComments.isEmpty {
                    Text("這次沒有匿名文字評語")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(reviewComments.enumerated()), id: \.offset) { _, comment in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "quote.bubble.fill")
                                .foregroundStyle(BombTheme.green)
                            Text(comment)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BombTheme.ink, lineWidth: 3))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .black))
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(BombTheme.yellow.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var outcomeColor: Color {
        outcome == .completed ? BombTheme.green : BombTheme.red
    }

    private var clampedProgress: Int {
        outcome == .completed ? 100 : min(max(progress, 0), 100)
    }

    private var completedTasks: [ProjectTask] {
        tasks.filter { $0.progress >= 100 }
    }

    private var unfinishedTasks: [ProjectTask] {
        tasks.filter { $0.progress < 100 }
    }

    private var otherMemberCount: Int {
        members.filter { $0.id != currentUserID }.count
    }

    private var myCompletedReviewCount: Int {
        Set(
            reviews
                .filter { $0.reviewerMemberID == currentUserID }
                .map(\.revieweeMemberID)
        ).count
    }

    private var myReviewStatus: String {
        if myCompletedReviewCount == 0 { return "依本次合作表現完成匿名評分" }
        if myCompletedReviewCount < otherMemberCount { return "還有隊友等你評分" }
        return "你已評完所有隊友"
    }

    private var everyoneCompletedReviews: Bool {
        reviewParticipantCount > 0 && completedReviewerCount >= reviewParticipantCount
    }

    private var reviewParticipantCount: Int {
        let syncedCount = reviewSummary?.participantCount ?? 0
        return syncedCount > 0 ? syncedCount : members.count
    }

    private var reviewMetrics: [SettlementReviewMetric] {
        guard let personalReviewProject else { return [] }
        return [
            SettlementReviewMetric(title: "任務完成", average: personalReviewProject.average(total: personalReviewProject.taskCompletionScoreTotal)),
            SettlementReviewMetric(title: "討論參與", average: personalReviewProject.average(total: personalReviewProject.discussionScoreTotal)),
            SettlementReviewMetric(title: "主動協助", average: personalReviewProject.average(total: personalReviewProject.collaborationScoreTotal)),
            SettlementReviewMetric(title: "解決問題", average: personalReviewProject.average(total: personalReviewProject.ideaScoreTotal)),
            SettlementReviewMetric(title: "準時可靠", average: personalReviewProject.average(total: personalReviewProject.reliabilityScoreTotal))
        ]
    }
}

private struct SettlementReviewMetric: Identifiable {
    let title: String
    let average: Double

    var id: String { title }
}
