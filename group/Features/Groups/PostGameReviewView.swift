import Foundation
import SwiftUI

/// 已結案專案的遊戲化成果報告；MVP 內容使用本檔案內的展示資料。
struct PostGameReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let groupName: String

    @State private var showsPlaceholderAlert = false
    private let demo = PostGameReviewDemo.maic

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("📋 任務結案報告")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)

                    projectResultCard
                    contributionCard
                    peerReviewCard
                    teamRetrospectiveCard
                    exportActions
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: "賽後回顧", subtitle: groupName) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel("返回群組")
            } trailing: {
                EmptyView()
            }
        }
        .alert("功能開發中", isPresented: $showsPlaceholderAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("此功能將於正式版本推出，目前 MVP 僅展示任務結案報告。")
        }
    }

    private var projectResultCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(BombTheme.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(groupName)
                        .font(.system(.title2, design: .rounded, weight: .black))
                    Text("成功拆彈")
                        .font(.headline.weight(.black))
                        .foregroundStyle(BombTheme.green)
                }

                Spacer(minLength: 0)

                Text("100%")
                    .font(.system(.title, design: .rounded, weight: .black))
            }

            HStack(spacing: 10) {
                resultMetric(title: "完成率", value: "\(demo.completionRate)%")
                resultMetric(title: "完成任務", value: "\(demo.completedTasks) / \(demo.totalTasks)")
                resultMetric(title: "團隊", value: "\(demo.teamSize) 位特工")
            }
        }
        .postGameCard()
    }

    private func resultMetric(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.black))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(BombTheme.yellow.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("👥 小組分工")

            ForEach(Array(demo.contributions.enumerated()), id: \.element.id) { index, member in
                contributionRow(member)

                if index < demo.contributions.count - 1 {
                    Divider().overlay(BombTheme.ink.opacity(0.35))
                }
            }
        }
        .postGameCard()
    }

    private func contributionRow(_ member: MemberContribution) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(BombTheme.ink)
                Image(systemName: "person.fill")
                    .foregroundStyle(BombTheme.yellow)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name).font(.headline.weight(.black))
                    Spacer()
                    Text(member.completion)
                        .font(.caption.weight(.black))
                        .foregroundStyle(BombTheme.green)
                }

                Text(member.role)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Text(member.responsibility)
                    .font(.subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var peerReviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("⭐ 隊員互評")

            Text("匿名平均分")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            ForEach(demo.reviewScores) { review in
                VStack(spacing: 7) {
                    HStack {
                        Text(review.name).font(.subheadline.weight(.black))
                        Spacer()
                        Text(String(format: "%.1f / 5", review.score))
                            .font(.subheadline.weight(.black))
                    }

                    ProgressView(value: review.score, total: 5)
                        .tint(BombTheme.yellow)
                        .scaleEffect(y: 1.45)
                }
            }
        }
        .postGameCard()
    }

    private var teamRetrospectiveCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("🤖 Bomb AI 團隊復盤")

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .lastTextBaseline) {
                    Text("合作指數")
                        .font(.headline.weight(.black))
                    Spacer()
                    Text("\(demo.collaborationIndex) / 100")
                        .font(.system(.title2, design: .rounded, weight: .black))
                }

                ProgressView(value: Double(demo.collaborationIndex), total: 100)
                    .tint(BombTheme.green)
                    .scaleEffect(y: 1.6)
            }
            .padding(12)
            .background(BombTheme.yellow.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            retrospectiveList(title: "團隊亮點", items: demo.highlights, marker: "✓")
            retrospectiveList(title: "改善建議", items: demo.improvements, marker: "•")

            VStack(alignment: .leading, spacing: 7) {
                Text("AI 總評").font(.headline.weight(.black))
                Text("「\(demo.summary)」")
                    .font(.subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(Color.white.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))

            Text("AI 分析僅供參考。")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .postGameCard()
    }

    private func retrospectiveList(title: String, items: [String], marker: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline.weight(.black))
            ForEach(items, id: \.self) { item in
                Text("\(marker) \(item)")
                    .font(.subheadline.weight(.bold))
            }
        }
    }

    private var exportActions: some View {
        VStack(spacing: 10) {
            placeholderButton("儲存圖片", systemImage: "photo.fill")
            placeholderButton("匯出 PDF", systemImage: "doc.fill")
            placeholderButton("分享", systemImage: "square.and.arrow.up")
        }
        .padding(.top, 2)
    }

    private func placeholderButton(_ title: String, systemImage: String) -> some View {
        Button {
            showsPlaceholderAlert = true
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BombTheme.ink)
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title2, design: .rounded, weight: .black))
    }
}

private struct PostGameCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(17)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
            .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)
    }
}

private extension View {
    func postGameCard() -> some View {
        modifier(PostGameCardModifier())
    }
}

private struct PostGameReviewDemo {
    let completionRate: Int
    let completedTasks: Int
    let totalTasks: Int
    let teamSize: Int
    let contributions: [MemberContribution]
    let reviewScores: [MemberReviewScore]
    let collaborationIndex: Int
    let highlights: [String]
    let improvements: [String]
    let summary: String

    static let maic = PostGameReviewDemo(
        completionRate: 100,
        completedTasks: 12,
        totalTasks: 12,
        teamSize: 4,
        contributions: [
            MemberContribution(name: "我", role: "組長", responsibility: "任務分配、簡報整合", completion: "2 / 2"),
            MemberContribution(name: "小宇", role: "資料分析", responsibility: "市場分析、競品分析", completion: "4 / 4"),
            MemberContribution(name: "米米", role: "簡報設計", responsibility: "視覺統整、圖表排版", completion: "3 / 3"),
            MemberContribution(name: "Peach", role: "市場研究", responsibility: "問卷整理、資料蒐集", completion: "3 / 3")
        ],
        reviewScores: [
            MemberReviewScore(name: "我", score: 4.5),
            MemberReviewScore(name: "小宇", score: 4.8),
            MemberReviewScore(name: "米米", score: 4.3),
            MemberReviewScore(name: "Peach", score: 4.9)
        ],
        collaborationIndex: 92,
        highlights: ["分工明確", "成員皆完成負責任務", "成果皆有提交"],
        improvements: ["更早確認簡報架構", "增加中期進度檢查", "避免最後一天集中整合"],
        summary: "本次團隊合作良好，任務分工清楚，所有成員皆完成主要負責工作。若能增加中期檢查，整體效率會更穩定。"
    )
}

private struct MemberContribution: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let responsibility: String
    let completion: String
}

private struct MemberReviewScore: Identifiable {
    let id = UUID()
    let name: String
    let score: Double
}

#Preview("Post Game Review") {
    NavigationStack {
        PostGameReviewView(groupName: "MAIC 比賽")
    }
}
