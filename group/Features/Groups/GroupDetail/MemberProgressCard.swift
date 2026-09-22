import SwiftUI
import UIKit

struct PokeButtonAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

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
    let model: GroupBombModel
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
    let onPoke: (PokeStyle) -> Int?
    let onPokeEmoji: (String, String?) -> Void

    @State private var uploadTask: ProjectTask?
    @State private var previewDeliverable: Deliverable?
    @State private var expandedTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onToggleExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text(tasks.isEmpty ? L10n.text("尚未指派任務") : L10n.format("{0} 項任務 · 已完成 {1} 項", String(describing: tasks.count), String(describing: tasks.filter(\.isCompleted).count)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                    GeometryReader { geometry in
                        Capsule().fill(BombTheme.ink.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule().fill(BombTheme.ink)
                                    .frame(width: geometry.size.width * Double(min(100, max(0, member.progress))) / 100)
                            }
                    }
                    .frame(height: 3)
                    .accessibilityLabel(L10n.text("任務進度"))
                    .accessibilityValue(tasks.isEmpty ? L10n.text("尚未指派任務") : "\(member.progress)%")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? L10n.format("收合{0}的任務", String(describing: member.name)) : L10n.format("展開{0}的任務", String(describing: member.name)))

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        taskCard(task, number: index + 1)
                    }

                    if tasks.isEmpty {
                        emptyTaskState
                    }
                }

                if member.showsNudge && !isCurrentUser {
                    HStack {
                        Spacer()
                        PokeActionButton(onPoke: onPoke, onPokeEmoji: { onPokeEmoji(member.id, $0) })
                            .anchorPreference(key: PokeButtonAnchorKey.self, value: .bounds) {
                                [member.id: $0]
                            }
                    }
                }
            }
        }
        .foregroundStyle(BombTheme.ink)
        .padding(16)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 3))
        .animation(.snappy, value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                expandedTaskID = nil
            }
        }
        .sheet(item: $uploadTask) { task in
            DeliverableSubmissionSheet(task: task) { deliverable in
                onSubmitDeliverable(task.id, deliverable)
            }
        }
        .sheet(item: $previewDeliverable) { deliverable in
            DeliverablePhotoPreview(deliverable: deliverable)
        }
        .accessibilityElement(children: .contain)
    }

    private func taskCard(_ task: ProjectTask, number: Int) -> some View {
        let isTaskExpanded = expandedTaskID == task.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    expandedTaskID = isTaskExpanded ? nil : task.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(L10n.format("任務 {0}", String(describing: number)))
                            .font(.caption.weight(.black))
                            .foregroundStyle(BombTheme.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(BombTheme.yellow, in: Capsule())

                        Text(task.title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(task.isCompleted ? Color.secondary : BombTheme.ink)
                            .strikethrough(task.isCompleted)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(task.progress)%")
                            .font(.subheadline.weight(.black))
                            .monospacedDigit()

                        Image(systemName: isTaskExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.black))
                    }

                    HStack(spacing: 8) {
                        ProgressView(value: Double(task.progress), total: 100)
                            .tint(BombTheme.ink)

                        Text(L10n.format(
                            "{0}/{1} 子任務",
                            String(describing: task.subtasks.filter(\.isComplete).count),
                            String(describing: task.subtasks.count)
                        ))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    }
                }
                .contentShape(Rectangle())
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isTaskExpanded
                ? L10n.format("收合任務 {0}", String(describing: task.title))
                : L10n.format("展開任務 {0}", String(describing: task.title)))

            if isTaskExpanded {
                Divider()
                    .overlay(BombTheme.ink.opacity(0.16))

                VStack(alignment: .leading, spacing: 18) {
                    checklistSection(for: task)
                    deliverableSection(for: task)
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(BombTheme.paper.mix(with: .white, by: 0.22), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink.opacity(0.7), lineWidth: 1.5))
    }

    private var emptyTaskState: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.headline.weight(.bold))
            Text(L10n.text("目前沒有指派任務"))
                .font(.subheadline.weight(.bold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(BombTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            avatar
            Text("\(Text(member.name).font(.system(.title2, design: .rounded, weight: .black))) \(roleLabel)")
                .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(tasks.isEmpty ? "—" : "\(member.progress)%")
                .font(.system(.title2, design: .rounded, weight: .black))
                .monospacedDigit()
                .fixedSize()
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.subheadline.weight(.black))
        }
    }

    private var roleLabel: Text {
        let label = member.role == MemberRole.leader.title
            ? Text(Image(systemName: "crown.fill"))
            : Text(member.role)
        return label
            .font(.subheadline.weight(.bold))
            .foregroundColor(.secondary)
            .baselineOffset(2)
    }

    @ViewBuilder
    private func checklistSection(for task: ProjectTask) -> some View {
        if !task.subtasks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L10n.text("子任務"), systemImage: "arrow.turn.down.right")
                        .font(.subheadline.weight(.black))
                    Spacer()
                    Text(L10n.format(
                        "已完成 {0}/{1}",
                        String(describing: task.subtasks.filter(\.isComplete).count),
                        String(describing: task.subtasks.count)
                    ))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(task.subtasks) { subtask in
                        if isCurrentUser {
                            Button { onToggleSubtask(task.id, subtask.id) } label: {
                                checklistRow(subtask)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.pendingTaskUpdates.contains(task.id))
                            .accessibilityValue(subtask.isComplete ? L10n.text("已完成") : L10n.text("未完成"))
                            .accessibilityHint(L10n.text("切換子任務完成狀態"))
                        } else {
                            checklistRow(subtask)
                        }
                    }
                }
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(BombTheme.yellow)
                        .frame(width: 4)
                }
            }
        }
    }

    private func checklistRow(_ subtask: Subtask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: subtask.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.bold))
                .foregroundStyle(subtask.isComplete ? BombTheme.ink : BombTheme.ink.opacity(0.55))
                .padding(.top, 1)

            Text(subtask.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(subtask.isComplete ? Color.secondary : BombTheme.ink)
                .strikethrough(subtask.isComplete)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(BombTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }

    private func deliverableSection(for task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("成果交付"), systemImage: "paperclip")
                    .font(.subheadline.weight(.black))

                Spacer()

                if isCurrentUser, task.deliverable != nil {
                    Button(L10n.text("更換")) { uploadTask = task }
                        .font(.caption.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .buttonStyle(.plain)
                }
            }
            if let deliverable = task.deliverable {
                AttachmentActionButton(model: model, taskID: task.id, deliverable: deliverable,
                                       localPreview: { previewDeliverable = deliverable }) {
                    HStack(spacing: 12) {
                        AttachmentPhotoThumbnail(model: model, taskID: task.id, deliverable: deliverable)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(deliverable.originalFilename ?? deliverable.title)
                                .font(.subheadline.weight(.black))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(deliverable.submittedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
                                .font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.down.to.line")
                            .font(.title3.weight(.bold))
                    }
                    .padding(10)
                    .background(BombTheme.paper.mix(with: .white, by: 0.25), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(BombTheme.ink.opacity(0.12), lineWidth: 1))
                }
                confirmationSection(for: task, deliverable: deliverable)
            } else {
                Text(L10n.text("尚未上傳成果")).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            }
            if isCurrentUser, task.deliverable == nil {
                Button { uploadTask = task } label: {
                    Text(L10n.text("＋ 上傳成果"))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(BombTheme.ink, in: RoundedRectangle(cornerRadius: 10))
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

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.text("成員確認")).foregroundStyle(BombTheme.ink)
                Text("\(confirmedCount)/\(groupMemberIDs.count)").foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.black))
            ViewThatFits(in: .horizontal) {
                confirmationAvatars(confirmedIDs: confirmedIDs, isFullyConfirmed: isFullyConfirmed)
                ScrollView(.horizontal) {
                    confirmationAvatars(confirmedIDs: confirmedIDs, isFullyConfirmed: isFullyConfirmed)
                }
                .scrollIndicators(.hidden)
            }
            if !hasCurrentUserConfirmed && groupMemberIDs.contains(currentUserID) {
                Button { onConfirmDeliverable(task.id) } label: {
                    Text(L10n.text("確認這項成果"))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BombTheme.ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.pendingTaskUpdates.contains(task.id))
            }
        }
    }

    private func confirmationAvatars(confirmedIDs: Set<UUID>, isFullyConfirmed: Bool) -> some View {
        HStack(spacing: 7) {
            ForEach(groupMemberIDs, id: \.self) { id in
                let confirmed = confirmedIDs.contains(id)
                let name = model.members.first(where: { $0.id == id })?.name ?? L10n.text("成員")
                MemberPhotoAvatar(
                    groupID: tasks.first?.firestoreGroupID,
                    uid: model.members.first(where: { $0.id == id })?.firebaseUID,
                    name: name, confirmed: confirmed
                )
                    .accessibilityLabel("\(name)：\(confirmed ? L10n.text("已確認") : L10n.text("尚未確認"))")
            }
            Text(isFullyConfirmed ? L10n.text("已全部確認") : L10n.text("待確認"))
                .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var avatar: some View {
        Circle().fill(BombTheme.ink)
            .frame(width: 50, height: 50)
            .overlay {
                Text(String(member.name.prefix(1)).uppercased())
                    .font(.title2.weight(.black)).foregroundStyle(BombTheme.yellow)
            }
            .accessibilityHidden(true)
    }
}

private struct PokeActionButton: View {
    let onPoke: (PokeStyle) -> Int?
    let onPokeEmoji: (String?) -> Void

    @State private var isCharging = false
    @State private var suppressNextTap = false
    @State private var hasChargedBomb = false
    @State private var isCoolingDown = false
    @State private var showsLimitAlert = false
    @State private var lightFeedbackID = 0
    @State private var heavyFeedbackID = 0
    @State private var actionFeedbackID = 0

    var body: some View {
        ZStack {
            Label(isCoolingDown ? L10n.text("讓他喘口氣") : L10n.text("戳一下"), systemImage: "hand.tap.fill")
                .font(.subheadline.weight(.black))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(BombTheme.ink)
                .clipShape(Capsule())
                .symbolEffect(.bounce, value: actionFeedbackID)
                .scaleEffect(isCharging ? 0.92 : 1)
                .rotationEffect(.degrees(isCharging ? 2 : 0))
                .animation(
                    isCharging ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .snappy,
                    value: isCharging
                )
                .contentShape(Capsule())
                .onTapGesture {
                    guard !suppressNextTap, !isCoolingDown else { return }
                    _ = sendPoke(style: .gentle, isBombPoke: false)
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    guard !isCoolingDown else { return }
                    suppressNextTap = true
                    guard sendPoke(style: .alarm, isBombPoke: true) else {
                        suppressNextTap = false
                        return
                    }
                    hasChargedBomb = true
                    onPokeEmoji("💣")
                } onPressingChanged: { isPressing in
                    guard !isCoolingDown else { return }
                    isCharging = isPressing

                    guard !isPressing, hasChargedBomb else { return }
                    hasChargedBomb = false
                    onPokeEmoji("💥")

                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        onPokeEmoji(nil)
                        suppressNextTap = false
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isCoolingDown ? L10n.text("讓他喘口氣") : L10n.text("戳一下"))
                .accessibilityHint(L10n.text("長按可發送加強提醒"))
                .accessibilityAction {
                    guard !isCoolingDown else { return }
                    _ = sendPoke(style: .gentle, isBombPoke: false)
                }

        }
        .frame(height: 38)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedbackID)
        .sensoryFeedback(.impact(weight: .heavy), trigger: heavyFeedbackID)
        .bombDialog(L10n.text("讓他喘口氣>_<"), isPresented: $showsLimitAlert) {
            Button(L10n.text("好")) { }
        }
    }

    private func sendPoke(style: PokeStyle, isBombPoke: Bool) -> Bool {
        guard let pokeCount = onPoke(style) else { return false }

        actionFeedbackID += 1
        if isBombPoke {
            heavyFeedbackID += 1
        } else {
            lightFeedbackID += 1
        }

        if pokeCount == 15 {
            showsLimitAlert = true
            isCoolingDown = true
            Task {
                try? await Task.sleep(for: .seconds(10))
                isCoolingDown = false
            }
        }
        return true
    }

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
                    VStack(spacing: 12) {
                        Image(systemName: deliverable.url == nil ? "doc.fill" : "link")
                            .font(.system(size: 42, weight: .black))
                        Text(deliverable.originalFilename ?? L10n.text("成果附件"))
                            .font(.headline.weight(.black))
                    }
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle(deliverable.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("完成")) { dismiss() }.tint(BombTheme.yellow)
                }
            }
        }
    }
}
