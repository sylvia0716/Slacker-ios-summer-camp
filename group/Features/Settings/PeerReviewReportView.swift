import SwiftUI

/// Existing anonymous peer-review report. Future work: place it inside the Settings feature entry screen.
struct PeerReviewReportView: View {
    let model: GroupBombModel

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("貢獻雷達").font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text("匿名互評｜第 4 組").font(.subheadline.bold())
                    ContributionRadar(metrics: model.radar).frame(height: 310).comicCard()
                    ForEach(model.radar) { metric in
                        HStack {
                            Text(metric.title).font(.headline)
                            Spacer()
                            Text("\(Int(metric.score * 100)) 分").font(.headline.monospacedDigit())
                        }
                        .padding(.horizontal, 4)
                    }
                    Button { model.lastEvent = "PDF 戰報已準備完成" } label: {
                        Label("匯出貢獻戰報 PDF", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BombTheme.ink)
                    Text(model.lastEvent).font(.footnote.bold())
                }
                .padding(16)
            }
        }
        .navigationTitle("雷達")
    }
}

/// Canvas-only rendering of peer-review metrics. It owns no report data.
struct ContributionRadar: View {
    let metrics: [RadarMetric]

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.32
            Canvas { context, _ in
                let count = metrics.count
                guard count > 2 else { return }
                for level in 1...4 {
                    var ring = Path()
                    for index in 0..<count {
                        let point = radarPoint(index: index, count: count, radius: radius * Double(level) / 4, center: center)
                        index == 0 ? ring.move(to: point) : ring.addLine(to: point)
                    }
                    ring.closeSubpath()
                    context.stroke(ring, with: .color(BombTheme.ink.opacity(0.22)), lineWidth: 1)
                }
                var shape = Path()
                for (index, metric) in metrics.enumerated() {
                    let point = radarPoint(index: index, count: count, radius: radius * metric.score, center: center)
                    index == 0 ? shape.move(to: point) : shape.addLine(to: point)
                }
                shape.closeSubpath()
                context.fill(shape, with: .color(BombTheme.red.opacity(0.48)))
                context.stroke(shape, with: .color(BombTheme.ink), lineWidth: 3)
            }
            .overlay {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    Text(metric.title).font(.caption.weight(.black))
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
