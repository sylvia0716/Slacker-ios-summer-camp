import SwiftUI

struct GroupAdmissionInbox: View {
    let model: GroupBombModel
    var groupID: String? = nil
    @State private var selectedRequest: GroupJoinRequest?

    private var requests: [GroupJoinRequest] {
        model.admissions.incomingRequests.filter { groupID == nil || $0.groupID == groupID }
    }

    var body: some View {
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(L10n.text("待審核入群"))
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(requests.count, format: .number)
                        .font(.subheadline.weight(.black).monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(BombTheme.yellow, in: Capsule())
                        .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                }
                .foregroundStyle(BombTheme.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("待審核入群 · {0}", String(requests.count)))
                ForEach(requests) { request in
                    Button {
                        selectedRequest = request
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill").font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.applicantName)
                                    .font(.system(.headline, design: .rounded, weight: .black))
                                Text(request.groupName)
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                            }
                            Spacer()
                            Text(L10n.text("查看申請"))
                                .font(.system(.caption, design: .rounded, weight: .black))
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(BombTheme.ink)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .comicCard()
            .sheet(item: $selectedRequest) { request in
                GroupAdmissionReviewSheet(model: model, request: request)
            }
        }
    }
}

struct GroupAdmissionReviewSheet: View {
    let model: GroupBombModel
    let request: GroupJoinRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var projects: [PersonalPeerReviewProject] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var decisionError: String?
    @State private var confirmsRejection = false

    private var isPending: Bool {
        model.admissions.incomingRequests.contains { $0.requestID == request.requestID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("個人戰力檔案"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BombTheme.secondaryText)
                        Text(request.applicantName).font(.largeTitle.weight(.black))
                        Text(L10n.format("申請加入「{0}」", request.groupName))
                            .font(.subheadline)
                            .foregroundStyle(BombTheme.secondaryText)
                    }
                    Divider()
                    if !isPending {
                        ContentUnavailableView(L10n.text("此申請已更新"), systemImage: "checkmark.circle")
                    } else if isLoading {
                        ProgressView(L10n.text("載入戰力檔案…")).frame(maxWidth: .infinity)
                    } else if let loadError {
                        Text(loadError).foregroundStyle(BombTheme.red)
                        Button(L10n.text("重試")) { Task { await loadProfile() } }
                            .buttonStyle(AdmissionDecisionButtonStyle(isPrimary: true))
                    } else {
                        ApplicantBattleProfileView(projects: projects)
                    }
                    if let decisionError {
                        Text(decisionError).font(.footnote).foregroundStyle(BombTheme.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .comicCard()
                .padding(20)
            }
            .background(BombTheme.yellow)
            .navigationTitle(L10n.text("入群審核"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text(L10n.text("關閉"))
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .foregroundStyle(BombTheme.ink)
                            .background(BombTheme.paper, in: Capsule())
                            .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isPending { reviewActions }
            }
            .bombDialog(L10n.text("拒絕這份入群申請？"), isPresented: $confirmsRejection) {
                Button(L10n.text("返回查看"), role: .cancel) { }
                Button(L10n.text("確認拒絕"), role: .destructive) { decide(approve: false) }
            } message: {
                Text(L10n.text("拒絕後，對方可在 App 內查看未通過結果，並可重新申請。"))
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task { await loadProfile() }
        .onChange(of: isPending) { _, pending in
            if !pending { projects = [] }
        }
    }

    private var reviewActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            Button { confirmsRejection = true } label: {
                Label(L10n.text("拒絕申請"), systemImage: "xmark")
            }
            .buttonStyle(AdmissionDecisionButtonStyle(isPrimary: false))

            Button { decide(approve: true) } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(BombTheme.paper)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(L10n.text("核准加入"))
                }
            }
            .buttonStyle(AdmissionDecisionButtonStyle(isPrimary: true))
        }
        .disabled(isSaving || isLoading || loadError != nil)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            BombTheme.yellow.ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(BombTheme.ink.opacity(0.18)).frame(height: 1)
        }
    }

    private func loadProfile() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let loaded = try await model.admissions.profile(for: request)
            guard !Task.isCancelled, isPending else { return }
            projects = loaded
        } catch {
            loadError = L10n.text("無法載入戰力檔案，請重試。")
        }
    }

    private func decide(approve: Bool) {
        guard !isSaving, isPending else { return }
        isSaving = true
        decisionError = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.admissions.review(request, approve: approve)
                dismiss()
            } catch GroupJoinError.applicantProjectLimit {
                decisionError = GroupJoinError.applicantProjectLimit.localizedDescription
            } catch {
                decisionError = L10n.text("審核未完成，申請或群組狀態可能已變更，請重新整理後重試。")
            }
        }
    }
}

private struct AdmissionDecisionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .black))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(isPrimary ? BombTheme.paper : BombTheme.red)
            .background {
                // Draw the offset backing separately so text and symbols never cast a shadow.
                ZStack {
                    Capsule()
                        .fill(BombTheme.ink)
                        .offset(y: configuration.isPressed ? 0 : 3)
                    Capsule()
                        .fill(isPrimary ? BombTheme.ink : BombTheme.paper)
                        .overlay {
                            Capsule()
                                .strokeBorder(BombTheme.ink, lineWidth: 2.5)
                        }
                }
            }
            .offset(y: configuration.isPressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
