import SwiftUI
import UIKit

struct MemberProgressPreviewItem: Identifiable {
    let id: String
    let name: String
    let role: String
    let progress: Int
    let currentTask: String
    let status: String
    let showsNudge: Bool
}

struct MemberProgressCard: View {
    let member: MemberProgressPreviewItem
    let tasks: [ProjectTask]
    let groupMemberIDs: [UUID]
    let currentUserID: UUID
    let isCurrentUser: Bool
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onSubmitDeliverable: (UUID, Deliverable) -> Void
    let onToggleSubtask: (UUID, UUID) -> Void
    let onConfirmDeliverable: (UUID) -> Void

    @State private var uploadTask: ProjectTask?
    @State private var previewDeliverable: Deliverable?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                header

                HStack(alignment: .center, spacing: 10) {
                    Text(member.currentTask)
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    Text(member.status)
                        .font(.caption2.weight(.black))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(BombTheme.ink)
                        .background(BombTheme.yellow)
                        .clipShape(.capsule)
                        .fixedSize()
                }

                ProgressView(value: Double(member.progress), total: 100)
                    .tint(progressColor)
                    .scaleEffect(y: 1.15)
                    .padding(.horizontal, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleExpanded)

            if member.showsNudge {
                HStack {
                    Spacer()
                    Button(action: {}) {
                        Label("戳一下", systemImage: "hand.tap.fill")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .foregroundStyle(.white)
                            .background(BombTheme.ink)
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("提醒功能將在下一階段開放")
                }
            }

            if isExpanded {
                Divider().overlay(BombTheme.ink)
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .comicCard()
        .animation(.snappy, value: isExpanded)
        .sheet(item: $uploadTask) { task in
            DeliverablePhotoSheet(task: task) { deliverable in
                onSubmitDeliverable(task.id, deliverable)
            }
        }
        .sheet(item: $previewDeliverable) { deliverable in
            DeliverablePhotoPreview(deliverable: deliverable)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(member.name).font(.system(.headline, design: .rounded, weight: .black))
                Text(member.role).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(member.progress)%").font(.system(.title3, design: .rounded, weight: .black))
            Image(systemName: "chevron.down")
                .font(.caption.weight(.black))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityLabel(isExpanded ? "收合成員任務" : "展開成員任務")
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if tasks.isEmpty {
                Text("尚未指派任務").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 14) {
                        checklistSection(for: task)

                        Divider().overlay(BombTheme.ink.opacity(0.45))
                        deliverableSection(for: task)
                    }
                    if task.id != tasks.last?.id { Divider().overlay(BombTheme.ink.opacity(0.45)) }
                }
            }
        }
    }

    private func checklistSection(for task: ProjectTask) -> some View {
        let pendingSubtasks = task.subtasks.filter { !$0.isComplete }
        let completedSubtasks = task.subtasks.filter(\.isComplete)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日目標（待完成）")
                    .font(.subheadline.weight(.black))

                if pendingSubtasks.isEmpty {
                    Text("今日目標已完成")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingSubtasks) { subtask in
                        if isCurrentUser {
                            Button {
                                onToggleSubtask(task.id, subtask.id)
                            } label: {
                                checklistRow(subtask, isInteractive: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            checklistRow(subtask, isInteractive: false)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("已完成事項")
                    .font(.subheadline.weight(.black))

                if completedSubtasks.isEmpty {
                    Text("尚無完成紀錄")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(completedSubtasks) { subtask in
                        checklistRow(subtask, isInteractive: false)
                    }
                }
            }

            Text("已完成 \(completedSubtasks.count) / \(task.subtasks.count)")
                .font(.caption.weight(.black))
        }
    }

    private func checklistRow(_ subtask: Subtask, isInteractive: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: subtask.isComplete ? "checkmark.square.fill" : "square")
                .font(.body.weight(.bold))
                .foregroundStyle(subtask.isComplete ? BombTheme.green : BombTheme.ink)
            Text(subtask.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(subtask.isComplete ? Color.secondary : BombTheme.ink)
                .strikethrough(subtask.isComplete)
            Spacer(minLength: 4)
            if isInteractive {
                Text("勾選")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityHint(isInteractive ? "標記這項工作為完成" : "唯讀")
    }

    @ViewBuilder
    private func deliverableSection(for task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("成果證明").font(.subheadline.weight(.black))
            if let deliverable = task.deliverable {
                HStack(alignment: .top, spacing: 12) {
                    Button { previewDeliverable = deliverable } label: {
                        deliverableThumbnail(deliverable)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(deliverable.title).font(.subheadline.weight(.black))
                        if !deliverable.detail.isEmpty {
                            Text(deliverable.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(deliverable.submittedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                confirmationSection(for: task, deliverable: deliverable)
            } else {
                Text("尚未上傳成果照片").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }

            if isCurrentUser {
                Button { uploadTask = task } label: {
                    Text(task.deliverable == nil ? "＋ 上傳成果照片" : "更換成果照片")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(BombTheme.ink).clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func confirmationSection(for task: ProjectTask, deliverable: Deliverable) -> some View {
        let confirmedIDs = Set(deliverable.confirmedMemberIDs)
        let confirmedCount = groupMemberIDs.filter { confirmedIDs.contains($0) }.count
        let isFullyConfirmed = !groupMemberIDs.isEmpty && confirmedCount == groupMemberIDs.count
        let hasCurrentUserConfirmed = confirmedIDs.contains(currentUserID)

        return VStack(alignment: .leading, spacing: 8) {
            Label("已確認", systemImage: "person.2.fill")
                .font(.caption.weight(.black))

            HStack(spacing: 8) {
                ForEach(groupMemberIDs, id: \.self) { memberID in
                    Circle()
                        .fill(confirmedIDs.contains(memberID) ? BombTheme.ink : Color.clear)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(BombTheme.ink, lineWidth: 2))
                        .accessibilityLabel(confirmedIDs.contains(memberID) ? "已確認" : "尚未確認")
                }
            }

            if isFullyConfirmed {
                Label("全部組員已確認", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.green)
            } else {
                Text("\(confirmedCount) / \(groupMemberIDs.count) 位組員已確認")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                if !hasCurrentUserConfirmed {
                    Button { onConfirmDeliverable(task.id) } label: {
                        Label("我已確認", systemImage: "checkmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BombTheme.ink)
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 2)
    }

    private func deliverableThumbnail(_ deliverable: Deliverable) -> some View {
        SwiftUI.Group {
            if let filename = deliverable.localImageFilename,
               let image = DeliverableImageStore.image(named: filename) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").font(.title2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 82)
        .background(.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(BombTheme.ink, lineWidth: 2))
        .clipped()
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(BombTheme.ink)
            Text(String(member.name.prefix(1)).uppercased()).font(.title3.weight(.black)).foregroundStyle(BombTheme.yellow)
        }
        .frame(width: 50, height: 50)
        .overlay(Circle().stroke(BombTheme.ink, lineWidth: 2))
        .accessibilityHidden(true)
    }

    private var progressColor: Color { member.showsNudge ? BombTheme.red : BombTheme.ink }
}

private struct DeliverablePhotoPreview: View {
    @Environment(\.dismiss) private var dismiss
    let deliverable: Deliverable

    var body: some View {
        NavigationStack {
            ZStack {
                BombTheme.ink.ignoresSafeArea()
                if let filename = deliverable.localImageFilename,
                   let image = DeliverableImageStore.image(named: filename) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .padding(16)
                } else {
                    Text("照片無法讀取").font(.headline.weight(.black)).foregroundStyle(.white)
                }
            }
            .navigationTitle(deliverable.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.tint(BombTheme.yellow)
                }
            }
        }
    }
}
