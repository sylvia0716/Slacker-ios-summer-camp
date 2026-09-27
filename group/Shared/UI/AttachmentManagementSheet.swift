import SwiftUI

struct AttachmentManagementSheet: View {
    let model: GroupBombModel
    let task: ProjectTask
    let onSubmit: (Deliverable) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String?
    @State private var title = ""
    @State private var detail = ""
    @State private var deletion: TaskAttachment?
    @State private var replacement: TaskAttachment?
    @State private var showsUpload = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var attachments: [TaskAttachment] {
        (model.attachmentsByTaskID[task.id] ?? []).filter { $0.status == .ready }
    }

    var body: some View {
        BombFormSheet(title: L10n.text("編輯附件")) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(attachments) { attachment in
                    VStack(alignment: .leading, spacing: 12) {
                        AttachmentActionButton(model: model, taskID: task.id, deliverable: Deliverable(attachment: attachment)) {
                            AttachmentSummaryRow(model: model, taskID: task.id,
                                                 deliverable: Deliverable(attachment: attachment))
                        }
                        HStack(spacing: 16) {
                            Spacer()
                            Button {
                                editingID = attachment.id
                                title = attachment.title
                                detail = attachment.detail
                            } label: {
                                Image(systemName: "pencil").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(L10n.text("編輯附件"))
                            Button { deletion = attachment } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(BombTheme.red)
                            }
                            .accessibilityLabel(L10n.text("刪除附件"))
                        }
                        .buttonStyle(.plain)
                        if editingID == attachment.id {
                            TextField(L10n.text("成果標題"), text: $title)
                                .bombFormField()
                            TextField(L10n.text("成果說明"), text: $detail, axis: .vertical)
                                .lineLimit(3...6)
                                .bombFormField()
                            Button(L10n.text("儲存變更")) { save(attachment) }
                                .buttonStyle(BombFormPrimaryButtonStyle())
                                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 100 || detail.count > 1000)
                            Button(L10n.text("替換檔案")) {
                                replacement = attachment
                                showsUpload = true
                            }
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Capsule())
                            .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                            .buttonStyle(.plain)
                        }
                    }
                }
                if isWorking { ProgressView().frame(maxWidth: .infinity) }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(BombTheme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(isWorking)
        } actions: {
            BombFormActions(
                primaryTitle: L10n.text("新增附件"),
                isBusy: isWorking,
                secondaryTitle: L10n.text("完成"),
                onPrimary: {
                    replacement = nil
                    showsUpload = true
                },
                onSecondary: { dismiss() }
            )
        }
        .sheet(isPresented: $showsUpload) {
            DeliverableSubmissionSheet(task: task,
                initialTitle: replacement == nil ? "" : title,
                initialDetail: replacement == nil ? "" : detail) { deliverable in
                onSubmit(deliverable)
                if let old = replacement {
                    replacement = nil
                    remove(old, replacing: true)
                }
            }
        }
        .bombDialog(L10n.text("確定刪除此附件？"), isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }
        )) {
            Button(L10n.text("取消"), role: .cancel) { deletion = nil }
            Button(L10n.text("刪除"), role: .destructive) {
                if let deletion { remove(deletion) }
                deletion = nil
            }
        } message: { Text(L10n.text("刪除後無法復原。")) }
        .interactiveDismissDisabled(isWorking)
    }

    private func save(_ attachment: TaskAttachment) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await model.editAttachment(attachment, title: title, detail: detail, taskID: task.id)
                editingID = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func remove(_ attachment: TaskAttachment, replacing: Bool = false) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do { try await model.deleteAttachment(attachment, taskID: task.id) }
            catch {
                errorMessage = replacing
                    ? L10n.text("新檔已上傳，舊附件未刪除，請重新刪除舊附件。")
                    : error.localizedDescription
            }
        }
    }
}
