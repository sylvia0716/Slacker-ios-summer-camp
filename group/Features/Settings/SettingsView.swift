import SwiftUI

/// Third tab: links to AI analysis, peer-review reports, and general preferences.
struct SettingsView: View {
    let model: GroupBombModel

    var body: some View {
        List {
            Section("報告") {
                NavigationLink { AIAnalysisReportView(model: model) } label: {
                    Label("AI 分析報告", systemImage: "sparkles")
                }
                NavigationLink { PeerReviewReportView(model: model) } label: {
                    Label("組員互評報告", systemImage: "scope")
                }
            }
            Section("一般") {
                Label("通知設定", systemImage: "bell")
                Label("帳號與個人資料", systemImage: "person.crop.circle")
            }
        }
        .navigationTitle("設定")
    }
}

/// Mock AI report for the MVP; replace its copy with service output in a later iteration.
private struct AIAnalysisReportView: View {
    let model: GroupBombModel

    var body: some View {
        List {
            Section("本週狀態") {
                Label("團隊目前完成 \(model.teamProgress)%", systemImage: "chart.bar.fill")
                Label("米米的進度需要關注", systemImage: "exclamationmark.triangle.fill")
            }
            Section("建議") {
                Text("先確認資料分析的交付時間，再安排簡報統整。")
            }
        }
        .navigationTitle("AI 分析")
    }
}
