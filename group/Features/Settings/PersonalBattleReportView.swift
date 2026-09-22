import SwiftUI
import UIKit

/// Private cumulative report built only from scores received by the signed-in user.
struct PersonalBattleReportView: View {
    @Environment(\.dismiss) private var dismiss
    let model: GroupBombModel
    @State private var exportedReport: ExportedPersonalReport?
    @State private var exportError: String?

    private var projects: [PersonalPeerReviewProject] {
        model.personalReviewProjectsForReport
    }

    private var totalReviewCount: Int {
        projects.reduce(0) { $0 + $1.reviewCount }
    }

    private var hasEnoughEvidence: Bool {
        projects.count >= 3
    }

    private func projectAverage(_ keyPath: KeyPath<PersonalPeerReviewProject, Double>) -> Double {
        guard !projects.isEmpty else { return 0 }
        return projects.reduce(0) { $0 + $1[keyPath: keyPath] } / Double(projects.count)
    }

    private var metrics: [RadarMetric] {
        [
            RadarMetric(title: L10n.text("任務完成"), score: normalized(projectAverage(\.taskCompletionScore))),
            RadarMetric(title: L10n.text("討論參與"), score: normalized(projectAverage(\.discussionScore))),
            RadarMetric(title: L10n.text("主動協助"), score: normalized(projectAverage(\.collaborationScore))),
            RadarMetric(title: L10n.text("解決問題"), score: normalized(projectAverage(\.ideaScore))),
            RadarMetric(title: L10n.text("準時可靠"), score: normalized(projectAverage(\.reliabilityScore)))
        ]
    }

    private var averageScore: Double {
        guard totalReviewCount > 0 else { return 0 }
        let scoreTotal = metrics.reduce(0) { $0 + $1.score } * 5
        return scoreTotal / Double(metrics.count)
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    privacyBanner

                    if projects.isEmpty {
                        emptyState
                    } else {
                        summaryCard

                        if !hasEnoughEvidence {
                            evidencePendingCard
                        }

                        HStack {
                            Text(L10n.text("專案紀錄"))
                                .font(.title2.weight(.black))
                            Spacer()
                            Text(L10n.format("{0} 個專案", String(describing: projects.count)))
                                .font(.caption.weight(.black))
                        }

                        ForEach(projects) { project in
                            ProjectRecordCard(project: project)
                        }

                        Button(action: exportReport) {
                            Label(L10n.text("匯出個人戰力 PDF"), systemImage: "square.and.arrow.up")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .foregroundStyle(.white)
                                .background(BombTheme.ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if let error = model.personalPeerReviewSyncError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .bombTabBarHidden()
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("個人戰力檔案")) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel(L10n.text("返回設定"))
            } trailing: {
                EmptyView()
            }
        }
        .sheet(item: $exportedReport) { report in
            PersonalReportShareSheet(activityItems: [report.url])
        }
        .bombDialog(L10n.text("無法匯出戰力檔案"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(L10n.text("知道了")) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var privacyBanner: some View {
        Label(L10n.text("只有你看得到；匯出時包含分數與專案摘要"), systemImage: "lock.fill")
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(BombTheme.paper.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 42, weight: .black))
            Text(L10n.text("還沒有個人戰力紀錄"))
                .font(.title3.weight(.black))
            Text(L10n.text("專案結束且全員完成互評後，分數會自動累積在這裡。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .comicCard()
    }

    private var summaryCard: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.profileName.isEmpty ? L10n.text("我的累積戰力") : L10n.format("{0}的累積戰力", String(describing: model.profileName)))
                        .font(.headline.weight(.black))
                    Text(L10n.format("{0} 個專案 · {1} 份互評", String(describing: projects.count), String(describing: totalReviewCount)))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f", averageScore))
                    .font(.system(size: 42, weight: .black, design: .rounded))
                Text("/ 5")
                    .font(.caption.weight(.black))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ContributionRadar(metrics: metrics)
                .frame(height: 270)
        }
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
        .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)
    }

