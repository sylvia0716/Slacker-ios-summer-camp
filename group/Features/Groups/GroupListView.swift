import SwiftUI

/// First tab: groups projects by their deadline and peer-review state.
struct GroupListView: View {
    let model: GroupBombModel
    let isSelected: Bool
    private let tutorialStep: Binding<TutorialStep?>?
    private let onReplayTutorial: (() -> Void)?
    private let onCreateGroupTutorialFrameChange: ((CGRect?) -> Void)?

    @State private var isAddGroupPresented = false
    @State private var enteredGroup: Group?
    @State private var animationSequence = 0

    init(
        model: GroupBombModel,
        isSelected: Bool = true,
        tutorialStep: Binding<TutorialStep?>? = nil,
        onReplayTutorial: (() -> Void)? = nil,
        onCreateGroupTutorialFrameChange: ((CGRect?) -> Void)? = nil
    ) {
        self.model = model
        self.isSelected = isSelected
        self.tutorialStep = tutorialStep
        self.onReplayTutorial = onReplayTutorial
        self.onCreateGroupTutorialFrameChange = onCreateGroupTutorialFrameChange
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ZStack {
                BombTheme.yellow.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        Text("選一組，繼續拆彈。")
                            .font(.subheadline.bold())

                        if model.groups.isEmpty {
                            emptyState
                        } else {
                            let activeGroups = groups(matching: { $0 == .active }, now: context.date)
                            let awaitingGroups = groups(matching: { $0.isAwaitingReview }, now: context.date)
                            let closedGroups = groups(matching: { $0 == .closed }, now: context.date)

                            groupSection(title: "進行中", groups: activeGroups, now: context.date)
                            groupSection(title: "待評分", groups: awaitingGroups, now: context.date)
                            groupSection(title: "已完成", groups: closedGroups, now: context.date)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("我的群組")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新增", systemImage: "plus") {
                    if tutorialStep?.wrappedValue == .createGroup {
                        tutorialStep?.wrappedValue = .createGroupForm
                    }
                    isAddGroupPresented = true
                }
                .accessibilityIdentifier("tutorial.createGroupButton")
            }

#if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                debugMenu
            }
#endif
        }
        .background {
            if tutorialStep?.wrappedValue == .createGroup {
                ToolbarTargetFrameReader(
                    identifier: "tutorial.createGroupButton",
                    accessibilityLabel: "新增"
                ) {
                    onCreateGroupTutorialFrameChange?($0)
                }
            }
        }
        .sheet(isPresented: $isAddGroupPresented, onDismiss: restoreCreateGroupTutorialIfNeeded) {
            AddGroupSheet(model: model) { group in
                enteredGroup = group
                if tutorialStep?.wrappedValue == .createGroupForm {
                    tutorialStep?.wrappedValue = .inviteCode
                }
            }
        }
        .navigationDestination(item: $enteredGroup) { group in
            GroupDetailView(group: group, model: model, tutorialStep: tutorialStep)
        }
        .task(id: isSelected) {
            guard isSelected else { return }
            animationSequence += 1
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 36, weight: .black))
            Text("還沒有群組")
                .font(.title3.weight(.black))
            Text("建立群組或輸入邀請碼加入")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    @ViewBuilder
    private func groupSection(title: String, groups: [Group], now: Date) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .black))

                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    let status = listStatus(for: group, now: now)
                    NavigationLink {
                        destination(for: group, status: status)
                    } label: {
                        GroupRow(
                            group: group,
                            status: status,
                            progress: model.projectProgress(for: group.id),
                            completedReviewerCount: model.completedPeerReviewerCount(in: group.id),
                            now: now,
                            animationDelay: Double(index) * 0.09,
                            animationSequence: animationSequence
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
        model.groups
            .filter { predicate(listStatus(for: $0, now: now)) }
            .sorted(by: { $0.deadline < $1.deadline })
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

    private func restoreCreateGroupTutorialIfNeeded() {
        if tutorialStep?.wrappedValue == .createGroupForm {
            tutorialStep?.wrappedValue = .createGroup
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
}

private struct AddGroupSheet: View {
    let model: GroupBombModel
    let enterGroup: (Group) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var flow = GroupEntryFlow.entry
    @State private var entryMode = GroupEntryMode.create
    @State private var groupName = ""
    @State private var groupDeadline = Date.now.addingTimeInterval(7 * 24 * 60 * 60)
    @State private var groupCode = ""
    @State private var createdGroup: Group?
    @State private var joinError: String?

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canJoin: Bool {
        !groupCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                switch flow {
                case .entry:
                    Form {
                        Section {
                            HStack(spacing: 12) {
                                entryButton(title: "建立群組", symbol: "plus", mode: .create)
                                entryButton(title: "加入群組", symbol: "person.badge.plus", mode: .join)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }

                        if entryMode == .create {
                            Section("群組名稱") {
                                TextField("輸入群組名稱", text: $groupName)
                            }
                            Section("群組期限") {
                                DatePicker(
                                    "截止時間",
                                    selection: $groupDeadline,
                                    in: Date.now...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                            }
                        } else {
                            Section("群組代碼") {
                                TextField("例如 GB-DEMO", text: $groupCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                            }
                        }
                    }
                case .shareCode:
                    VStack(spacing: 20) {
                        Text("分享這組代碼給隊友")
                            .font(.headline)
                        Text(createdGroup?.inviteCode ?? "")
                            .font(.system(.title, design: .monospaced, weight: .black))
                            .padding()
                            .background(BombTheme.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(flow == .entry ? "取消" : "上一步") {
                        if flow == .entry { dismiss() } else { flow = .entry }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("下一步", action: advance)
                        .disabled(!canAdvance)
                }
            }
        }
        .presentationDetents([.medium])
        .alert("無法加入群組", isPresented: Binding(
            get: { joinError != nil },
            set: { if !$0 { joinError = nil } }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(joinError ?? "")
        }
    }

    private var navigationTitle: String {
        switch flow {
        case .entry: "新增群組"
        case .shareCode: "群組代碼"
        }
    }

    private var canAdvance: Bool {
        switch flow {
        case .entry:
            entryMode == .create ? canCreate && groupDeadline > .now : canJoin
        case .shareCode:
            createdGroup != nil
        }
    }

    private func advance() {
        switch flow {
        case .entry:
            if entryMode == .create {
                model.createGroup(name: groupName, deadline: groupDeadline)
                createdGroup = model.groups.last
                flow = .shareCode
            } else {
                let normalizedCode = groupCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if model.joinGroup(inviteCode: normalizedCode),
                   let group = model.groups.first(where: { $0.inviteCode == normalizedCode }) {
                    enterGroup(group)
                    dismiss()
                } else {
                    joinError = "請確認群組代碼後再試一次。"
                }
            }
        case .shareCode:
            guard let createdGroup else { return }
            enterGroup(createdGroup)
            dismiss()
        }
    }

    private func entryButton(title: String, symbol: String, mode: GroupEntryMode) -> some View {
        let isSelected = entryMode == mode

        return Button {
            entryMode = mode
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.headline.bold())
                    .foregroundStyle(isSelected ? BombTheme.yellow : BombTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? BombTheme.ink : BombTheme.yellow.opacity(0.35))
                    .clipShape(Circle())
                Text(title)
                    .font(.subheadline.bold())
            }
            .foregroundStyle(BombTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? BombTheme.yellow : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : BombTheme.ink.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum GroupEntryFlow: Equatable {
    case entry
    case shareCode
}

private enum GroupEntryMode: Equatable {
    case create
    case join
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: Group
    let status: GroupListStatus
    let progress: Int
    let completedReviewerCount: Int
    let now: Date
    let animationDelay: TimeInterval
    let animationSequence: Int

    @State private var animatedProgress = 0

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

            ProgressView(value: Double(animatedProgress), total: 100)
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
        .task(id: animationSequence) {
            guard animationSequence > 0 else { return }
            animatedProgress = 0

            if reduceMotion {
                animatedProgress = progress
                return
            }

            try? await Task.sleep(for: .seconds(animationDelay + 0.06))
            guard !Task.isCancelled else {
                animatedProgress = progress
                return
            }
            withAnimation(.spring(duration: 0.75, bounce: 0.08)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newProgress in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) {
                animatedProgress = newProgress
            }
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
