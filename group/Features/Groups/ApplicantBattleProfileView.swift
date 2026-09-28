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
            Text(L10n.text("個人戰力檔案"))
                .font(.title2.weight(.black))
            if projects.isEmpty {
                ContentUnavailableView(L10n.text("尚無歷史戰力紀錄"), systemImage: "chart.bar.xaxis")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.format("累積 {0} 個專案 · {1} 份匿名互評",
                                     String(projects.count), String(projects.reduce(0) { $0 + $1.reviewCount })))
                        .font(.subheadline.bold())
                    ForEach(metrics) { metric in
                        HStack {
                            Text(metric.title)
                            Spacer()
                            Text("\(metric.score.formatted(.number.precision(.fractionLength(1)))) / 5")
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        ProgressView(value: min(max(metric.score, 0), 5), total: 5)
                            .tint(BombTheme.ink)
                            .accessibilityLabel(metric.title)
                    }
                    if projects.count < 3 {
                        Text(L10n.text("專案數較少，分數僅供初步參考。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .comicCard()
                ForEach(projects) { project in
                    ProjectRecordCard(project: project)
                }
            }
        }
    }
}
