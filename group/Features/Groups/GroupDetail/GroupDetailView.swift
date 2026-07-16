import SwiftUI
import UIKit

/// Group detail backed by the app's shared Group, Member, and ProjectTask data.
struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let group: Group
    let model: AppStore

    @State private var showsCopiedFeedback = false
    @State private var showsPublishTaskSheet = false

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
                        group: group,
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
                ChatRoomView(groupName: group.name)
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
            Text(group.name)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("群組代碼：\(group.inviteCode)")
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
            }

            if showsCopiedFeedback {
                Text("群組代碼已複製")
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.green)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var countdownCard: some View {
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
                Text(remainingTime)
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
                    Text("＋ 發布任務")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(BombTheme.ink)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }

            ForEach(groupMembers) { member in
                MemberProgressCard(member: memberProgressItem(for: member))
            }
        }
    }

    private var groupMembers: [Member] {
        group.memberIDs.compactMap { memberID in
            model.members.first(where: { $0.id == memberID })
        }
    }

    private var groupProgress: Int {
        model.projectProgress(for: group.id)
    }

    private var missionName: String {
        let name = group.name.replacingOccurrences(of: "拆彈小隊", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? group.name : name
    }

    private var remainingTime: String {
        let remaining = max(0, Int(group.deadline.timeIntervalSinceNow))
        let days = remaining / 86_400
        let hours = remaining % 86_400 / 3_600
        let minutes = remaining % 3_600 / 60
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
        UIPasteboard.general.string = group.inviteCode
        withAnimation(.snappy) { showsCopiedFeedback = true }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { showsCopiedFeedback = false }
        }
    }

    private func closePublishTaskSheet() {
        withAnimation(.snappy) { showsPublishTaskSheet = false }
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
