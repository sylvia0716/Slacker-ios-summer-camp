import SwiftUI

struct NotificationBellButton: View {
    let model: AppStore

    var body: some View {
        NavigationLink {
            NotificationInboxView(model: model)
        } label: {
            Image(systemName: "bell")
        }
        .buttonStyle(BombHeaderButtonStyle())
        .overlay(alignment: .topTrailing) {
            let unreadCount = model.notificationInbox.unreadCount
            if unreadCount > 0 {
                // 數量本來就算得出來（accessibilityValue 早就唸出數字了），
                // 只是視覺上先前只畫了一個點。
                Text(unreadCount > 9 ? L10n.text("9+") : "\(unreadCount)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BombTheme.paper)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(BombTheme.red, in: Capsule())
                    .overlay(Capsule().stroke(BombTheme.yellow, lineWidth: 2))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(L10n.text("通知"))
        .accessibilityValue(model.notificationInbox.unreadCount == 0 ? L10n.text("沒有未讀通知")
            : L10n.format("{0} 則未讀通知", String(model.notificationInbox.unreadCount)))
        .accessibilityIdentifier("notifications.bell")
    }
}

struct NotificationInboxView: View {
    let model: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNotification: InboxNotification?
    @State private var selectedRequest: GroupJoinRequest?

    private var hasSyncError: Bool {
        model.admissions.syncError != nil || model.meetingNotificationSyncFailed
    }

    /// 原本只有一行「請下拉重新整理」的紅字，沒有可按的重試入口。
    private var syncStatus: some View {
        BombSyncStatus(
            message: L10n.text("部分通知尚未同步。"),
            isRetrying: model.isLoadingCloudGroups
        ) {
            model.admissions.stop()
            model.refreshAdmissionSync()
            Task { await model.reloadCloudGroups(forceRefresh: true) }
        }
    }

    var body: some View {
        // 專案自有的 Group 模型會遮蔽 SwiftUI.Group，這裡需完整命名。
        SwiftUI.Group {
            if model.notificationInbox.items.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        if hasSyncError { syncStatus }
                        BombEmptyState(
                            systemImage: "bell",
                            title: L10n.text("目前沒有通知")
                        )
                        .padding(.top, 70)
                    }
                    .padding(16)
                }
            } else {
                // 用 List 而非 ScrollView＋LazyVStack，才能支援 swipeActions；
                // 外觀靠下面幾個 modifier 還原成原本的漫畫卡片樣式。
                List {
                    if hasSyncError {
                        syncStatus.bombInboxRow()
                    }
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
                        .bombInboxRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.notificationInbox.remove(id: item.id)
                            } label: {
                                Label(L10n.text("刪除"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                model.notificationInbox.setRead(id: item.id, isRead: !item.isRead)
                            } label: {
                                Label(item.isRead ? L10n.text("標為未讀") : L10n.text("標為已讀"),
                                      systemImage: item.isRead ? "envelope.badge" : "envelope.open")
                            }
                            .tint(BombTheme.ink)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
            }
        }
        .background(BombTheme.yellow.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("通知")) {
                Button(action: dismiss.callAsFunction) { Image(systemName: "chevron.left") }
                    .buttonStyle(BombHeaderButtonStyle())
                    .accessibilityLabel(L10n.text("返回"))
            } trailing: {
                // 原本是純文字，和左側 BombHeaderButtonStyle 的實心圓按鈕並排時
                // 看起來不像可點擊。改成同樣語彙的膠囊（墨底黃字）。
                Button(L10n.text("全部已讀")) { model.notificationInbox.markAllRead() }
                    .font(.caption.weight(.black))
                    .foregroundStyle(BombTheme.yellow)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(BombTheme.ink, in: Capsule())
                    .contentShape(Capsule())
                    .buttonStyle(.plain)
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

private extension View {
    /// 把 `List` 的預設列樣式還原成原本 ScrollView 版的漫畫卡片外觀：
    /// 透明底、無分隔線，並維持原先 16pt 水平、12pt 垂直的卡片間距。
    func bombInboxRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// 通知的視覺分色。
///
/// 刻意放在 view 層而不是 `InboxNotification.Kind` 上：Models 目前完全不依賴
/// SwiftUI，不該為了顏色把 UI 型別帶進去。
private extension InboxNotification.Kind {
    /// 圓圈底色：讓使用者不必逐字閱讀就能分辨「好消息／要注意／一般資訊」。
    ///
    /// 強度階梯：紅（急迫）＞綠（好消息）＞黃（待行動）＞淡黃（純資訊）。
    /// 中性色刻意不用 `paper`——它與卡片底色相同（對比 1.00:1），
    /// 圓圈會只剩描邊，跟旁邊的實心圓並排時顯得破碎。
    var tint: Color {
        switch self {
        case .applicationApproved: BombTheme.green
        case .applicationRejected, .taskDeadline, .projectDeadline: BombTheme.red
        case .pokeThreshold, .reviewAvailable, .reviewReminder: BombTheme.yellow
        case .applicationPending, .admissionReview, .meeting: BombTheme.yellow.opacity(0.3)
        }
    }

    /// 圖示顏色，與 `tint` 搭配確保對比足夠。
    var onTint: Color {
        switch self {
        case .applicationApproved, .applicationRejected, .taskDeadline, .projectDeadline:
            BombTheme.paper
        case .pokeThreshold, .reviewAvailable, .reviewReminder,
             .applicationPending, .admissionReview, .meeting:
            BombTheme.ink
        }
    }
}

private struct NotificationRow: View {
    let item: InboxNotification

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.kind.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(item.kind.onTint)
                .frame(width: 42, height: 42)
                .background(item.kind.tint, in: Circle())
                // 描邊讓淺色系（paper）的圓圈在米色卡片上也有輪廓。
                .overlay(Circle().stroke(BombTheme.ink.opacity(0.25), lineWidth: 1))
                // 已讀時整個徽章一起淡化，而不是只調底色透明度——
                // 後者會讓 paper 這種淺色在卡片上整個消失。
                .opacity(item.isRead ? 0.55 : 1)
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
                // 通知匣看的是「多久以前」而不是「幾點幾分」；
                // 絕對時間保留在詳情頁。
                Text(item.createdAt, format: .relative(presentation: .named).locale(L10n.locale))
                    .font(.caption)
                    .foregroundStyle(BombTheme.secondaryText)
            }
        }
        .foregroundStyle(BombTheme.ink)
        .padding(16)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: BombRadius.card))
        .overlay(RoundedRectangle(cornerRadius: BombRadius.card).stroke(BombTheme.ink, lineWidth: item.isRead ? 1 : 2))
        .contentShape(RoundedRectangle(cornerRadius: BombRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? L10n.text("已讀") : L10n.text("未讀"))
    }
}

private struct NotificationDetailView: View {
    let model: AppStore
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
                    .font(.system(.title2, design: .rounded, weight: .black))
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
