import SwiftUI
import UIKit

/// Combined peer-review and AI report styled like a compact team report card.
struct PeerReviewReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bombSafeAreaInsets) private var safeAreaInsets
    let model: GroupBombModel
    let group: Group
    @State private var isGeneratingAnalysis = false
    @State private var analysisError: String?
    @State private var exportedReport: ExportedTeamReport?
    @State private var exportError: String?

    private var projectAnalysis: CommunicationAnalysis? {
        model.communicationAnalyses[group.id]
    }

    private var resultsAvailable: Bool {
        projectAnalysis?.taskCompletionScore != nil
            && projectAnalysis?.discussionScore != nil
            && projectAnalysis?.collaborationScore != nil
            && projectAnalysis?.problemSolvingScore != nil
            && projectAnalysis?.reliabilityScore != nil
    }

    private var reportMetrics: [RadarMetric] {
        return [
            RadarMetric(title: L10n.text("任務完成"), score: normalizedScore(projectAnalysis?.taskCompletionScore)),
            RadarMetric(title: L10n.text("討論參與"), score: normalizedScore(projectAnalysis?.discussionScore)),
            RadarMetric(title: L10n.text("主動協助"), score: normalizedScore(projectAnalysis?.collaborationScore)),
            RadarMetric(title: L10n.text("解決問題"), score: normalizedScore(projectAnalysis?.problemSolvingScore)),
            RadarMetric(title: L10n.text("準時可靠"), score: normalizedScore(projectAnalysis?.reliabilityScore))
        ]
    }

    private var averageScore: Int? {
        guard resultsAvailable else { return nil }
        return Int(reportMetrics.map(\.score).reduce(0, +) / Double(reportMetrics.count) * 100)
    }

    private var groupTasks: [ProjectTask] {
        model.projectTasks.filter { $0.groupID == group.id }
    }

    private var groupMembers: [Member] {
        group.memberIDs.compactMap { memberID in
            model.members.first { $0.id == memberID }
        }
    }

    private func normalizedScore(_ score: Int?) -> Double {
        guard let score else { return 0 }
        return min(max(Double(score) / 100, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.text("AI 專案雷達"))
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                        Spacer()
                        Button(action: exportReport) {
                            Label(L10n.text("匯出戰報"), systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.black))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(BombTheme.ink)
                                .foregroundStyle(BombTheme.yellow)
                                .clipShape(.capsule)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("匯出團隊戰報 PDF"))
                    }

                    RadarReportCard(
                        metrics: reportMetrics,
                        averageScore: averageScore,
                        groupName: group.name,
                        analysisUpdatedAt: projectAnalysis?.updatedAt,
                        resultsAvailable: resultsAvailable,
                        isGenerating: isGeneratingAnalysis,
                        errorMessage: analysisError,
                        onRetry: { Task { await generateAnalysis() } }
                    )

                    Text(L10n.text("專案成果與 AI 復盤"))
                        .font(.title2.weight(.black))
                    AIReportCard(
                        progress: model.projectProgress(for: group.id),
                        tasks: groupTasks,
                        analysis: model.communicationAnalyses[group.id]
                    )

                    Text(L10n.text("成員貢獻明細"))
                        .font(.title2.weight(.black))

                    Label(
                        L10n.text("依 App 內紀錄整理，不包含口頭討論或線下工作，不應作為評分或考核的唯一依據。"),
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BombTheme.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                    if groupMembers.isEmpty {
                        Text(L10n.text("目前沒有可顯示的成員紀錄。"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(BombTheme.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
                    } else {
                        ForEach(groupMembers) { member in
                            MemberContributionCard(
                                firestoreGroupID: group.firestoreDocumentID,
                                member: member,
                                role: group.memberRoles[member.id] ?? member.role,
                                tasks: groupTasks.filter { $0.ownerMemberID == member.id }
                            )
                        }
                    }

                }
                .padding(16)
                .padding(.bottom, 24)
            }

            LinearGradient(
                colors: [BombTheme.yellow.opacity(0), BombTheme.yellow.opacity(0.82), BombTheme.yellow],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
            .offset(y: safeAreaInsets.bottom)
            .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .bombTabBarHidden()
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("團隊戰報")) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel(L10n.text("返回專案結算"))
            } trailing: {
                EmptyView()
            }
        }
        .task {
            guard !resultsAvailable else { return }
            await generateAnalysis()
        }
        .sheet(item: $exportedReport) { report in
            TeamReportShareSheet(activityItems: [report.url])
        }
        .bombDialog(L10n.text("無法匯出戰報"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(L10n.text("知道了")) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func generateAnalysis() async {
        guard !isGeneratingAnalysis else { return }
        isGeneratingAnalysis = true
        analysisError = nil
        defer { isGeneratingAnalysis = false }
        do {
            _ = try await model.generateProjectAIAnalysis(groupID: group.id)
        } catch is CancellationError {
            return
        } catch {
            analysisError = error.localizedDescription
        }
    }

    private func exportReport() {
        do {
            let url = try TeamReportPDFExporter.export(
                group: group,
                progress: model.projectProgress(for: group.id),
                tasks: groupTasks,
                members: groupMembers,
                analysis: projectAnalysis
            )
            exportedReport = ExportedTeamReport(url: url)
            model.lastEvent = L10n.text("團隊戰報 PDF 已產生")
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct RadarReportCard: View {
    let metrics: [RadarMetric]
    let averageScore: Int?
    let groupName: String
    let analysisUpdatedAt: Date?
    let resultsAvailable: Bool
    let isGenerating: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("AI 團隊協作指數"))
                        .font(.headline.weight(.black))
                    Text(analysisUpdatedAt.map {
                        "\(groupName)｜\($0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))"
                    } ?? L10n.format("{0}｜根據任務與討論紀錄", String(describing: groupName)))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(averageScore.map(String.init) ?? "—")
                    .font(.system(size: 42, weight: .black, design: .rounded))
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)

            ContributionRadar(metrics: metrics)
                .frame(height: 280)
                .overlay {
                    if !resultsAvailable {
                        VStack(spacing: 10) {
                            if isGenerating {
                                ProgressView()
                                    .tint(BombTheme.ink)
                                Text(L10n.text("AI 正在分析專案紀錄…"))
                                    .font(.subheadline.weight(.black))
                            } else {
                                Text(errorMessage ?? L10n.text("尚未產生 AI 專案分析"))
                                    .font(.subheadline.weight(.black))
                                    .multilineTextAlignment(.center)
                                Button(L10n.text("重新分析"), action: onRetry)
                                    .font(.caption.weight(.black))
                                    .buttonStyle(.borderedProminent)
                                    .tint(BombTheme.ink)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 250)
                        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, lineWidth: 2))
                    }
                }
        }
        .foregroundStyle(BombTheme.ink)
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
    }
}

