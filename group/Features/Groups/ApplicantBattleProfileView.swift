import SwiftUI

/// Receives the applicant's authorized history, never the leader's own report.
struct ApplicantBattleProfileView: View {
    let projects: [PersonalPeerReviewProject]

    private struct Metric: Identifiable {
        let title: String
        let score: Double
        var id: String { title }
    }

    private var metrics: [Metric] {
        func average(_ key: KeyPath<PersonalPeerReviewProject, Double>) -> Double {
            guard !projects.isEmpty else { return 0 }
            return projects.reduce(0) { $0 + $1[keyPath: key] } / Double(projects.count)
        }
        return [
            Metric(title: L10n.text("任務完成"), score: average(\.taskCompletionScore)),
            Metric(title: L10n.text("討論參與"), score: average(\.discussionScore)),
            Metric(title: L10n.text("主動協助"), score: average(\.collaborationScore)),
            Metric(title: L10n.text("解決問題"), score: average(\.ideaScore)),
            Metric(title: L10n.text("準時可靠"), score: average(\.reliabilityScore))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if projects.isEmpty {
                ContentUnavailableView(L10n.text("尚無歷史戰力紀錄"), systemImage: "chart.bar.xaxis")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("能力概覽"))
                        .font(.title3.weight(.black))
                    Text(L10n.format("累積 {0} 個專案 · {1} 份匿名互評",
                                     String(projects.count), String(projects.reduce(0) { $0 + $1.reviewCount })))
                        .font(.caption)
                        .foregroundStyle(BombTheme.secondaryText)
                    ForEach(metrics) { metric in
                        VStack(spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(metric.title)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                score(metric.score, font: .headline)
                            }
                            ProgressView(value: min(max(metric.score, 0), 5), total: 5)
                                .tint(scoreColor(metric.score))
                                .accessibilityLabel(metric.title)
                        }
                    }
                    if projects.count < 3 {
                        Text(L10n.text("專案數較少，分數僅供初步參考。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text(L10n.text("專案紀錄"))
                    .font(.title3.weight(.black))
                ForEach(projects) { project in
                    VStack(alignment: .leading, spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(project.groupName).font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 8)
                                score(project.overallAverage, font: .title2)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(project.groupName).font(.headline)
                                score(project.overallAverage, font: .title2)
                            }
                        }
                        Text(project.completedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)))
                            .font(.caption)
                            .foregroundStyle(BombTheme.secondaryText)
                        if project.excludedReviewCount > 0 {
                            Text(L10n.format("已排除 {0} 份異常評分", String(project.excludedReviewCount)))
                                .font(.caption2)
                                .foregroundStyle(BombTheme.secondaryText)
                        }
                    }
                    if project.id != projects.last?.id { Divider() }
                }
            }
        }
        .foregroundStyle(BombTheme.ink)
    }

    private func scoreColor(_ value: Double) -> Color {
        value < 3 ? BombTheme.red : BombTheme.ink
    }

    private func score(_ value: Double, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value.formatted(.number.precision(.fractionLength(1))))
                .font(font.weight(.black))
                .foregroundStyle(scoreColor(value))
            Text("/ 5")
                .font(.caption)
                .foregroundStyle(BombTheme.secondaryText)
        }
        .monospacedDigit()
        .fixedSize()
    }
}
