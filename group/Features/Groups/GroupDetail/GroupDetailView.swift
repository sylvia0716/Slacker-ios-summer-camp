import SwiftUI
import UIKit

/// Group detail backed by the app's shared Group, Member, and ProjectTask data.
struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let group: Group
    let model: AppStore

    @State private var showsCopiedFeedback = false
    @State private var showsPublishTaskSheet = false
    @State private var showsDeadlineSheet = false
    @State private var deadlineDraft = Date.now
    @State private var deadlineError: String?
    @State private var showsNameSheet = false
    @State private var nameDraft = ""
    @State private var nameError: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ZStack {
                    BombTheme.yellow.ignoresSafeArea()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            topBar
                            groupIdentity
                            countdownCard
                            memberSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 120)
                    }
                    .scrollIndicators(.hidden)
                }

                if showsPublishTaskSheet {
                    BombTheme.ink.opacity(0.16)
                        .ignoresSafeArea(edges: .top)
                        .onTapGesture { closePublishTaskSheet() }
                        .transition(.opacity)

                    PublishTaskSheet(
                        group: currentGroup,
                        members: groupMembers,
                        onPublish: { title, detail, assigneeID, deadline in
                            try model.publishTask(
                                title: title,
                                detail: detail,
                                groupID: group.id,
                                assigneeMemberID: assigneeID,
                                deadline: deadline
                            )
                        },
                        onCancel: closePublishTaskSheet
                    )
                    .frame(height: proxy.size.height * 0.82)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { deadlineDraft = currentGroup.deadline }
        .sheet(isPresented: $showsDeadlineSheet) {
            DeadlineEditorSheet(deadline: $deadlineDraft, onSave: saveDeadline)
        }
        .sheet(isPresented: $showsNameSheet) {
            GroupNameEditorSheet(name: $nameDraft, onSave: saveName)
        }
        .alert("無法修改期限", isPresented: Binding(
            get: { deadlineError != nil },
            set: { if !$0 { deadlineError = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(deadlineError ?? "")
        }
        .alert("無法修改群組名稱", isPresented: Binding(
            get: { nameError != nil },
            set: { if !$0 { nameError = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(nameError ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Label("返回", systemImage: "chevron.left")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            NavigationLink {
                ChatRoomView(model: model, group: group)
            } label: {
                Label("聊天室", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
        }
    }

    private var groupIdentity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentGroup.name)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("群組代碼：\(currentGroup.inviteCode)")
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)

                Button(action: copyInviteCode) {
                    Label("複製", systemImage: "doc.on.doc.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)

                ShareLink(
                    item: "加入「\(currentGroup.name)」的群組，邀請碼：\(currentGroup.inviteCode)"
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
            }

            Button {
                nameDraft = currentGroup.name
                showsNameSheet = true
            } label: {
                Label("修改群組名稱", systemImage: "pencil")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)

            Button {
                deadlineDraft = currentGroup.deadline
                showsDeadlineSheet = true
            } label: {
                Label("修改截止時間", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)

            if showsCopiedFeedback {
                Text("群組代碼已複製")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var countdownCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            countdownCard(at: context.date)
        }
    }

    private func countdownCard(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(BombTheme.yellow)
                Text("行動代號：\(missionName)")
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text("LIVE")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(remainingTime(at: date))
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)

                Text("\(groupProgress)%")
                    .font(.system(.title2, design: .rounded, weight: .black))
            }

            ProgressView(value: Double(groupProgress), total: 100)
                .tint(BombTheme.yellow)
                .scaleEffect(y: 1.8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(BombTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .top) {
            HazardStripe()
                .clipShape(.capsule)
                .padding(.horizontal, 22)
                .offset(y: -5)
        }
    }

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("成員進度")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .layoutPriority(1)

                Spacer(minLength: 4)

                Button {
                    withAnimation(.snappy) { showsPublishTaskSheet = true }
                } label: {
                    Text(isGroupDeadlinePassed ? "已截止" : "＋ 發布任務")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(isGroupDeadlinePassed)
                .opacity(isGroupDeadlinePassed ? 0.45 : 1)
            }

            ForEach(groupMembers) { member in
                MemberProgressCard(member: memberProgressItem(for: member)) { style in
                    model.poke(memberID: member.id, in: group.id, style: style)
                }
            }
        }
    }

    private var groupMembers: [Member] {
        currentGroup.memberIDs.compactMap { memberID in
            model.members.first(where: { $0.id == memberID })
        }
    }

    private var currentGroup: Group {
        model.groups.first(where: { $0.id == group.id }) ?? group
    }

    private var groupProgress: Int {
        model.projectProgress(for: group.id)
    }

    private var isGroupDeadlinePassed: Bool {
        currentGroup.deadline <= .now
    }

    private var missionName: String {
        let name = currentGroup.name.replacingOccurrences(of: "拆彈小隊", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? currentGroup.name : name
    }

    private func remainingTime(at date: Date) -> String {
        let remaining = max(0, Int(currentGroup.deadline.timeIntervalSince(date)))
        let days = remaining / 86_400
        let hours = remaining % 86_400 / 3_600
        let minutes = remaining % 3_600 / 60

        if remaining == 0 {
            return "已截止"
        }

        return "\(days) 天 \(hours) 小時 \(minutes) 分鐘"
    }

    private func memberProgressItem(for member: Member) -> MemberProgressPreviewItem {
        let tasks = model.tasks(for: member.id, in: group.id)
        let currentTask = tasks.max(by: { $0.createdAt < $1.createdAt })
        let progress = model.memberProgress(for: member.id, in: group.id)

        return MemberProgressPreviewItem(
            id: member.id.uuidString,
            name: member.name,
            role: member.role.title,
            progress: progress,
            currentTask: currentTask?.title ?? "尚未指派任務",
            status: currentTask?.status.title ?? "待命",
            showsNudge: currentTask != nil && progress < 50
        )
    }

    private func copyInviteCode() {
        UIPasteboard.general.string = currentGroup.inviteCode
        withAnimation(.snappy) { showsCopiedFeedback = true }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { showsCopiedFeedback = false }
        }
    }

    private func closePublishTaskSheet() {
        withAnimation(.snappy) { showsPublishTaskSheet = false }
    }

    private func saveDeadline() {
        do {
            try model.updateGroupDeadline(groupID: group.id, deadline: deadlineDraft)
            showsDeadlineSheet = false
        } catch {
            deadlineError = error.localizedDescription
        }
    }

    private func saveName() {
        do {
            try model.updateGroupName(groupID: group.id, name: nameDraft)
            showsNameSheet = false
        } catch {
            nameError = error.localizedDescription
        }
    }
}

private struct DeadlineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var deadline: Date
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "截止時間",
                    selection: $deadline,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .navigationTitle("修改截止時間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { onSave() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GroupNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("群組名稱", text: $name)
            }
            .navigationTitle("修改群組名稱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { onSave() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GroupDetailPreview: View {
    @State private var model = AppStore()

    var body: some View {
        NavigationStack {
            if let group = model.groups.first {
                GroupDetailView(group: group, model: model)
            }
        }
    }
}

#Preview("Group detail") {
    GroupDetailPreview()
}