private struct AIReportCard: View {
    let progress: Int
    let tasks: [ProjectTask]
    let analysis: CommunicationAnalysis?

    private var completedTaskCount: Int {
        tasks.filter { $0.progress >= 100 }.count
    }

    private var finalOutcomeDetail: String {
        let totalCount = tasks.count
        let unfinishedCount = max(totalCount - completedTaskCount, 0)
        guard totalCount > 0 else {
            return L10n.format("本次專案沒有建立任務紀錄，最終完成度為 {0}%。", String(describing: progress))
        }
        return L10n.format("最終完成度 {0}%，完成 {1} / {2} 項任務，未完成 {3} 項。", String(describing: progress), String(describing: completedTaskCount), String(describing: totalCount), String(describing: unfinishedCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            AIReportRow(
                icon: "checkmark.seal.fill", title: L10n.text("最終任務成果"),
                detail: finalOutcomeDetail
            )
            Divider()
            CommunicationAnalysisRow(analysis: analysis)
            Divider()
            AIReportRow(
                icon: "doc.text.magnifyingglass", title: L10n.text("專案復盤結論"),
                detail: analysis?.strength ?? L10n.text("AI 分析完成後，將整理本次專案值得延續的合作方式。")
            )
            Divider()
            AIReportRow(
                icon: "arrow.clockwise.circle.fill", title: L10n.text("下次合作建議"),
                detail: analysis?.suggestion ?? L10n.text("AI 分析完成後，將提供下一次合作可採取的改善方向。")
            )
        }
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
    }
}

private struct MemberContributionCard: View {
    let firestoreGroupID: String?
    let member: Member
    let role: MemberRole
    let tasks: [ProjectTask]

