import SwiftUI

/// First tab: groups projects by their deadline and peer-review state.
struct GroupListView: View {
    let model: GroupBombModel
    private let tutorialStep: Binding<TutorialStep?>?
    private let onReplayTutorial: (() -> Void)?

    @State private var showsCreateGroupSheet = false
    @State private var newlyCreatedGroup: Group?

    init(
        model: GroupBombModel,
        tutorialStep: Binding<TutorialStep?>? = nil,
        onReplayTutorial: (() -> Void)? = nil
    ) {
        self.model = model
        self.tutorialStep = tutorialStep
        self.onReplayTutorial = onReplayTutorial
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ZStack {
                BombTheme.yellow.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的群組")
                                .font(.system(.largeTitle, design: .rounded, weight: .black))
                            Text("選一組，繼續拆彈。")
                                .font(.subheadline.bold())
                        }

                        let activeGroups = groups(matching: { $0 == .active }, now: context.date)
                        let awaitingGroups = groups(matching: { $0.isAwaitingReview }, now: context.date)
                        let closedGroups = groups(matching: { $0 == .closed }, now: context.date)

                        groupSection(title: "進行中", groups: activeGroups, now: context.date)
                        groupSection(title: "待評分", groups: awaitingGroups, now: context.date)
                        groupSection(title: "已完成", groups: closedGroups, now: context.date)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("群組")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("建立群組", systemImage: "plus") {
                        tutorialStep?.wrappedValue = .createGroupForm
                        showsCreateGroupSheet = true
                    }
                    Button("加入群組", systemImage: "person.badge.plus") { model.lastEvent = "加入群組功能準備中" }
                } label: {
                    Image(systemName: "plus")
                        .tutorialTarget(
                            .createGroupButton,
                            enabled: tutorialStep?.wrappedValue == .createGroup
                        )
                }
            }

#if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                debugMenu
            }
