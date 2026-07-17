import SwiftUI

/// Combined peer-review and AI report styled like a compact team report card.
struct PeerReviewReportView: View {
    let model: GroupBombModel

    private var averageScore: Int {
        guard !model.radar.isEmpty else { return 0 }
        return Int(model.radar.map(\.score).reduce(0, +) / Double(model.radar.count) * 100)
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("貢獻雷達")
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                        Spacer()
                        Text("匿名互評")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(BombTheme.ink)
                            .foregroundStyle(BombTheme.yellow)
                            .clipShape(.capsule)
                    }

                    RadarReportCard(metrics: model.radar, averageScore: averageScore)

                    Text("AI 戰情成績單")
                        .font(.title2.weight(.black))
                    AIReportCard(model: model)

                    GeometryReader { proxy in
                        Button {
                            model.lastEvent = "PDF 戰報已準備完成"
                        } label: {
                            Label("匯出貢獻戰報 PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BombTheme.ink)
                        .frame(width: proxy.size.width * 0.6)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 44)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("團隊戰報")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BombTheme.yellow, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct RadarReportCard: View {
    let metrics: [RadarMetric]
    let averageScore: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("團隊貢獻指數")
                        .font(.headline.weight(.black))
                    Text("第 4 組｜4 位完成互評")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(averageScore)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)

            ContributionRadar(metrics: metrics)
                .frame(height: 280)
        }
        .foregroundStyle(BombTheme.ink)
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
        .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)
    }
}

private struct AIReportCard: View {
    let model: GroupBombModel

    var body: some View {
        VStack(spacing: 0) {
            CommunicationAnalysisRow(analysis: model.latestCommunicationAnalysis)
            Divider()
            AIReportRow(
                icon: "chart.bar.fill",
                title: "團隊進度摘要",
                detail: "團隊目前完成 \(model.teamProgress)%，多數任務皆按計畫推進，整體進度維持穩定。"
            )
            Divider()
            AIReportRow(
                icon: "exclamationmark.triangle.fill",
                title: "延誤風險",
                detail: "米米目前進度偏慢，可能影響後續整合，建議優先確認交付時間與需要的支援。"
            )
            Divider()
            AIReportRow(
                icon: "arrow.right.circle.fill",
                title: "建議下一步",
                detail: "先完成市場資料整理與來源確認，再集中處理簡報視覺統整，降低重複修改。"
            )
        }
        .comicCard()
    }
}

/// 顯示聊天室機器人寫入 AppStore 的最新評分，尚未分析時保留明確的空狀態。
private struct CommunicationAnalysisRow: View {
    let analysis: CommunicationAnalysis?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(BombTheme.yellow)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("AI 溝通分析").font(.subheadline.weight(.black))
                    Spacer()
                    if let analysis {
                        Text("\(analysis.score) 分")
                            .font(.caption.weight(.black).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BombTheme.yellow)
                            .clipShape(.capsule)
                    }
                }
                Text(analysis?.summary ?? "尚未分析聊天室對話；到聊天室點選「AI 分析」即可產生報告。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let analysis {
                    Text("建議：\(analysis.suggestion)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BombTheme.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}

private struct AIReportRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(BombTheme.yellow)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.black))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}

/// Radar rendering with percentage labels and a yellow score area.
struct ContributionRadar: View {
    let metrics: [RadarMetric]

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2 + 4)
            let radius = min(proxy.size.width, proxy.size.height) * 0.31
            Canvas { context, _ in
                let count = metrics.count
                guard count > 2 else { return }

                var scoreShape = Path()
                for (index, metric) in metrics.enumerated() {
                    let point = radarPoint(index: index, count: count, radius: radius * metric.score, center: center)
                    index == 0 ? scoreShape.move(to: point) : scoreShape.addLine(to: point)
                }
                scoreShape.closeSubpath()
                context.fill(scoreShape, with: .color(BombTheme.yellow.opacity(0.38)))

                for level in 1...4 {
                    var ring = Path()
                    for index in 0..<count {
                        let point = radarPoint(index: index, count: count, radius: radius * Double(level) / 4, center: center)
                        index == 0 ? ring.move(to: point) : ring.addLine(to: point)
                    }
                    ring.closeSubpath()
                    context.stroke(ring, with: .color(.white.opacity(0.9)), lineWidth: level == 4 ? 2.3 : 1.6)
                }

                for index in 0..<count {
                    var axis = Path()
                    axis.move(to: center)
                    axis.addLine(to: radarPoint(index: index, count: count, radius: radius, center: center))
                    context.stroke(axis, with: .color(.white.opacity(0.82)), lineWidth: 1.5)
                }

                context.stroke(scoreShape, with: .color(BombTheme.yellow), lineWidth: 4)
                for (index, metric) in metrics.enumerated() {
                    let point = radarPoint(index: index, count: count, radius: radius * metric.score, center: center)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(BombTheme.yellow))
                }
            }
            .overlay {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    VStack(spacing: 0) {
                        Text("\(Int(metric.score * 100))%")
                            .font(.caption.weight(.black).monospacedDigit())
                        Text(metric.title)
                            .font(.subheadline.weight(.black))
                    }
                    .foregroundStyle(BombTheme.ink)
                    .position(radarPoint(index: index, count: metrics.count, radius: radius * 1.28, center: center))
                }
            }
        }
    }

    private func radarPoint(index: Int, count: Int, radius: Double, center: CGPoint) -> CGPoint {
        let angle = (Double(index) / Double(count) * 2 * .pi) - (.pi / 2)
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}
