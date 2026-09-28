import SwiftUI

/// Both surfaces share the same cloud request model; the server controls report access.
struct CloudJoinRequestsView: View {
    let model: AppStore
    var groupID: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CloudJoinRequestStore()
    @State private var reviewing: CloudJoinRequest?
    @State private var decisionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.requests.contains(where: { groupID == nil || $0.status == "pending" }) {
                Text(L10n.text(groupID == nil ? "我的入群申請" : "入群審核"))
                    .font(.title2.bold())
                ForEach(store.requests.filter { groupID == nil || $0.status == "pending" }) { request in
                    if groupID == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.groupName).font(.headline)
                            Text(request.statusText).font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .comicCard()
                    } else {
                        Button { reviewing = request } label: {
                            HStack {
                                Text(L10n.format("{0} 想加入群組", request.displayName))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.headline)
                            .foregroundStyle(BombTheme.ink)
                            .comicCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let message = store.errorMessage {
                Button { Task { await store.refresh(groupID: groupID) } } label: {
                    Label(message, systemImage: "arrow.clockwise").font(.footnote)
                }
            }
        }
        .task(id: "\(model.firebaseUID ?? "")/\(groupID ?? "")/\(scenePhase == .active)") {
            guard scenePhase == .active, !model.isDemoMode, model.firebaseUID != nil else {
                store.reset()
                return
            }
            var refreshedApprovals: Set<String> = []
            while !Task.isCancelled {
                await store.refresh(groupID: groupID)
                let approvals = Set(store.requests.filter { $0.status == "approved" }.map(\.version))
                if groupID == nil, !approvals.subtracting(refreshedApprovals).isEmpty {
                    if await model.reloadCloudGroups(reportError: false, forceRefresh: true) { refreshedApprovals = approvals }
                }
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .onChange(of: model.firebaseUID) { _, _ in
            store.reset()
            reviewing = nil
            decisionMessage = nil
        }
        .sheet(item: $reviewing) { request in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(request.displayName).font(.title.bold())
                        if let report = request.report, report.reviewCount > 0 {
                            Text(L10n.format("{0} 個專案 · {1} 份隊友互評", String(report.projectCount), String(report.reviewCount)))
                            score("任務完成", report.taskCompletionScore)
                            score("討論參與", report.discussionScore)
                            score("主動協助", report.collaborationScore)
                            score("解決問題", report.ideaScore)
                            score("準時可靠", report.reliabilityScore)
                            Text(L10n.text("資料為申請時已完成專案的互評摘要。"))
                                .font(.footnote)
                        } else {
                            Text(L10n.text("尚無互評資料"))
                        }
                        if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
                        HStack {
                            Button(L10n.text("拒絕"), role: .destructive) { decide(request, approve: false) }
                            Spacer()
                            if store.busy { ProgressView() }
                            Button(L10n.text("核准加入")) { decide(request, approve: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.busy)
                    }
                    .padding(20)
                }
                .navigationTitle(L10n.text("入群審核"))
                .toolbar { Button(L10n.text("關閉")) { reviewing = nil } }
                .interactiveDismissDisabled(store.busy)
            }
        }
        .alert(L10n.text("審核結果"), isPresented: Binding(get: { decisionMessage != nil }, set: { if !$0 { decisionMessage = nil } })) {
            Button(L10n.text("知道了")) { decisionMessage = nil }
        } message: { Text(decisionMessage ?? "") }
    }

    private func score(_ title: String, _ value: Double?) -> some View {
        HStack {
            Text(L10n.text(title))
            Spacer()
            Text(value.map { String(format: "%.1f / 5", $0) } ?? "—")
        }
    }

    private func decide(_ request: CloudJoinRequest, approve: Bool) {
        Task {
            guard let status = await store.decide(request, approve: approve) else { return }
            reviewing = nil
            decisionMessage = L10n.text(status == "approved" ? "已核准加入" : status == "rejected" ? "申請已拒絕" : "申請已失效，未加入群組")
        }
    }
}