#endif
        }
        .sheet(isPresented: $showsCreateGroupSheet) {
            CreateGroupSheet(
                onCreate: createGroup,
                onCancel: cancelCreateGroup
            )
        }
        .navigationDestination(item: $newlyCreatedGroup) { group in
            GroupDetailView(group: group, model: model, tutorialStep: tutorialStep)
        }
    }

    @ViewBuilder
    private func groupSection(title: String, groups: [Group], now: Date) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .black))

                ForEach(groups) { group in
                    let status = listStatus(for: group, now: now)
                    NavigationLink {
                        destination(for: group, status: status)
                    } label: {
                        GroupRow(
                            group: group,
                            status: status,
                            progress: model.projectProgress(for: group.id),
                            completedReviewerCount: model.completedPeerReviewerCount(in: group.id),
                            now: now
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func groups(
        matching predicate: (GroupListStatus) -> Bool,
        now: Date
    ) -> [Group] {
        model.groups.filter { predicate(listStatus(for: $0, now: now)) }
    }

    private func listStatus(for group: Group, now: Date) -> GroupListStatus {
        guard now >= group.deadline else { return .active }

        let completedReviewerCount = model.completedPeerReviewerCount(in: group.id)
        if !group.memberIDs.isEmpty, completedReviewerCount == group.memberIDs.count {
            return .closed
        }

        return model.projectProgress(for: group.id) >= 100
            ? .awaitingReviewCompleted
            : .awaitingReviewExploded
    }

    @ViewBuilder
    private func destination(for group: Group, status: GroupListStatus) -> some View {
        switch status {
        case .active, .awaitingReviewCompleted, .awaitingReviewExploded:
            GroupDetailView(group: group, model: model, tutorialStep: tutorialStep)
        case .closed:
            PostGameReviewView(groupName: group.name)
        }
    }

#if DEBUG
    private var debugMenu: some View {
        Menu {
            Button("重設 iOS Summer Camp 互評") {
                resetReviews(inviteCode: "IOS100")
            }
            Button("重設電子電路期末互評") {
                resetReviews(inviteCode: "EE0073")
            }
            Divider()
            Button("完成 iOS Summer Camp 全部互評") {
                completeAllReviews(inviteCode: "IOS100")
            }
            Button("完成電子電路期末全部互評") {
                completeAllReviews(inviteCode: "EE0073")
            }
            if onReplayTutorial != nil {
                Divider()
                Button("重新播放新手教學", systemImage: "arrow.counterclockwise") {
                    onReplayTutorial?()
                }
            }
        } label: {
            Text("測試")
                .font(.caption.weight(.black))
                .foregroundStyle(BombTheme.ink)
        }
    }

    private func resetReviews(inviteCode: String) {
        guard let group = model.groups.first(where: { $0.inviteCode == inviteCode }) else { return }
        model.resetPeerReviews(for: group.id)
    }

    private func completeAllReviews(inviteCode: String) {
        guard let group = model.groups.first(where: { $0.inviteCode == inviteCode }) else { return }
        model.resetPeerReviews(for: group.id)

        for reviewerID in group.memberIDs {
            for revieweeID in group.memberIDs where reviewerID != revieweeID {
                _ = try? model.submitPeerReview(
                    groupID: group.id,
                    reviewerID: reviewerID,
                    revieweeID: revieweeID,
                    taskCompletionScore: 4,
                    discussionScore: 4,
                    collaborationScore: 4,
                    ideaScore: 4,
                    reliabilityScore: 4,
                    comment: "",
                    now: group.deadline.addingTimeInterval(1)
                )
            }
        }
    }
#endif

    private func createGroup(name: String, deadline: Date) {
        let existingIDs = Set(model.groups.map(\.id))
        model.createGroup(name: name, deadline: deadline)
        guard let group = model.groups.last(where: { !existingIDs.contains($0.id) }) else { return }

        showsCreateGroupSheet = false
        newlyCreatedGroup = group
        tutorialStep?.wrappedValue = .inviteCode
    }

    private func cancelCreateGroup() {
        showsCreateGroupSheet = false
        if tutorialStep?.wrappedValue == .createGroupForm {
            tutorialStep?.wrappedValue = .createGroup
        }
    }
}

private struct CreateGroupSheet: View {
    @State private var name = "我的第一個拆彈計畫"
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    let onCreate: (String, Date) -> Void
    let onCancel: () -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BombTheme.yellow.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("建立第一個專案")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("專案名稱")
                            .font(.headline.weight(.black))
                        TextField("輸入專案名稱", text: $name)
                            .textFieldStyle(.plain)
                            .font(.headline.weight(.bold))
                            .padding(14)
                            .background(BombTheme.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(BombTheme.ink, lineWidth: 3))

                        Text("Deadline")
                            .font(.headline.weight(.black))
                        DatePicker("截止時間", selection: $deadline, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .font(.subheadline.weight(.bold))
                            .padding(14)
                            .background(BombTheme.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(BombTheme.ink, lineWidth: 3))
                    }
                    .padding(18)
                    .background(BombTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(BombTheme.ink, lineWidth: 4))
                    .shadow(color: BombTheme.ink, radius: 0, x: 6, y: 6)

                    Button("完成建立，開始拆彈") {
                        onCreate(trimmedName, deadline)
                    }
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(BombTheme.ink)
                    .clipShape(.capsule)
                    .buttonStyle(.plain)
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.45 : 1)

                    Spacer()
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onCancel)
                        .fontWeight(.black)
                        .foregroundStyle(BombTheme.ink)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private enum GroupListStatus: Equatable {
    case active
    case awaitingReviewCompleted
    case awaitingReviewExploded
    case closed

    var isAwaitingReview: Bool {
        self == .awaitingReviewCompleted || self == .awaitingReviewExploded
    }

    var iconName: String {
        switch self {
        case .active: "bolt.fill"
        case .awaitingReviewCompleted: "checkmark.circle.fill"
        case .awaitingReviewExploded: "burst.fill"
        case .closed: "trophy.fill"
        }
    }

    var title: String {
        switch self {
        case .active: "進行中"
        case .awaitingReviewCompleted: "成功拆彈"
        case .awaitingReviewExploded: "任務爆炸"
        case .closed: "已完成"
        }
    }

    var badgeTitle: String {
        switch self {
        case .active: "進行中"
        case .awaitingReviewCompleted, .awaitingReviewExploded: "待評分"
        case .closed: "已完成"
        }
    }

    var accentColor: Color {
        switch self {
        case .active: BombTheme.yellow
        case .awaitingReviewCompleted: Color(red: 0.96, green: 0.58, blue: 0.08)
        case .awaitingReviewExploded: BombTheme.red
        case .closed: BombTheme.green
        }
    }
}

private struct GroupRow: View {
    let group: Group
    let status: GroupListStatus
    let progress: Int
    let completedReviewerCount: Int
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status.iconName)
                    .foregroundStyle(status.accentColor)

                Text(group.name)
                    .font(.title3.weight(.black))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(status.badgeTitle)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(status.accentColor)
                    .clipShape(.capsule)
            }

            Text(status.title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(status.accentColor)

            if status == .active {
                HStack {
                    Label(remainingDays, systemImage: "timer")
                    Spacer()
                    Label("\(group.memberIDs.count) 位特工", systemImage: "person.3.fill")
                }
                .font(.caption.bold())
            } else {
                HStack {
                    Text("最終進度 \(progress)%")
                    Spacer()
                    Text(reviewProgressText)
                }
                .font(.caption.bold())
            }

            ProgressView(value: Double(progress), total: 100)
                .tint(status.accentColor)
                .scaleEffect(y: 1.4)

            if status == .closed {
                HStack(spacing: 5) {
                    Text("查看賽後回顧")
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.black))
                .foregroundStyle(BombTheme.paper)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(BombTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(status == .awaitingReviewExploded ? BombTheme.red : BombTheme.ink, lineWidth: 3)
        }
    }

    private var remainingDays: String {
        let seconds = max(0, group.deadline.timeIntervalSince(now))
        let days = max(1, Int(ceil(seconds / 86_400)))
        return "剩 \(days) 天"
    }

    private var reviewProgressText: String {
        status == .closed
            ? "互評已完成"
            : "互評進度 \(completedReviewerCount) / \(group.memberIDs.count)"
    }
}
