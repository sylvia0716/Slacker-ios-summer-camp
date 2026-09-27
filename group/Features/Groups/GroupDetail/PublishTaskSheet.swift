import SwiftUI

private struct SubtaskDraft: Identifiable {
    let id = UUID()
    var title = ""
}

/// Focused task-publishing flow: choose who should do what, and by when.
struct PublishTaskSheet: View {
    let group: Group
    let members: [Member]
    let onPublish: (String, String, [String], UUID, Date) async throws -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var detail = ""
    @State private var subtaskDrafts = [SubtaskDraft()]
    @State private var selectedMemberID: UUID?
    @State private var deadline: Date
    @State private var initialDeadline: Date
    @State private var submissionError: String?
    @State private var isPublishing = false
    @State private var confirmsDiscard = false

    init(
        group: Group,
        members: [Member],
        onPublish: @escaping (String, String, [String], UUID, Date) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.group = group
        self.members = members
        self.onPublish = onPublish
        self.onCancel = onCancel

        let now = Date.now
        let preferredDeadline = now.addingTimeInterval(60 * 60)
        let initialDeadline = max(now, min(preferredDeadline, group.deadline))
        _deadline = State(initialValue: initialDeadline)
        _initialDeadline = State(initialValue: initialDeadline)
    }

    var body: some View {
        BombFormSheet(title: L10n.text("發布任務"), showsHandle: true) {
            taskFields
                .disabled(isPublishing)
            subtaskFields
                .disabled(isPublishing)
            assigneePicker
                .disabled(isPublishing)
            deadlinePicker
                .disabled(isPublishing)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            BombFormActions(
                primaryTitle: isPublishing ? L10n.text("發布中…") : L10n.text("發布任務"),
                isEnabled: canPublish,
                isBusy: isPublishing,
                onPrimary: publish,
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
                            removeSubtask(draft.id)
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
                    subtaskDrafts.append(SubtaskDraft())
                } label: {
                    Label(L10n.text("新增子任務"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.black))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BombTheme.ink)
            }

            Text(L10n.text("每項子任務會平均計入任務進度"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BombTheme.secondaryText)
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

    private var assigneePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(L10n.text("負責人"), isRequired: true)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(members) { member in
                        assigneeButton(for: member)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func assigneeButton(for member: Member) -> some View {
        let isSelected = selectedMemberID == member.id

        return Button {
            selectedMemberID = member.id
            submissionError = nil
        } label: {
            HStack(spacing: 9) {
                MemberPhotoAvatar(groupID: group.firestoreDocumentID, uid: member.firebaseUID, name: member.name, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.subheadline.weight(.black))
                    Text(member.role.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BombTheme.secondaryText)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline.weight(.black))
            }
            .foregroundStyle(BombTheme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isSelected ? BombTheme.yellow : BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BombTheme.ink, lineWidth: isSelected ? 4 : 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var deadlinePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(L10n.text("截止時間"), isRequired: true)

            DatePicker(
                L10n.text("選擇日期與時間"),
                selection: $deadline,
                in: allowedDeadlineRange,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .bombFormField()

            if let deadlineError {
                Text(deadlineError)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSubtaskTitles: [String] {
        subtaskDrafts.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var selectedMember: Member? {
        guard let selectedMemberID else { return nil }
        return members.first(where: { $0.id == selectedMemberID })
    }

    private var allowedDeadlineRange: ClosedRange<Date> {
        let now = Date.now
        return now...max(now, group.deadline)
    }

    private var deadlineError: String? {
        if deadline <= Date.now { return L10n.text("截止時間必須晚於目前時間") }
        if deadline > group.deadline { return L10n.text("截止時間不可晚於群組總截止時間") }
        return nil
    }

    private var errorMessage: String? {
        submissionError
    }

    private var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedSubtaskTitles.contains { $0.isEmpty }
            && selectedMember != nil
            && deadlineError == nil
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

    private func publish() {
        guard canPublish, !isPublishing, let selectedMemberID else { return }
        isPublishing = true
        submissionError = nil
        Task {
            do {
                try await onPublish(title, detail, trimmedSubtaskTitles, selectedMemberID, deadline)
                onCancel()
            } catch {
                submissionError = error.localizedDescription
                isPublishing = false
            }
        }
    }

    private func requestCancel() {
        guard !isPublishing else { return }
        let hasChanges = !title.isEmpty || !detail.isEmpty
            || selectedMemberID != nil || deadline != initialDeadline
            || subtaskDrafts.count != 1 || subtaskDrafts.contains { !$0.title.isEmpty }
        if hasChanges {
            confirmsDiscard = true
        } else {
            onCancel()
        }
    }

    private func removeSubtask(_ id: UUID) {
        guard subtaskDrafts.count > 1 else { return }
        subtaskDrafts.removeAll { $0.id == id }
    }
}
