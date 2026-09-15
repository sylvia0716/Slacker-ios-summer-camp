import SwiftUI
import QuickLook

/// Reuses the existing result label; adds interactions without changing its layout.
struct AttachmentActionButton<Label: View>: View {
    let model: GroupBombModel
    let taskID: UUID
    let deliverable: Deliverable
    var localPreview: (() -> Void)? = nil
    @ViewBuilder let label: () -> Label
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var action = AttachmentActionStore()
    @State private var confirmsDelete = false

    private var attachment: TaskAttachment? {
        model.attachmentsByTaskID[taskID]?.first { $0.id == deliverable.attachmentID }
    }

    var body: some View {
        Button {
            if deliverable.attachmentID == nil { localPreview?() }
            else { perform(delete: false) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(action.isWorking)
        .contextMenu {
            if attachment != nil {
                Button("刪除附件", role: .destructive) { confirmsDelete = true }
                    .disabled(action.isWorking)
            }
        }
        .confirmationDialog("確定刪除此附件？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("刪除", role: .destructive) { perform(delete: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("刪除後無法復原。")
        }
        .overlay {
            if action.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(action.isDeleting ? "正在刪除" : "下載中 \(Int(action.progress * 100))%")
                        .font(.caption.bold())
                }
                .padding(8)
                .background(BombTheme.yellow, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(BombTheme.ink)
                .accessibilityElement(children: .combine)
            }
        }
        .quickLookPreview($action.previewURL)
        .onChange(of: action.previewURL) { _, value in
            if value == nil { action.clearPreview() }
        }
        .onChange(of: action.externalURL) { _, url in
            if let url {
                openURL(url) { accepted in
                    if !accepted { action.errorMessage = "無法開啟此網址，請稍後重試。" }
                }
                action.externalURL = nil
            }
        }
        .alert("附件操作失敗", isPresented: Binding(get: { action.errorMessage != nil }, set: { if !$0 { action.errorMessage = nil } })) {
            Button("重新嘗試") { perform(delete: action.isDeleting) }
            Button("取消", role: .cancel) { action.errorMessage = nil }
        } message: { Text(action.errorMessage ?? "") }
        .onChange(of: model.firebaseUID) { _, _ in action.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { action.cancel() } }
        .onDisappear { action.cancel() }
    }

    private func perform(delete: Bool) {
        guard model.firebaseUID != nil else {
            action.errorMessage = AttachmentOperationError.signedOut.localizedDescription
            return
        }
        guard let attachment else {
            action.errorMessage = "附件資料尚未載入或已移除，請重新整理後再試。"
            return
        }
        action.run(delete: delete, attachment: attachment,
                   download: { item, progress in try await model.downloadAttachment(item, progress: progress) },
                   remove: { item in try await model.deleteAttachment(item, taskID: taskID) })
    }
}
