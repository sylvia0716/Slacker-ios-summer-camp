import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// First tab: groups projects by their deadline and peer-review state.
struct GroupListView: View {
    let model: GroupBombModel
    let isSelected: Bool
    private let tutorialStep: Binding<TutorialStep?>?
    private let onReplayTutorial: (() -> Void)?

    @State private var isAddGroupPresented = false
    @State private var addGroupInitialMode = GroupEntryMode.create
    @State private var enteredGroup: Group?
    @State private var animationSequence = 0
    @State private var joinSuccessMessage: String?

    init(
        model: GroupBombModel,
        isSelected: Bool = true,
        tutorialStep: Binding<TutorialStep?>? = nil,
        onReplayTutorial: (() -> Void)? = nil
    ) {
        self.model = model
        self.isSelected = isSelected
        self.tutorialStep = tutorialStep
        self.onReplayTutorial = onReplayTutorial
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ZStack {
                BombTheme.yellow.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if model.groups.isEmpty {
                            emptyState
                        } else {
                            Text("選一組，繼續拆彈。")
                                .font(.subheadline.bold())

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
        .refreshable { await model.reloadCloudGroups() }
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: "我的群組") {
#if DEBUG
                debugMenu
                    .buttonStyle(BombHeaderButtonStyle())
#else
                EmptyView()
#endif
            } trailing: {
                Button("新增", systemImage: "plus") {
                    if tutorialStep?.wrappedValue == .createGroup {
                        tutorialStep?.wrappedValue = .createGroupForm
                    }
                    presentAddGroup(mode: .create)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityIdentifier("tutorial.createGroupButton")
                .tutorialTarget(
                    .createGroupButton,
                    enabled: tutorialStep?.wrappedValue == .createGroup
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddGroupPresented, onDismiss: restoreCreateGroupTutorialIfNeeded) {
            AddGroupSheet(
                model: model,
                initialMode: addGroupInitialMode,
                enterGroup: { group in
                    enteredGroup = group
                    if tutorialStep?.wrappedValue == .createGroupForm {
                        tutorialStep?.wrappedValue = .inviteCode
                    }
                },
                joinedGroup: { message in
                    joinSuccessMessage = message
                }
            )
        }
        .navigationDestination(item: $enteredGroup) { group in
            GroupDetailView(group: group, model: model, tutorialStep: tutorialStep)
        }
        .task(id: isSelected) {
            guard isSelected else { return }
            animationSequence += 1
        }
        .bombDialog("加入群組", isPresented: Binding(
            get: { joinSuccessMessage != nil && !isAddGroupPresented },
            set: { if !$0 { joinSuccessMessage = nil } }
        )) {
            Button("知道了") { }
        } message: {
            Text(joinSuccessMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 36, weight: .black))
            Text("還沒有群組")
                .font(.title3.weight(.black))
            Text("建立自己的群組，或使用邀請碼加入")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.65))

            VStack(spacing: 12) {
                Button {
                    presentAddGroup(mode: .create)
                } label: {
                    Label("建立群組", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GroupEntryActionButtonStyle(isPrimary: true))

                Button {
                    presentAddGroup(mode: .join)
                } label: {
                    Label("輸入邀請碼", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GroupEntryActionButtonStyle(isPrimary: false))
            }
            .containerRelativeFrame(.horizontal) { width, _ in width * 0.66 }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private func presentAddGroup(mode: GroupEntryMode) {
        addGroupInitialMode = mode
        isAddGroupPresented = true
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
            Image(systemName: "wrench.and.screwdriver.fill")
        }
        .accessibilityLabel("測試工具")
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
    let joinedGroup: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var flow = GroupEntryFlow.entry
    @State private var entryMode: GroupEntryMode
    @State private var groupName = ""
    @State private var groupDeadline = Date.now.addingTimeInterval(7 * 24 * 60 * 60)
    @State private var groupCode = ""
    @State private var createdGroup: Group?
    @State private var joinError: String?
    @State private var joinStore = GroupJoinStore()
    @State private var isCreating = false
    @State private var creationError: String?
    @State private var isScannerPresented = false
    @State private var isScannerUnavailableAlertPresented = false
    @State private var showsCodeCopiedFeedback = false
    @FocusState private var isCodeFieldFocused: Bool

    init(
        model: GroupBombModel,
        initialMode: GroupEntryMode,
        enterGroup: @escaping (Group) -> Void,
        joinedGroup: @escaping (String) -> Void
    ) {
        self.model = model
        self.enterGroup = enterGroup
        self.joinedGroup = joinedGroup
        _entryMode = State(initialValue: initialMode)
    }

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canJoin: Bool {
        GroupInviteCode.isValid(groupCode)
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                switch flow {
                case .entry:
                    ScrollView {
                        VStack(spacing: 24) {
                            entryModePicker

                            if entryMode == .create {
                                createGroupForm
                            } else {
                                joinGroupForm
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .disabled(isBusy)
                case .shareCode:
                    shareCodeView
                }
            }
            .background(BombTheme.paper)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(flow == .entry ? "取消" : "上一步") {
                        if flow == .entry { dismiss() } else { flow = .entry }
                    }
                    .disabled(isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryButtonTitle, action: advance)
                        .disabled(!canAdvance || isBusy)
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .presentationDetents([.fraction(0.62)])
        .presentationDragIndicator(.visible)
        .presentationBackground(BombTheme.paper)
        .bombDialog("無法加入群組", isPresented: Binding(
            get: {
                if joinError != nil { return true }
                if case .failure = joinStore.state { return true }
                return false
            },
            set: { if !$0 { joinStore.reset(); joinError = nil } }
        )) {
            Button("知道了") { }
        } message: {
            if let joinError {
                Text(joinError)
            } else if case let .failure(error) = joinStore.state {
                Text(error.localizedDescription)
            }
        }
        .bombDialog("無法建立群組", isPresented: Binding(
            get: { creationError != nil },
            set: { if !$0 { creationError = nil } }
        )) {
            Button("知道了") { }
        } message: {
            Text(creationError ?? "")
        }
        .onChange(of: entryMode) { _, mode in
            if mode == .join {
                isCodeFieldFocused = true
            }
        }
        .bombDialog("無法使用掃碼", isPresented: $isScannerUnavailableAlertPresented) {
            Button("知道了") { }
        } message: {
            Text("請在支援相機文字辨識的裝置上使用掃碼功能。")
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            GroupCodeScanner(onRecognized: { scannedCode in
                groupCode = GroupInviteCode.normalized(scannedCode)
                isScannerPresented = false
            }, onFailure: { message in
                isScannerPresented = false
                joinError = message
            })
        }
    }

    private var entryModePicker: some View {
        HStack(spacing: 4) {
            entryButton(title: "建立群組", mode: .create)
            entryButton(title: "加入群組", mode: .join)
        }
        .padding(4)
        .background(BombTheme.ink)
        .clipShape(.capsule)
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.66 }
    }

    private var createGroupForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("群組名稱")
                .font(.headline.weight(.black))

            TextField("例如：期末報告拆彈小隊", text: $groupName)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(BombTheme.yellow.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("截止時間")
                .font(.headline.weight(.black))
                .padding(.top, 10)

            DatePicker(
                "截止時間",
                selection: $groupDeadline,
                in: Date.now...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.66 }
    }

    private var joinGroupForm: some View {
        VStack(spacing: 16) {
            Text("6 位邀請碼")
                .font(.title3.weight(.black))

            inviteCodeBoxes

            Rectangle()
                .stroke(BombTheme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .frame(height: 1)

            Button {
                if GroupCodeScanner.isAvailable {
                    isScannerPresented = true
                } else {
                    isScannerUnavailableAlertPresented = true
                }
            } label: {
                Image(systemName: "viewfinder")
                    .font(.title2.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .frame(width: 50, height: 50)
                    .background(BombTheme.yellow.opacity(0.22))
                    .clipShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("掃描邀請碼")

            Text("輸入隊友分享的邀請碼")
                .font(.caption.weight(.bold))
        }
        .padding(18)
        .background(BombTheme.yellow.opacity(0.08))
        .clipShape(PostageTicketShape())
        .overlay {
            PostageTicketShape()
                .stroke(BombTheme.ink, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.66 }
    }

    private var inviteCodeBoxes: some View {
        let characters = Array(groupCode.uppercased())

        return ZStack {
            HStack(spacing: 5) {
                ForEach(0..<6, id: \.self) { index in
                    Text(index < characters.count ? String(characters[index]) : "")
                        .font(.system(.title2, design: .monospaced, weight: .black))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(BombTheme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(BombTheme.ink.opacity(0.18), lineWidth: 1.5)
                        }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            TextField("", text: $groupCode)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.join)
                .onSubmit(submitInviteCode)
                .focused($isCodeFieldFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(Rectangle())
                .onTapGesture { isCodeFieldFocused = true }
                .accessibilityLabel("6 位邀請碼")
                .onChange(of: groupCode) { _, newValue in
                    groupCode = normalizedInviteCode(newValue)
                }
        }
    }

    @ViewBuilder
    private var shareCodeView: some View {
        if let createdGroup {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Text("分享給隊友")
                        .font(.headline.weight(.black))

                    if let image = qrCodeImage(for: createdGroup.inviteCode) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 132, height: 132)
                            .accessibilityLabel("群組邀請碼 QR Code")
                    }

                    Text(createdGroup.inviteCode)
                        .font(.system(.title2, design: .monospaced, weight: .black))
                        .textSelection(.enabled)

                    Rectangle()
                        .stroke(BombTheme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(height: 1)

                    HStack(spacing: 10) {
                        Button {
                            copyInviteCode(createdGroup.inviteCode)
                        } label: {
                            Label(
                                showsCodeCopiedFeedback ? "已複製" : "複製代碼",
                                systemImage: showsCodeCopiedFeedback ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(ShareCodeButtonStyle(isPrimary: true))

                        ShareLink(item: shareMessage(for: createdGroup)) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ShareCodeButtonStyle(isPrimary: false))
                    }
                }
                .padding(18)
                .background(BombTheme.yellow.opacity(0.08))
                .clipShape(PostageTicketShape())
                .overlay {
                    PostageTicketShape()
                        .stroke(BombTheme.ink, lineWidth: 2)
                }
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.66 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 12)
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

    private var isBusy: Bool {
        isCreating || joinStore.isJoining
    }

    private var primaryButtonTitle: String {
        if isCreating { return "建立中…" }
        if joinStore.isJoining { return "加入中…" }
        return flow == .entry ? "完成" : "稍後分享"
    }

    private func advance() {
        guard canAdvance, !isBusy else { return }
        isCodeFieldFocused = false
        switch flow {
        case .entry:
            if entryMode == .create {
                submitCreateGroup()
            } else {
                submitInviteCode()
            }
        case .shareCode:
            guard let createdGroup else { return }
            enterGroup(createdGroup)
            dismiss()
        }
    }

    private func submitCreateGroup() {
        guard canCreate, groupDeadline > .now, !isBusy else { return }
        if model.isDemoMode {
            model.createGroup(name: groupName, deadline: groupDeadline)
            createdGroup = model.groups.last
            flow = .shareCode
            return
        }

        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                createdGroup = try await model.createCloudGroup(
                    name: groupName,
                    deadline: groupDeadline
                )
                flow = .shareCode
            } catch {
                creationError = error.localizedDescription
            }
        }
    }

    private func submitInviteCode() {
        guard canJoin, !isBusy else { return }
        isCodeFieldFocused = false
        let normalizedCode = GroupJoinRepository.normalize(groupCode)
        groupCode = normalizedCode

        Task {
            guard let result = await joinStore.join(inviteCode: normalizedCode) else { return }
            guard model.acceptJoinedGroup(result) else { return }
            let successMessage = model.lastEvent
            dismiss()
            let refreshed = await model.reloadCloudGroups(reportError: false)
            guard model.firebaseUID == result.firebaseUID else { return }
            joinedGroup(refreshed ? successMessage : successMessage + "，但列表更新失敗，請下拉重新整理。")
        }
    }

    private func entryButton(title: String, mode: GroupEntryMode) -> some View {
        let isSelected = entryMode == mode

        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                entryMode = mode
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.black))
            .foregroundStyle(isSelected ? BombTheme.ink : BombTheme.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? BombTheme.yellow : Color.clear)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func normalizedInviteCode(_ value: String) -> String {
        String(GroupInviteCode.normalized(value).prefix(6))
    }

    private func qrCodeImage(for code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        ) else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.string = code
        withAnimation(.snappy) {
            showsCodeCopiedFeedback = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) {
                showsCodeCopiedFeedback = false
            }
        }
    }

    private func shareMessage(for group: Group) -> String {
        "加入「\(group.name)」群組，邀請碼：\(group.inviteCode)"
    }
}

private struct ShareCodeButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.black))
            .foregroundStyle(isPrimary ? BombTheme.paper : BombTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isPrimary ? BombTheme.ink : BombTheme.paper)
            .clipShape(.capsule)
            .overlay {
                Capsule().stroke(BombTheme.ink, lineWidth: isPrimary ? 0 : 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct GroupEntryActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(isPrimary ? BombTheme.paper : BombTheme.ink)
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(isPrimary ? BombTheme.ink : BombTheme.paper)
            .clipShape(.capsule)
            .overlay {
                Capsule().stroke(BombTheme.ink, lineWidth: isPrimary ? 0 : 2)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

private struct PostageTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 14
        let notchRadius: CGFloat = 9
        let middleY = rect.midY
        var path = Path()

        path.move(to: CGPoint(x: cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: middleY - notchRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX, y: middleY),
            radius: notchRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-270),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: middleY + notchRadius))
        path.addArc(
            center: CGPoint(x: rect.minX, y: middleY),
            radius: notchRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(-90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
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