    private var evidencePendingCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34, weight: .black))
            Text(L10n.text("資料累積中"))
                .font(.title2.weight(.black))
            Text(L10n.format("目前只有 {0} 個專案，仍可匯出分享，但會標示為初步資料。累積 3 個專案後，結果會更具參考性。", String(describing: projects.count)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ProgressView(value: Double(projects.count), total: 3)
                .tint(BombTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
        .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)
    }

    private func normalized(_ projectScore: Double) -> Double {
        min(max(projectScore / 5, 0), 1)
    }

    private func exportReport() {
        do {
            let url = try PersonalReportPDFExporter.export(
                profileName: model.profileName,
                projects: projects,
                metrics: metrics,
                averageScore: averageScore,
                totalReviewCount: totalReviewCount,
                isPreliminary: !hasEnoughEvidence
            )
            exportedReport = ExportedPersonalReport(url: url)
            model.lastEvent = L10n.text("個人戰力 PDF 已產生")
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct ProjectRecordCard: View {
    let project: PersonalPeerReviewProject

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(BombTheme.yellow, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(project.groupName)
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                Text(project.completedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(project.overallAverage.formatted(.number.precision(.fractionLength(1)))) / 5")
                    .font(.title3.weight(.black).monospacedDigit())
                Text(L10n.text("專案平均"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                if project.excludedReviewCount > 0 {
                    Text(L10n.format("已排除 {0} 份異常評分", String(describing: project.excludedReviewCount)))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .comicCard()
    }
}

private struct ExportedPersonalReport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PersonalReportShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private enum PersonalReportPDFExporter {
    private static let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)

    static func export(
        profileName: String,
        projects: [PersonalPeerReviewProject],
        metrics: [RadarMetric],
        averageScore: Double,
        totalReviewCount: Int,
        isPreliminary: Bool
    ) throws -> URL {
        let displayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.text("我的")
            : profileName
        let filename = L10n.format("{0}-個人戰力檔案-{1}.pdf", String(describing: safeFilename(displayName)), String(describing: timestamp()))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: L10n.format("{0} 個人戰力檔案", String(describing: displayName)),
            kCGPDFContextCreator as String: "Group Bomb"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)

        try renderer.writePDF(to: url) { context in
            let writer = PersonalReportPDFWriter(
                context: context,
                pageBounds: pageBounds,
                displayName: displayName
            )
            writer.beginPage()
            writer.drawSummary(
                projectCount: projects.count,
                reviewCount: totalReviewCount,
                averageScore: averageScore,
                isPreliminary: isPreliminary
            )

            writer.drawSectionTitle(L10n.text("五項能力平均"))
            for metric in metrics {
                writer.drawMetric(title: metric.title, score: metric.score * 5)
            }

            writer.drawSectionTitle(L10n.text("專案紀錄"))
            for project in projects {
                writer.drawProject(project)
            }

            writer.drawSectionTitle(L10n.text("資料說明"))
            writer.drawBody(L10n.text("本檔案依不同專案中收到的匿名互評彙整；已排除的異常評分不列入計算。互評可能受合作情境與主觀感受影響，不應作為分組、評分或考核的唯一依據。"))
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
            throw PersonalReportPDFExportError.emptyFile
        }
        return url
    }

    private static func safeFilename(_ value: String) -> String {
        let pieces = value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? "Group-Bomb" : pieces.joined(separator: "-")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

private enum PersonalReportPDFExportError: LocalizedError {
    case emptyFile

    var errorDescription: String? {
        L10n.text("PDF 產生失敗，請稍後再試。")
    }
}

private final class PersonalReportPDFWriter {
    private let context: UIGraphicsPDFRendererContext
    private let pageBounds: CGRect
    private let displayName: String
    private let margin: CGFloat = 40
    private let footerHeight: CGFloat = 44
    private var cursorY: CGFloat = 0

    private let yellow = UIColor(red: 1, green: 0.79, blue: 0.05, alpha: 1)
    private let ink = UIColor(red: 0.08, green: 0.08, blue: 0.07, alpha: 1)
    private let secondary = UIColor(white: 0.38, alpha: 1)
    private let rule = UIColor(white: 0.86, alpha: 1)

    init(context: UIGraphicsPDFRendererContext, pageBounds: CGRect, displayName: String) {
        self.context = context
        self.pageBounds = pageBounds
        self.displayName = displayName
    }

    func beginPage() {
        context.beginPage()
        UIColor.white.setFill()
        context.cgContext.fill(pageBounds)

        yellow.setFill()
        context.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 118))
        drawRawText(
            "GROUP BOMB",
            x: margin,
            y: 24,
            width: pageBounds.width - margin * 2,
            height: 20,
            font: .systemFont(ofSize: 14, weight: .black),
            color: ink
        )
        drawRawText(
            L10n.text("個人戰力檔案"),
            x: margin,
            y: 47,
            width: pageBounds.width - margin * 2,
            height: 40,
            font: .systemFont(ofSize: 28, weight: .black),
            color: ink
        )
        drawRawText(
            displayName,
            x: margin,
            y: 91,
            width: pageBounds.width - margin * 2,
            height: 20,
            font: .systemFont(ofSize: 12, weight: .bold),
            color: ink
        )

        let footer = L10n.format("{0}  ·  匯出於 {1}", String(describing: displayName), String(describing: Date.now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))))
        drawRawText(
            footer,
            x: margin,
            y: pageBounds.height - 30,
            width: pageBounds.width - margin * 2,
            height: 16,
            font: .systemFont(ofSize: 9, weight: .medium),
            color: secondary
        )
        cursorY = 138
    }

    func drawSummary(
        projectCount: Int,
        reviewCount: Int,
        averageScore: Double,
        isPreliminary: Bool
    ) {
        ensureSpace(108)
        let rect = CGRect(x: margin, y: cursorY, width: pageBounds.width - margin * 2, height: 92)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
        UIColor(white: 0.96, alpha: 1).setFill()
        path.fill()
        ink.setStroke()
        path.lineWidth = 2
        path.stroke()

        drawRawText(
            L10n.format("累積 {0} 個專案 · {1} 份匿名互評", String(describing: projectCount), String(describing: reviewCount)),
            x: rect.minX + 16,
            y: rect.minY + 15,
            width: rect.width - 145,
            height: 22,
            font: .systemFont(ofSize: 14, weight: .black),
            color: ink
        )
        drawRawText(
            isPreliminary ? L10n.text("整體平均 · 初步資料") : L10n.text("整體平均 · 已累積足夠專案"),
            x: rect.minX + 16,
            y: rect.minY + 43,
            width: rect.width - 145,
            height: 18,
            font: .systemFont(ofSize: 11, weight: .bold),
            color: secondary
        )
        drawRawText(
            String(format: "%.1f / 5", averageScore),
            x: rect.maxX - 125,
            y: rect.minY + 23,
            width: 105,
            height: 32,
            font: .monospacedDigitSystemFont(ofSize: 22, weight: .black),
            color: ink,
            alignment: .right
        )
        if isPreliminary {
            drawRawText(
                L10n.text("專案數較少，分數可能隨後續合作明顯變動。"),
                x: rect.minX + 16,
                y: rect.minY + 66,
                width: rect.width - 32,
                height: 16,
                font: .systemFont(ofSize: 9.5, weight: .medium),
                color: secondary
            )
        }
        cursorY = rect.maxY + 16
    }

    func drawSectionTitle(_ title: String) {
        ensureSpace(54)
        let rect = CGRect(x: margin, y: cursorY, width: pageBounds.width - margin * 2, height: 36)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        yellow.setFill()
        path.fill()
        drawRawText(
            title,
            x: rect.minX + 14,
            y: rect.minY + 8,
            width: rect.width - 28,
            height: 22,
            font: .systemFont(ofSize: 16, weight: .black),
            color: ink
        )
        cursorY = rect.maxY + 12
    }

    func drawMetric(title: String, score: Double) {
        ensureSpace(34)
        let boundedScore = min(max(score, 0), 5)
        drawRawText(
            title,
            x: margin,
            y: cursorY,
            width: 100,
            height: 20,
            font: .systemFont(ofSize: 12, weight: .bold),
            color: ink
        )
        drawRawText(
            String(format: "%.1f", boundedScore),
            x: pageBounds.width - margin - 52,
            y: cursorY,
            width: 52,
            height: 20,
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .black),
            color: ink,
            alignment: .right
        )

        let barX = margin + 108
        let barWidth = pageBounds.width - margin * 2 - 172
        let barRect = CGRect(x: barX, y: cursorY + 5, width: barWidth, height: 8)
        rule.setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 4).fill()
        yellow.setFill()
        UIBezierPath(
            roundedRect: CGRect(
                x: barX,
                y: cursorY + 5,
                width: barWidth * CGFloat(boundedScore / 5),
                height: 8
            ),
            cornerRadius: 4
        ).fill()
        cursorY += 28
    }

    func drawProject(_ project: PersonalPeerReviewProject) {
        ensureSpace(102)
        let rect = CGRect(x: margin, y: cursorY, width: pageBounds.width - margin * 2, height: 88)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        UIColor(white: 0.97, alpha: 1).setFill()
        path.fill()
        rule.setStroke()
        path.lineWidth = 1
        path.stroke()

        drawRawText(
            project.groupName,
            x: rect.minX + 14,
            y: rect.minY + 12,
            width: rect.width - 130,
            height: 22,
            font: .systemFont(ofSize: 14, weight: .black),
            color: ink
        )
        drawRawText(
            project.completedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)),
            x: rect.minX + 14,
            y: rect.minY + 36,
            width: rect.width - 150,
            height: 18,
            font: .systemFont(ofSize: 10, weight: .medium),
            color: secondary
        )
        drawRawText(
            L10n.format("{0} 份採計", String(describing: project.acceptedReviewCount)) + (project.excludedReviewCount > 0 ? L10n.format(" · 排除 {0} 份", String(describing: project.excludedReviewCount)) : ""),
            x: rect.minX + 14,
            y: rect.minY + 58,
            width: rect.width - 150,
            height: 18,
            font: .systemFont(ofSize: 10, weight: .bold),
            color: secondary
        )
        drawRawText(
            String(format: "%.1f / 5", project.overallAverage),
            x: rect.maxX - 116,
            y: rect.minY + 28,
            width: 98,
            height: 28,
            font: .monospacedDigitSystemFont(ofSize: 18, weight: .black),
            color: ink,
            alignment: .right
        )
        cursorY = rect.maxY + 12
    }

    func drawBody(_ text: String) {
        let font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        let width = pageBounds.width - margin * 2
        let height = measuredHeight(text, width: width, font: font, lineSpacing: 3)
        ensureSpace(height + 14)
        drawRawText(
            text,
            x: margin,
            y: cursorY,
            width: width,
            height: height,
            font: font,
            color: secondary,
            lineSpacing: 3
        )
        cursorY += height + 14
    }

    private func ensureSpace(_ height: CGFloat) {
        if cursorY + height > pageBounds.height - footerHeight {
            beginPage()
        }
    }

    private func measuredHeight(
        _ text: String,
        width: CGFloat,
        font: UIFont,
        lineSpacing: CGFloat = 0
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        ).height)
    }

    private func drawRawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat = 24,
        font: UIFont,
        color: UIColor,
        lineSpacing: CGFloat = 0,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = alignment
        (text as NSString).draw(
            in: CGRect(x: x, y: y, width: width, height: height),
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}
