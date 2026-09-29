import SwiftUI

struct NotificationBellButton: View {
    let model: GroupBombModel

    var body: some View {
        NavigationLink {
            NotificationInboxView(model: model)
        } label: {
            Image(systemName: "bell")
        }
        .buttonStyle(BombHeaderButtonStyle())
        .overlay(alignment: .topTrailing) {
            if model.notificationInbox.unreadCount > 0 {
                Circle()
                    .fill(BombTheme.red)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(BombTheme.yellow, lineWidth: 2))
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(L10n.text("通知"))
        .accessibilityValue(model.notificationInbox.unreadCount == 0 ? L10n.text("沒有未讀通知")
            : L10n.format("{0} 則未讀通知", String(model.notificationInbox.unreadCount)))
        .accessibilityIdentifier("notifications.bell")
    }
}

struct NotificationInboxView: View {
    let model: GroupBombModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNotification: InboxNotification?
    @State private var selectedRequest: GroupJoinRequest?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.admissions.syncError != nil || model.meetingNotificationSyncFailed {
                    Text(L10n.text("部分通知尚未同步，請下拉重新整理。"))
                        .font(.footnote)
                        .foregroundStyle(BombTheme.red)
                }
                if model.notificationInbox.items.isEmpty {
                    ContentUnavailableView(L10n.text("目前沒有通知"), systemImage: "bell")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                } else {
                    ForEach(model.notificationInbox.items) { item in
                        Button {
                            model.notificationInbox.markRead(id: item.id)
                            if item.kind == .admissionReview,
                               let request = model.admissions.incomingRequests.first(where: {
                                   $0.groupID == item.groupID && $0.requestID == item.relatedID
                               }) {
                                selectedRequest = request
                            } else {
                                selectedNotification = item
                            }
                        } label: {
                            NotificationRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(BombTheme.yellow.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("通知")) {
                Button(action: dismiss.callAsFunction) { Image(systemName: "chevron.left") }
                    .buttonStyle(BombHeaderButtonStyle())
                    .accessibilityLabel(L10n.text("返回"))
            } trailing: {
                Button(L10n.text("全部已讀")) { model.notificationInbox.markAllRead() }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BombTheme.ink)
                    .frame(minHeight: 44)
                    .disabled(model.notificationInbox.unreadCount == 0)
                    .opacity(model.notificationInbox.unreadCount == 0 ? 0.4 : 1)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .bombTabBarHidden()
        .refreshable {
            model.admissions.stop()
            model.refreshAdmissionSync()
            await model.reloadCloudGroups(forceRefresh: true)
        }
        .navigationDestination(item: $selectedNotification) { item in
            NotificationDetailView(model: model, item: item)
        }
        .sheet(item: $selectedRequest) { request in
            GroupAdmissionReviewSheet(model: model, request: request)
        }
    }
}

private struct NotificationRow: View {
    let item: InboxNotification

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.kind.symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 42, height: 42)
                .background(item.isRead ? BombTheme.yellow.opacity(0.4) : BombTheme.yellow, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.headline)
                    Spacer(minLength: 8)
                    if !item.isRead {
                        Circle().fill(BombTheme.red).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                Text(item.message)
                    .font(.subheadline)
                    .foregroundStyle(BombTheme.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(item.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))
                    .font(.caption)
                    .foregroundStyle(BombTheme.secondaryText)
            }
        }
        .foregroundStyle(BombTheme.ink)
        .padding(16)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BombTheme.ink, lineWidth: item.isRead ? 1 : 2))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? L10n.text("已讀") : L10n.text("未讀"))
    }
}

private struct NotificationDetailView: View {
    let model: GroupBombModel
    let item: InboxNotification
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRequest: GroupJoinRequest?

    private var group: Group? {
        model.groups.first { $0.id.uuidString == item.groupID || $0.firestoreDocumentID == item.groupID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(item.title, systemImage: item.kind.symbol)
                    .font(.title2.weight(.black))
                Text(item.message).font(.body)
                Text(item.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))
                    .font(.caption)
                    .foregroundStyle(BombTheme.secondaryText)
                if item.kind == .admissionReview {
                    if let request = model.admissions.incomingRequests.first(where: {
                        $0.groupID == item.groupID && $0.requestID == item.relatedID
                    }) {
                        Button(L10n.text("查看申請")) { selectedRequest = request }
                            .buttonStyle(BombFormPrimaryButtonStyle())
                    } else if let error = model.admissions.syncError {
                        Text(error).font(.subheadline).foregroundStyle(BombTheme.red)
                    } else if model.isLoadingCloudGroups || (group?.memberRoles[model.currentUserID] == .leader
                        && !model.admissions.loadedIncomingGroupIDs.contains(item.groupID)) {
                        ProgressView()
                    } else {
                        Text(L10n.text("此申請已更新"))
                            .font(.subheadline)
                            .foregroundStyle(BombTheme.secondaryText)
                    }
                }
                if item.kind == .taskDeadline, let rawID = item.relatedID, let taskID = UUID(uuidString: rawID),
                   model.projectTasks.contains(where: { $0.id == taskID && $0.ownerMemberID == model.currentUserID }) {
                    NavigationLink {
                        MyTaskDetailView(model: model, taskID: taskID)
                    } label: {
                        Text(L10n.text("查看任務"))
                    }
                    .buttonStyle(BombFormPrimaryButtonStyle())
                } else if let group {
                    NavigationLink {
                        GroupDetailView(group: group, model: model,
                            opensPeerReview: item.kind == .reviewAvailable || item.kind == .reviewReminder)
                    } label: {
                        Text(L10n.text("查看群組"))
                    }
                    .buttonStyle(BombFormPrimaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .comicCard()
            .padding(16)
        }
        .foregroundStyle(BombTheme.ink)
        .background(BombTheme.yellow.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("通知")) {
                Button(action: dismiss.callAsFunction) { Image(systemName: "chevron.left") }
                    .buttonStyle(BombHeaderButtonStyle())
                    .accessibilityLabel(L10n.text("返回"))
            } trailing: { EmptyView() }
        }
        .navigationBarBackButtonHidden()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .bombTabBarHidden()
        .sheet(item: $selectedRequest) { request in
            GroupAdmissionReviewSheet(model: model, request: request)
        }
    }
}
