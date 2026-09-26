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
        _deadline = State(initialValue: max(Date.now, min(task.deadline, group.deadline)))
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(BombTheme.ink.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("修改任務"))
                        .font(.system(.title2, design: .rounded, weight: .black))

                    taskFields
                    subtaskFields
                    deadlinePicker

                    if let submissionError {
                        Text(submissionError)
                            .font(.caption.weight(.black))
                            .foregroundStyle(BombTheme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            actionBar
        }
        .background(BombTheme.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(BombTheme.ink, lineWidth: 3)
        }
        .shadow(color: BombTheme.ink.opacity(0.3), radius: 14, y: 4)
    }

    private var taskFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(L10n.text("任務名稱"), isRequired: true)
                TextField(L10n.text("例如「製作競品分析」"), text: $title)
                    .textInputAutocapitalization(.never)
                    .taskEditInputStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(L10n.text("任務說明"), isRequired: false)
                TextField(L10n.text("例如「整理三個競品的功能與差異」"), text: $detail, axis: .vertical)
                    .lineLimit(2...4)
                    .taskEditInputStyle()
            }
        }
    }

    private var subtaskFields: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                fieldLabel(L10n.text("子任務"), isRequired: true)
                Spacer()
                Text("\(subtaskDrafts.count) / 10")
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(BombTheme.ink.opacity(0.5))
            }

            ForEach($subtaskDrafts) { $draft in
                HStack(spacing: 9) {
                    TextField(L10n.text("例如「整理簡報架構」"), text: $draft.title)
                        .textInputAutocapitalization(.never)
                        .taskEditInputStyle()

                    if subtaskDrafts.count > 1 {
                        Button {
                            subtaskDrafts.removeAll { $0.id == draft.id }
                        } label: {
                            Image(systemName: "minus")
                                .font(.subheadline.weight(.black))
                                .frame(width: 38, height: 38)
                                .foregroundStyle(.white)
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
                .font(.caption2.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.55))
        }
    }

    private var deadlinePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(L10n.text("截止時間"), isRequired: true)
            DatePicker(
                L10n.text("選擇日期與時間"),
                selection: $deadline,
                in: Date.now...max(Date.now, group.deadline),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.subheadline.weight(.bold))
            .tint(BombTheme.ink)
            .padding(12)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BombTheme.ink, lineWidth: 2)
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button(action: save) {
                Text(isSaving ? L10n.text("儲存中…") : L10n.text("儲存修改"))
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
            .opacity(canSave && !isSaving ? 1 : 0.42)

            Button(L10n.text("取消"), action: onCancel)
                .font(.subheadline.weight(.black))
                .foregroundStyle(BombTheme.ink)
                .buttonStyle(.plain)
                .padding(.vertical, 5)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .safeAreaPadding(.bottom, 8)
        .background(BombTheme.yellow)
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
            && deadline > Date.now
            && deadline <= group.deadline
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

private extension View {
    func taskEditInputStyle() -> some View {
        font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(BombTheme.ink, lineWidth: 2)
            }
    }
}
