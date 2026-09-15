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

    @State private var uploadTask: ProjectTask?
    @State private var previewDeliverable: Deliverable?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onToggleExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text(tasks.isEmpty ? "尚未指派任務" : "\(tasks.count) 項任務 · 已完成 \(tasks.filter(\.isCompleted).count) 項")
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
                    .accessibilityLabel("任務進度")
                    .accessibilityValue(tasks.isEmpty ? "尚未指派任務" : "\(member.progress)%")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收合\(member.name)的任務" : "展開\(member.name)的任務")

            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 14) {
                    Text(task.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(task.isCompleted ? Color.secondary : BombTheme.ink)
                        .strikethrough(task.isCompleted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isExpanded {
                        checklistSection(for: task)
                        deliverableSection(for: task)
                    }
                }
                if task.id != tasks.last?.id {
                    Divider().overlay(BombTheme.ink.opacity(0.2))
                }
            }

            if member.showsNudge && !isCurrentUser {
                HStack {
                    Spacer()
                    PokeActionButton(onPoke: onPoke)
                }
            }
        }
        .foregroundStyle(BombTheme.ink)
        .padding(16)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BombTheme.ink, lineWidth: 2))
        .animation(.snappy, value: isExpanded)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("子任務 \(task.subtasks.filter(\.isComplete).count)/\(task.subtasks.count)")
                    .font(.subheadline.weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BombTheme.yellow, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(BombTheme.ink).frame(height: 2)
                    }
                ForEach(task.subtasks) { subtask in
                    if isCurrentUser {
                        Button { onToggleSubtask(task.id, subtask.id) } label: {
                            checklistRow(subtask)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.pendingTaskUpdates.contains(task.id))
                        .accessibilityValue(subtask.isComplete ? "已完成" : "未完成")
                        .accessibilityHint("切換子任務完成狀態")
                    } else {
                        checklistRow(subtask)
                    }
                }
            }
        }
    }

    private func checklistRow(_ subtask: Subtask) -> some View {
        Text(subtask.title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(subtask.isComplete ? Color.secondary : BombTheme.ink)
            .strikethrough(subtask.isComplete)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func deliverableSection(for task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成果附件").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
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
                            Text(deliverable.submittedAt.formatted(date: .abbreviated, time: .shortened))
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
                Text("尚未上傳成果").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            }
            if isCurrentUser {
                Button { uploadTask = task } label: {
                    Text(task.deliverable == nil ? "＋ 上傳成果" : "更換成果")
                        .font(.subheadline.weight(.black))
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

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("成員確認").foregroundStyle(BombTheme.ink)
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
                    Text("確認這項成果")
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
                let name = model.members.first(where: { $0.id == id })?.name ?? "成員"
                Circle()
                    .fill(confirmed ? BombTheme.ink : Color(uiColor: .systemGray4))
                    .frame(width: 32, height: 32)
                    .overlay {
                        if confirmed {
                            Text(String(name.prefix(1)).uppercased())
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(BombTheme.yellow)
                        }
                    }
                    .accessibilityLabel("\(name)：\(confirmed ? "已確認" : "尚未確認")")
            }
            Text(isFullyConfirmed ? "已全部確認" : "待確認")
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

    @State private var isCharging = false
    @State private var suppressNextTap = false
    @State private var hasChargedBomb = false
    @State private var showsBomb = false
    @State private var showsExplosion = false
    @State private var isCoolingDown = false
    @State private var showsLimitAlert = false
    @State private var lightFeedbackID = 0
    @State private var heavyFeedbackID = 0

    var body: some View {
        ZStack {
            Label(isCoolingDown ? "讓他喘口氣" : "戳一下", systemImage: "hand.tap.fill")
                .font(.subheadline.weight(.black))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(BombTheme.ink)
                .clipShape(.capsule)
                .scaleEffect(isCharging ? 0.92 : 1)
                .rotationEffect(.degrees(isCharging ? 2 : 0))
                .animation(
                    isCharging ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .snappy,
                    value: isCharging
                )
                .contentShape(.capsule)
                .onTapGesture {
                    guard !suppressNextTap, !isCoolingDown else { return }
                    sendPoke(style: .gentle, isBombPoke: false)
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    guard !isCoolingDown else { return }
                    suppressNextTap = true
                    hasChargedBomb = true
                    sendPoke(style: .alarm, isBombPoke: true)
                } onPressingChanged: { isPressing in
                    guard !isCoolingDown else { return }
                    isCharging = isPressing

                    guard !isPressing, hasChargedBomb else { return }
                    hasChargedBomb = false
                    showsBomb = false
                    showsExplosion = true

                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        showsExplosion = false
                        suppressNextTap = false
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    guard !isCoolingDown else { return }
                    sendPoke(style: .gentle, isBombPoke: false)
                }

            Text("💣")
                .font(.system(size: 52))
                .offset(y: -58)
                .scaleEffect(showsBomb ? 1 : 0.1)
                .opacity(showsBomb ? 1 : 0)
                .allowsHitTesting(false)

            Text("💥")
                .font(.system(size: 62))
                .offset(y: -58)
                .scaleEffect(showsExplosion ? 1 : 0.1)
                .opacity(showsExplosion ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(height: 38)
        .animation(.bouncy, value: showsBomb)
        .animation(.snappy, value: showsExplosion)
        .sensoryFeedback(.impact(weight: .light), trigger: lightFeedbackID)
        .sensoryFeedback(.impact(weight: .heavy), trigger: heavyFeedbackID)
        .alert("讓他喘口氣>_<", isPresented: $showsLimitAlert) {
            Button("好", role: .cancel) { }
        }
    }

    private func sendPoke(style: PokeStyle, isBombPoke: Bool) {
        guard let pokeCount = onPoke(style) else { return }

        if isBombPoke {
            heavyFeedbackID += 1
            showsBomb = true
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
                        Text(deliverable.originalFilename ?? "成果附件")
                            .font(.headline.weight(.black))
                    }
                    .foregroundStyle(.white)
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
