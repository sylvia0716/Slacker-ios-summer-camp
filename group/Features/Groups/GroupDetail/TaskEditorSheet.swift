import SwiftUI

private struct TaskEditSubtaskDraft: Identifiable {
    let id: UUID
    var title: String
    let isComplete: Bool
}

/// Owner-only editor for an existing task. Identity and completion are preserved for retained subtasks.
struct TaskEditorSheet: View {
    let group: Group
    let task: ProjectTask
    let onSave: (String, String, [Subtask], Date) async throws -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var detail: String
    @State private var subtaskDrafts: [TaskEditSubtaskDraft]
    @State private var deadline: Date
    @State private var submissionError: String?
    @State private var isSaving = false
    @State private var confirmsDiscard = false

    init(
        group: Group,
        task: ProjectTask,
        onSave: @escaping (String, String, [Subtask], Date) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.group = group
        self.task = task
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: task.title)
        _detail = State(initialValue: task.detail)
        _subtaskDrafts = State(initialValue: task.subtasks.map {
            TaskEditSubtaskDraft(id: $0.id, title: $0.title, isComplete: $0.isComplete)
        })
        _deadline = State(initialValue: task.deadline)
    }

    var body: some View {
        BombFormSheet(title: L10n.text("修改任務"), showsHandle: true) {
            taskFields
                .disabled(isSaving)
            subtaskFields
                .disabled(isSaving)
            deadlinePicker
                .disabled(isSaving)

            if let submissionError {
                Text(submissionError)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            BombFormActions(
                primaryTitle: isSaving ? L10n.text("儲存中…") : L10n.text("儲存修改"),
                isEnabled: canSave,
                isBusy: isSaving,
                onPrimary: save,
                onSecondary: requestCancel
            )
        }
        .background(BombTheme.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(BombTheme.ink, lineWidth: 3)
        }
        .shadow(color: BombTheme.ink.opacity(0.3), radius: 14, y: 4)
        .bombDialog(L10n.text("捨棄未儲存的內容？"), isPresented: $confirmsDiscard, destructiveIsRed: true) {
            Button(L10n.text("繼續編輯"), role: .cancel) { }
            Button(L10n.text("捨棄"), role: .destructive, action: onCancel)
        }
    }

    private var taskFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(L10n.text("任務名稱"), isRequired: true)
                TextField(L10n.text("例如「製作競品分析」"), text: $title)
                    .textInputAutocapitalization(.never)
                    .bombFormField()
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(L10n.text("任務說明"), isRequired: false)
                TextField(L10n.text("例如「整理三個競品的功能與差異」"), text: $detail, axis: .vertical)
                    .lineLimit(2...4)
                    .bombFormField()
            }
        }
    }

    private var subtaskFields: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                fieldLabel(L10n.text("子任務"), isRequired: true)
                Spacer()
                Text("\(subtaskDrafts.count) / 10")
                    .font(.footnote.monospacedDigit().weight(.bold))
                    .foregroundStyle(BombTheme.secondaryText)
            }

            ForEach($subtaskDrafts) { $draft in
                HStack(spacing: 9) {
                    TextField(L10n.text("例如「整理簡報架構」"), text: $draft.title)
                        .textInputAutocapitalization(.never)
                        .bombFormField()

                    if subtaskDrafts.count > 1 {
                        Button {
                            subtaskDrafts.removeAll { $0.id == draft.id }
                        } label: {
                            Image(systemName: "minus")
                                .font(.subheadline.weight(.black))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(BombTheme.paper)
                                .background(BombTheme.red)
                                .clipShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("刪除子任務"))
                    }
                }
            }

            if subtaskDrafts.count < 10 {
                Button {
                    subtaskDrafts.append(TaskEditSubtaskDraft(id: UUID(), title: "", isComplete: false))
                } label: {
                    Label(L10n.text("新增子任務"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.black))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BombTheme.ink)
            }

            Text(L10n.text("保留的子任務會維持目前完成狀態"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BombTheme.secondaryText)
        }
    }

    private var deadlinePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(L10n.text("截止時間"), isRequired: true)
            DatePicker(
                L10n.text("選擇日期與時間"),
                selection: $deadline,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .bombFormField()

            if let deadlineError {
                Text(deadlineError)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDrafts: [TaskEditSubtaskDraft] {
        subtaskDrafts.map {
            TaskEditSubtaskDraft(
                id: $0.id,
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                isComplete: $0.isComplete
            )
        }
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty
            && !trimmedDrafts.isEmpty
            && !trimmedDrafts.contains { $0.title.isEmpty }
            && deadlineError == nil
    }

    private var deadlineError: String? {
        if group.deadline <= Date.now {
            return L10n.text("群組已截止，請先延長群組期限再修改任務。")
        }
        if deadline <= Date.now {
            return L10n.text("截止時間已過，請選擇未來時間後儲存。")
        }
        if deadline > group.deadline {
            return L10n.text("截止時間不可晚於群組總截止時間")
        }
        return nil
    }

    private func requestCancel() {
        guard !isSaving else { return }
        let sameSubtasks = subtaskDrafts.count == task.subtasks.count
            && zip(subtaskDrafts, task.subtasks).allSatisfy { draft, original in
                draft.id == original.id && draft.title == original.title
            }
        let hasChanges = title != task.title || detail != task.detail
            || deadline != task.deadline || !sameSubtasks
        if hasChanges {
            confirmsDiscard = true
        } else {
            onCancel()
        }
    }

    private func fieldLabel(_ title: String, isRequired: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if isRequired {
                Text("＊")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }
        }
        .font(.subheadline.weight(.black))
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        submissionError = nil
        let subtasks = trimmedDrafts.map {
            Subtask(id: $0.id, title: $0.title, isComplete: $0.isComplete, weight: 1)
        }
        Task {
            do {
                try await onSave(trimmedTitle, detail, subtasks, deadline)
                onCancel()
            } catch {
                submissionError = error.localizedDescription
                isSaving = false
            }
        }
    }
}