    private var completedTaskCount: Int {
        tasks.filter { $0.progress >= 100 }.count
    }

    private var averageProgress: Int {
        guard !tasks.isEmpty else { return 0 }
        return tasks.reduce(0) { $0 + $1.progress } / tasks.count
    }

    private var totalSubtaskCount: Int {
        tasks.reduce(0) { $0 + $1.subtasks.count }
    }

    private var completedSubtaskCount: Int {
        tasks.reduce(0) { total, task in
            total + task.subtasks.filter(\.isComplete).count
        }
    }

    private var submittedDeliverableCount: Int {
        tasks.compactMap(\.deliverable).count
    }

    private var approvedDeliverableCount: Int {
        tasks.compactMap(\.deliverable).filter(\.isApproved).count
    }

    private var overdueIncompleteCount: Int {
        tasks.filter {
            $0.deadline != .distantFuture && $0.deadline < .now && $0.progress < 100
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MemberPhotoAvatar(groupID: firestoreGroupID, uid: member.firebaseUID, name: member.name, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.headline.weight(.black))
                    Text(role.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(averageProgress)%")
                    .font(.title2.weight(.black).monospacedDigit())
            }

            if tasks.isEmpty {
                Text(L10n.text("目前沒有指派給此成員的任務紀錄。"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: Double(averageProgress), total: 100)
                    .tint(BombTheme.ink)
                    .scaleEffect(y: 1.4)

                Grid(horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        contributionValue("\(completedTaskCount) / \(tasks.count)", label: L10n.text("完成任務"))
                        contributionValue("\(completedSubtaskCount) / \(totalSubtaskCount)", label: L10n.text("完成子任務"))
                    }
                    GridRow {
                        contributionValue("\(submittedDeliverableCount)", label: L10n.text("成果交付"))
                        contributionValue("\(approvedDeliverableCount)", label: L10n.text("成果驗收"))
                    }
                }

                if overdueIncompleteCount > 0 {
                    Label(L10n.format("期限已過且尚未完成 {0} 項", String(describing: overdueIncompleteCount)), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(BombTheme.red)
                }

                Divider()

                ForEach(tasks.sorted(by: { $0.deadline < $1.deadline })) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(task.progress >= 100 ? BombTheme.green : BombTheme.yellow)
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.subheadline.weight(.black))
                            Text(taskDeadlineText(task))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(task.progress)%")
                            .font(.subheadline.weight(.black).monospacedDigit())
                    }
                }
            }
        }
        .padding(16)
        .background(BombTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 3))
    }

    private func contributionValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.black).monospacedDigit())
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func taskDeadlineText(_ task: ProjectTask) -> String {
        guard task.deadline != .distantFuture else { return L10n.text("未設定期限") }
        return L10n.format("期限 {0}", String(describing: task.deadline.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))))
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
                    Text(L10n.text("AI 溝通分析")).font(.subheadline.weight(.black))
                    Spacer()
                    if let analysis {
                        Text(L10n.format("{0} 分", String(describing: analysis.score)))
                            .font(.caption.weight(.black).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BombTheme.yellow)
                            .clipShape(.capsule)
                    }
                }
                Text(analysis?.summary ?? L10n.text("尚未分析聊天室對話；到聊天室點選「AI 分析」即可產生報告。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

private struct ExportedTeamReport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct TeamReportShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

private enum TeamReportPDFExporter {
    private static let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)

    static func export(
        group: Group,
        progress: Int,
        tasks: [ProjectTask],
        members: [Member],
        analysis: CommunicationAnalysis?
    ) throws -> URL {
        let filename = L10n.format("{0}-團隊戰報-{1}.pdf", String(describing: safeFilename(group.name)), String(describing: timestamp()))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: L10n.format("{0} 團隊戰報", String(describing: group.name)),
            kCGPDFContextCreator as String: "Group Bomb"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)

        try renderer.writePDF(to: url) { context in
            let writer = TeamReportPDFWriter(context: context, pageBounds: pageBounds, group: group)
            writer.beginPage()

            let metricScores: [(String, Int?)] = [
                (L10n.text("任務完成"), analysis?.taskCompletionScore),
                (L10n.text("討論參與"), analysis?.discussionScore),
                (L10n.text("主動協助"), analysis?.collaborationScore),
                (L10n.text("解決問題"), analysis?.problemSolvingScore),
                (L10n.text("準時可靠"), analysis?.reliabilityScore)
            ]
            writer.drawSectionTitle(L10n.text("AI 團隊協作指數"))
            for metric in metricScores {
                writer.drawMetric(title: metric.0, score: metric.1)
            }

            let completedCount = tasks.filter { $0.progress >= 100 }.count
            writer.drawSectionTitle(L10n.text("最終任務成果"))
            writer.drawBody(L10n.format("最終完成度 {0}%，完成 {1} / {2} 項任務，未完成 {3} 項。", String(describing: progress), String(describing: completedCount), String(describing: tasks.count), String(describing: max(tasks.count - completedCount, 0))))

            if !tasks.isEmpty {
                writer.drawSubheading(L10n.text("任務明細"))
                for task in tasks.sorted(by: { $0.deadline < $1.deadline }) {
                    writer.drawTask(task)
                }
            }

            writer.drawSectionTitle(L10n.text("成員貢獻明細"))
            writer.drawBody(L10n.text("以下內容依 App 內的任務、子任務、期限與成果紀錄整理，未包含口頭討論或線下工作，不應作為評分或考核的唯一依據。"))
            if members.isEmpty {
                writer.drawBody(L10n.text("目前沒有可匯出的成員紀錄。"))
            } else {
                for member in members {
                    let memberTasks = tasks.filter { $0.ownerMemberID == member.id }
                    writer.drawMemberContribution(
                        member: member,
                        role: group.memberRoles[member.id] ?? member.role,
                        tasks: memberTasks
                    )
                }
            }

            writer.drawSectionTitle(L10n.text("AI 溝通分析"))
            if let analysis {
                writer.drawBody(L10n.format("溝通分數：{0} 分", String(describing: analysis.score)))
                writer.drawBody(analysis.summary)
            } else {
                writer.drawBody(L10n.text("尚未產生 AI 溝通分析。"))
            }

            writer.drawSectionTitle(L10n.text("專案復盤結論"))
            writer.drawBody(analysis?.strength ?? L10n.text("尚未產生 AI 專案復盤結論。"))

            writer.drawSectionTitle(L10n.text("下次合作建議"))
            writer.drawBody(analysis?.suggestion ?? L10n.text("尚未產生下一次合作建議。"))
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
            throw TeamReportPDFExportError.emptyFile
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

private enum TeamReportPDFExportError: LocalizedError {
    case emptyFile

    var errorDescription: String? {
        L10n.text("PDF 產生失敗，請稍後再試。")
    }
}

private final class TeamReportPDFWriter {
    private let context: UIGraphicsPDFRendererContext
    private let pageBounds: CGRect
    private let group: Group
    private let margin: CGFloat = 40
    private let footerHeight: CGFloat = 44
    private var cursorY: CGFloat = 0

    private let yellow = UIColor(red: 1, green: 0.79, blue: 0.05, alpha: 1)
    private let ink = UIColor(red: 0.08, green: 0.08, blue: 0.07, alpha: 1)
    private let secondary = UIColor(white: 0.38, alpha: 1)
    private let rule = UIColor(white: 0.86, alpha: 1)

    init(context: UIGraphicsPDFRendererContext, pageBounds: CGRect, group: Group) {
        self.context = context
        self.pageBounds = pageBounds
        self.group = group
    }

    func beginPage() {
        context.beginPage()
        UIColor.white.setFill()
        context.cgContext.fill(pageBounds)

        yellow.setFill()
        context.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 118))
        drawRawText("GROUP BOMB", x: margin, y: 24, width: pageBounds.width - margin * 2,
                    height: 20, font: .systemFont(ofSize: 14, weight: .black), color: ink)
        drawRawText(L10n.text("團隊戰報"), x: margin, y: 47, width: pageBounds.width - margin * 2,
                    height: 40, font: .systemFont(ofSize: 28, weight: .black), color: ink)
        drawRawText(group.name, x: margin, y: 91, width: pageBounds.width - margin * 2,
                    height: 20, font: .systemFont(ofSize: 12, weight: .bold), color: ink)

        let footer = L10n.format("{0}  ·  匯出於 {1}", String(describing: group.name), String(describing: Date.now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))))
        drawRawText(footer, x: margin, y: pageBounds.height - 30, width: pageBounds.width - margin * 2,
                    font: .systemFont(ofSize: 9, weight: .medium), color: secondary)
        cursorY = 138
    }

    func drawSectionTitle(_ title: String) {
        ensureSpace(54)
        let rect = CGRect(x: margin, y: cursorY, width: pageBounds.width - margin * 2, height: 36)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        yellow.setFill()
        path.fill()
        drawRawText(title, x: rect.minX + 14, y: rect.minY + 8, width: rect.width - 28,
                    font: .systemFont(ofSize: 16, weight: .black), color: ink)
        cursorY = rect.maxY + 12
    }

    func drawSubheading(_ title: String) {
        ensureSpace(32)
        drawRawText(title, x: margin, y: cursorY, width: pageBounds.width - margin * 2,
                    font: .systemFont(ofSize: 14, weight: .black), color: ink)
        cursorY += 28
    }

    func drawMetric(title: String, score: Int?) {
        ensureSpace(34)
        let availableWidth = pageBounds.width - margin * 2
        drawRawText(title, x: margin, y: cursorY, width: 120,
                    font: .systemFont(ofSize: 12, weight: .bold), color: ink)
        drawRawText(score.map { "\($0)" } ?? L10n.text("尚未分析"), x: pageBounds.width - margin - 80, y: cursorY,
                    width: 80, font: .monospacedDigitSystemFont(ofSize: 12, weight: .black), color: ink,
                    alignment: .right)

        let barX = margin + 126
        let barWidth = availableWidth - 216
        let barRect = CGRect(x: barX, y: cursorY + 5, width: barWidth, height: 8)
        rule.setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 4).fill()
        if let score {
            yellow.setFill()
            UIBezierPath(
                roundedRect: CGRect(x: barX, y: cursorY + 5, width: barWidth * CGFloat(min(max(score, 0), 100)) / 100, height: 8),
                cornerRadius: 4
            ).fill()
        }
        cursorY += 28
    }

    func drawBody(_ text: String) {
        let font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        let width = pageBounds.width - margin * 2
        let height = measuredHeight(text, width: width, font: font, lineSpacing: 3)
        ensureSpace(height + 14)
        drawRawText(text, x: margin, y: cursorY, width: width, height: height,
                    font: font, color: secondary, lineSpacing: 3)
        cursorY += height + 14
    }

    func drawTask(_ task: ProjectTask) {
        let deadline = task.deadline == .distantFuture
            ? L10n.text("未設定期限")
            : task.deadline.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))
        let detail = "\(task.status.title) · \(task.progress)% · \(deadline)"
        let titleFont = UIFont.systemFont(ofSize: 12.5, weight: .bold)
        let detailFont = UIFont.systemFont(ofSize: 10.5, weight: .medium)
        let width = pageBounds.width - margin * 2 - 20
        let titleHeight = measuredHeight(task.title, width: width, font: titleFont, lineSpacing: 1)
        ensureSpace(titleHeight + 35)

        yellow.setFill()
        context.cgContext.fillEllipse(in: CGRect(x: margin, y: cursorY + 3, width: 8, height: 8))
        drawRawText(task.title, x: margin + 18, y: cursorY, width: width, height: titleHeight,
                    font: titleFont, color: ink)
        cursorY += titleHeight + 3
        drawRawText(detail, x: margin + 18, y: cursorY, width: width,
                    font: detailFont, color: secondary)
        cursorY += 25
    }

    func drawMemberContribution(member: Member, role: MemberRole, tasks: [ProjectTask]) {
        let completedTasks = tasks.filter { $0.progress >= 100 }.count
        let totalSubtasks = tasks.reduce(0) { $0 + $1.subtasks.count }
        let completedSubtasks = tasks.reduce(0) { total, task in
            total + task.subtasks.filter(\.isComplete).count
        }
        let submittedDeliverables = tasks.compactMap(\.deliverable)
        let approvedDeliverables = submittedDeliverables.filter(\.isApproved).count
        let overdueIncompleteTasks = tasks.filter {
            $0.deadline != .distantFuture && $0.deadline < .now && $0.progress < 100
        }.count
        let averageProgress = tasks.isEmpty
            ? 0
            : tasks.reduce(0) { $0 + $1.progress } / tasks.count

        ensureSpace(92)
        let headerRect = CGRect(x: margin, y: cursorY, width: pageBounds.width - margin * 2, height: 34)
        UIColor(red: 1, green: 0.93, blue: 0.62, alpha: 1).setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 10).fill()
        drawRawText(member.name, x: headerRect.minX + 12, y: headerRect.minY + 8,
                    width: headerRect.width - 120, font: .systemFont(ofSize: 14, weight: .black), color: ink)
        drawRawText(role.title, x: headerRect.maxX - 100, y: headerRect.minY + 8,
                    width: 88, font: .systemFont(ofSize: 11, weight: .bold), color: secondary,
                    alignment: .right)
        cursorY = headerRect.maxY + 9

        if tasks.isEmpty {
            drawBody(L10n.text("目前沒有指派給此成員的任務紀錄。"))
            return
        }

        let summary = [
            L10n.format("負責任務 {0} 項，完成 {1} 項，平均進度 {2}%", String(describing: tasks.count), String(describing: completedTasks), String(describing: averageProgress)),
            L10n.format("子任務完成 {0} / {1} 項", String(describing: completedSubtasks), String(describing: totalSubtasks)),
            L10n.format("成果已交付 {0} 項，其中驗收 {1} 項", String(describing: submittedDeliverables.count), String(describing: approvedDeliverables)),
            L10n.format("期限已過且尚未完成 {0} 項", String(describing: overdueIncompleteTasks))
        ].joined(separator: "\n")
        drawBody(summary)

        for task in tasks.sorted(by: { $0.deadline < $1.deadline }) {
            drawTask(task)
        }
    }

    private func ensureSpace(_ requiredHeight: CGFloat) {
        if cursorY + requiredHeight > pageBounds.height - footerHeight {
            beginPage()
        }
    }

    private func measuredHeight(
        _ text: String,
        width: CGFloat,
        font: UIFont,
        lineSpacing: CGFloat
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
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = alignment
        (text as NSString).draw(
            with: CGRect(x: x, y: y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
            context: nil
        )
    }
}
