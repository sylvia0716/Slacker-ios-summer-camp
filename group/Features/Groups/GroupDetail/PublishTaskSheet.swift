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
    @State private var submissionError: String?
    @State private var isPublishing = false

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
                    Text("發布任務")
                        .font(.system(.title2, design: .rounded, weight: .black))

                    taskFields
                    subtaskFields
                    assigneePicker
                    deadlinePicker
                    publishSummary

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.black))
                            .foregroundStyle(BombTheme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)

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

    private var subtaskFields: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                fieldLabel("子任務", isRequired: true)
                Spacer()
                Text("\(subtaskDrafts.count) / 10")
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(BombTheme.ink.opacity(0.5))
            }

            ForEach($subtaskDrafts) { $draft in
                HStack(spacing: 9) {
                    TextField("例如「整理簡報架構」", text: $draft.title)
                        .textInputAutocapitalization(.never)
                        .inputFieldStyle()

                    if subtaskDrafts.count > 1 {
                        Button {
                            removeSubtask(draft.id)
                        } label: {
                            Image(systemName: "minus")
                                .font(.subheadline.weight(.black))
                                .frame(width: 38, height: 38)
                                .foregroundStyle(.white)
                                .background(BombTheme.red)
                                .clipShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("刪除子任務")
                    }
                }
            }

            if subtaskDrafts.count < 10 {
                Button {
                    subtaskDrafts.append(SubtaskDraft())
                } label: {
                    Label("新增子任務", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.black))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BombTheme.ink)
            }

            Text("每項子任務會平均計入任務進度")
                .font(.caption2.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.55))
        }
    }

    private var taskFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("任務名稱", isRequired: true)
                TextField("例如「製作競品分析」", text: $title)
                    .textInputAutocapitalization(.never)
                    .inputFieldStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("任務說明", isRequired: false)
                TextField("例如「整理三個競品的功能與差異」", text: $detail, axis: .vertical)
                    .lineLimit(2...4)
                    .inputFieldStyle()
            }
        }
    }

    private var assigneePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("負責人", isRequired: true)

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
                ZStack {
                    Circle().fill(BombTheme.ink)
                    Image(systemName: member.avatarSymbol)
                        .font(.caption.weight(.black))
                        .foregroundStyle(BombTheme.yellow)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.subheadline.weight(.black))
                    Text(member.role.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BombTheme.ink.opacity(0.6))
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline.weight(.black))
            }
            .foregroundStyle(BombTheme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isSelected ? BombTheme.paper : BombTheme.paper.opacity(0.65))
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
            fieldLabel("截止時間", isRequired: true)

            DatePicker(
                "選擇日期與時間",
                selection: $deadline,
                in: allowedDeadlineRange,
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

            if let deadlineError {
                Text(deadlineError)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }
        }
    }

    private var publishSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("發布摘要")
                .font(.subheadline.weight(.black))
            summaryRow(label: "任務", value: trimmedTitle.isEmpty ? "尚未填寫" : trimmedTitle)
            summaryRow(label: "子任務", value: "\(filledSubtaskCount) 項")
            summaryRow(label: "負責人", value: selectedMember?.name ?? "尚未選擇")
            summaryRow(label: "截止", value: deadline.formatted(date: .abbreviated, time: .shortened))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard()
    }

    private var actionBar: some View {
        VStack(spacing: 6) {
            Button(action: publish) {
                Text(isPublishing ? "發布中…" : "發布任務")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!canPublish || isPublishing)
            .opacity(canPublish && !isPublishing ? 1 : 0.42)

            Button("取消", action: onCancel)
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

    private var trimmedSubtaskTitles: [String] {
        subtaskDrafts.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var filledSubtaskCount: Int {
        trimmedSubtaskTitles.filter { !$0.isEmpty }.count
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
        if deadline <= Date.now { return "截止時間必須晚於目前時間" }
        if deadline > group.deadline { return "截止時間不可晚於群組總截止時間" }
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

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label)：")
                .foregroundStyle(BombTheme.ink.opacity(0.6))
            Text(value)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.bold))
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

    private func removeSubtask(_ id: UUID) {
        guard subtaskDrafts.count > 1 else { return }
        subtaskDrafts.removeAll { $0.id == id }
    }
}

private extension View {
    func inputFieldStyle() -> some View {
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
