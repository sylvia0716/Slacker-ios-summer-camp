import SwiftUI
import OSLog

/// 群組聊天室畫面；完整時間軸由 AppStore 依群組保存至裝置本機。
struct ChatRoomView: View {
    private static let bottomAnchorID = "chat-room-bottom"
    private static let aiLogger = Logger(subsystem: "con.sylvia.group", category: "AppleIntelligence")

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let model: GroupBombModel
    let group: Group
    private let tutorialStep: Binding<TutorialStep?>?

    @State private var draft = ""
    @State private var showsShortcuts = false
    @State private var isAIResponding = false
    @State private var isAwayFromLatest = false
    @State private var pinnedScrollTargetID: String?
    @FocusState private var isComposerFocused: Bool

    init(
        model: GroupBombModel,
        group: Group,
        tutorialStep: Binding<TutorialStep?>? = nil
    ) {
        self.model = model
        self.group = group
        self.tutorialStep = tutorialStep
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                memberStatus
                pinnedMessageBar

                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(model.chatItems(for: group.id)) { item in
                                    chatItem(item)
                                        .id(item.id)
                                        .contextMenu {
                                            if let message = pinnableMessage(for: item) {
                                                let isPinned = model.pinnedChatMessageByGroupID[group.id]?.id == item.id
                                                Button(L10n.text(isPinned ? "取消置頂" : "置頂訊息"),
                                                       systemImage: isPinned ? "pin.slash" : "pin") {
                                                    model.setPinnedChatMessage(
                                                        isPinned ? nil : message, groupID: group.id
                                                    )
                                                }
                                            }
                                        }
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id(Self.bottomAnchorID)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isComposerFocused = false
                        }
                        .onAppear {
                            scrollToBottom(using: proxy, animated: false)
                        }
                        .onScrollGeometryChange(for: Bool.self, of: { geometry in
                            geometry.contentSize.height - geometry.visibleRect.maxY > 80
                        }) { _, isAway in
                            withAnimation(.snappy) {
                                isAwayFromLatest = isAway
                            }
                        }
                        .onChange(of: model.chatItems(for: group.id).count) {
                            guard !isAwayFromLatest else { return }
                            scrollToBottom(using: proxy)
                        }
                        .onChange(of: model.isChatMessageSyncReady(for: group.id)) { _, isReady in
                            guard isReady else { return }
                            scrollToBottom(using: proxy, animated: false)
                        }
                        .onChange(of: isComposerFocused) { _, isFocused in
                            guard isFocused else { return }
                            scrollToBottom(using: proxy)
                        }
                        .onChange(of: pinnedScrollTargetID) { _, targetID in
                            guard let targetID else { return }
                            withAnimation(.snappy) { proxy.scrollTo(targetID, anchor: .center) }
                            pinnedScrollTargetID = nil
                        }

                        if isAwayFromLatest {
                            Button {
                                scrollToBottom(using: proxy)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(BombTheme.ink)
                                    .frame(width: 44, height: 44)
                                    .background(BombTheme.paper)
                                    .clipShape(.circle)
                                    .overlay(Circle().stroke(BombTheme.ink, lineWidth: 2))
                                    .shadow(color: BombTheme.ink.opacity(0.18), radius: 6, y: 3)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel(L10n.text("回到最新訊息"))
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .bombTabBarHidden()
        .onAppear {
            if tutorialStep?.wrappedValue == .chatEntry {
                tutorialStep?.wrappedValue = .aiChat
            }
        }
        .task(id: group.id) {
            await model.startChatSync(groupID: group.id, displayName: model.profileName)
        }
        .onChange(of: scenePhase) { _, phase in
            model.updateChatPresence(
                groupID: group.id,
                displayName: model.profileName,
                isOnline: phase == .active
            )
            if phase == .active { model.markLatestChatMessageRead(groupID: group.id) }
        }
        .onChange(of: model.cloudChatMessageIDsByGroupID[group.id]?.last) {
            guard scenePhase == .active else { return }
            model.markLatestChatMessageRead(groupID: group.id)
        }
        .onDisappear {
            model.stopChatSync(groupID: group.id, displayName: model.profileName)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var topBar: some View {
        BombHeader(title: group.name, wrapsTitle: true) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(BombHeaderButtonStyle())
            .accessibilityLabel(L10n.text("返回群組"))
        } trailing: {
            EmptyView()
        }
    }

    private var memberStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(onlineMembers.isEmpty ? BombTheme.ink.opacity(0.3) : BombTheme.green)
                    .frame(width: 9, height: 9)
                Text(L10n.format("{0} 人在線", String(describing: onlineMembers.count)))
                    .font(.caption.weight(.black))

                if !onlineMembers.isEmpty {
                    ScrollView(.horizontal) {
                        Text(onlineMembers.map(\.displayName).joined(separator: "、"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.65))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scrollIndicators(.hidden)
                } else {
                    Spacer()
                }

                Text(L10n.text("今天"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BombTheme.ink.opacity(0.6))
            }

            if let syncError = model.chatMessageSyncError(for: group.id) {
                Label(L10n.format("訊息同步：{0}", String(describing: syncError)), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BombTheme.red)
                    .lineLimit(2)
            }

            if let syncError = model.chatPresenceSyncError(for: group.id) {
                Label(L10n.format("在線狀態：{0}", String(describing: syncError)), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BombTheme.red)
                    .lineLimit(2)
            }

            if let syncError = model.chatReadSyncErrorsByGroupID[group.id] {
                Label(L10n.format("已讀同步：{0}", String(describing: syncError)), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BombTheme.red)
                    .lineLimit(2)
            }

            if let syncError = model.chatPinSyncErrorsByGroupID[group.id] {
                Label(L10n.format("置頂同步：{0}", String(describing: syncError)), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BombTheme.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BombTheme.paper)
    }

    private var onlineMembers: [ChatPresence] {
        model.onlineMembers(for: group.id)
    }

    @ViewBuilder
    private var pinnedMessageBar: some View {
        if let message = model.pinnedChatMessageByGroupID[group.id] {
            HStack(spacing: 8) {
                Button {
                    pinnedScrollTargetID = message.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.senderName).font(.caption2.weight(.black))
                            Text(message.text).font(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(BombTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.format("跳到置頂訊息：{0}", String(describing: message.text)))

                Button {
                    model.setPinnedChatMessage(nil, groupID: group.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.black))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("取消置頂訊息"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(BombTheme.paper)
        }
    }

    private func pinnableMessage(for item: ChatRoomItem) -> ChatPinnedMessage? {
        switch item {
        case let .message(id, sender, text, _, _, _, deliveryState):
            guard deliveryState == .sent else { return nil }
            return ChatPinnedMessage(messageID: id, senderName: sender, text: text)
        case let .botReply(id, text, _):
            return ChatPinnedMessage(messageID: id, senderName: "拆彈 AI 通訊官", text: text)
        case let .botAnalysis(id, analysis):
            return ChatPinnedMessage(messageID: id, senderName: "拆彈 AI 通訊官", text: analysis.summary)
        case .agendaReminder, .systemEvent:
            return nil
        }
    }

    @ViewBuilder
    private func chatItem(_ item: ChatRoomItem) -> some View {
        switch item {
        case let .message(id, sender, text, time, isCurrentUser, _, deliveryState):
            messageBubble(
                id: id,
                sender: sender,
                text: text,
                time: time,
                isCurrentUser: isCurrentUser,
                deliveryState: deliveryState
            )
        case let .systemEvent(_, icon, text, _):
            Label(text, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(BombTheme.ink.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(BombTheme.paper)
                .clipShape(.capsule)
                .frame(maxWidth: .infinity)
        case let .botAnalysis(_, analysis):
            ChatBotAnalysisCard(analysis: analysis)
        case let .botReply(_, text, createdAt):
            ChatBotReplyBubble(text: text, createdAt: createdAt)
        case let .agendaReminder(_, summary, createdAt):
            ChatBotReplyBubble(text: summary.localizedText, createdAt: createdAt,
                               title: L10n.text("自動化議程"), icon: "list.bullet.rectangle")
        }
    }

    private func messageBubble(
        id: String,
        sender: String,
        text: String,
        time: String,
        isCurrentUser: Bool,
        deliveryState: ChatMessageDeliveryState
    ) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 42) }

            if !isCurrentUser { avatar(for: sender, messageID: id) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(sender)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BombTheme.ink.opacity(0.62))

                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrentUser ? Color.white : BombTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(isCurrentUser ? BombTheme.ink : BombTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        if !isCurrentUser {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(BombTheme.ink, lineWidth: 2)
                        }
                    }

                if isCurrentUser, deliveryState != .sent {
                    messageDeliveryStatus(id: id, text: text, deliveryState: deliveryState)
                } else {
                    HStack(spacing: 6) {
                        Text(time)
                        if isCurrentUser {
                            let count = model.readCount(for: id, in: group.id)
                            if count > 0 { Text(L10n.format("已讀 {0}", String(describing: count))) }
                        }
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BombTheme.ink.opacity(0.5))
                }
            }

            if !isCurrentUser { Spacer(minLength: 42) }
        }
    }

    @ViewBuilder
    private func messageDeliveryStatus(
        id: String,
        text: String,
        deliveryState: ChatMessageDeliveryState
    ) -> some View {
        switch deliveryState {
        case .sending:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(L10n.text("傳送中"))
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(BombTheme.ink.opacity(0.55))
        case .failed:
            Button {
                retryMessage(id: id, text: text)
            } label: {
                Label(L10n.text("傳送失敗・重試"), systemImage: "arrow.clockwise")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BombTheme.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("訊息傳送失敗，點兩下重試"))
        case .sent:
            EmptyView()
        }
    }

    private func avatar(for name: String, messageID: String) -> some View {
        MemberPhotoAvatar(
            groupID: group.firestoreDocumentID,
            uid: model.chatSenderIDsByGroupID[group.id]?[messageID],
            name: name
        )
        .accessibilityHidden(true)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if isAIResponding {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(BombTheme.ink)
                    Text(L10n.text("Apple Intelligence 思考中…"))
                        .font(.caption.weight(.black))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            if showsShortcuts {
                ChatShortcutBar(onSelect: sendShortcut)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) { showsShortcuts.toggle() }
                } label: {
                    Image(systemName: showsShortcuts ? "xmark" : "plus")
                        .font(.headline.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .frame(width: 42, height: 42)
                        .background(BombTheme.paper)
                        .clipShape(.circle)
                        .overlay(Circle().stroke(BombTheme.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsShortcuts ? L10n.text("收起快捷指令") : L10n.text("展開快捷指令"))

                TextField(L10n.text("輸入訊息"), text: $draft, axis: .vertical)
                    .focused($isComposerFocused)
                    .lineLimit(1...3)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(BombTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BombTheme.ink, lineWidth: 2)
                    }

                Button(action: sendDraft) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(BombTheme.ink)
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel(L10n.text("發送訊息"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(BombTheme.yellow)
        .tutorialTarget(
            .chatInput,
            enabled: tutorialStep?.wrappedValue == .aiChat
        )
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let conversation = model.chatItems(for: group.id).compactMap(\.humanConversationLine)
        draft = ""

        Task { @MainActor in
            guard await sendCloudMessage(text) else { return }
            guard let command = botCommand(in: text) else { return }
            await handleBotCommand(command, conversation: conversation)
        }
    }

    /// 同時支援半形與全形 @，讓直接輸入提及和快捷按鈕採用相同 AI 流程。
    private func botCommand(in text: String) -> String? {
        let prefixes = ["@機器人", "＠機器人", "@bot", "＠bot", "@Bomb AI"]
        guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else { return nil }
        return String(text.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleBotCommand(_ command: String, conversation: [String]) async {
        guard !isAIResponding else {
            await appendBotReply(L10n.text("我正在處理上一個請求，請稍後再試一次。"))
            return
        }

        guard !command.isEmpty else {
            await appendBotReply(L10n.text("請問需要我幫忙什麼？你可以輸入「@機器人 你的問題」。"))
            return
        }

        if ["分析溝通", "分析專案", "analyze communication", "analyze project"].contains(where: { command.lowercased().contains($0) }) {
            guard conversation.count >= 2 else {
                await appendBotReply(L10n.text("目前對話還不足以分析溝通狀況，請先讓成員進行一些討論。"))
                return
            }
            await requestAIProjectAnalysis(conversation: conversation)
            return
        }

        let queryPrefix = ["幫我們查詢", "Help us look this up"].first(where: { command.hasPrefix($0) })
        let explicitQuestion: String
        if let queryPrefix {
            explicitQuestion = String(command.dropFirst(queryPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            explicitQuestion = command
        }

        if explicitQuestion.isEmpty {
            guard let latestMessage = conversation.last else {
                await appendBotReply(L10n.text("請問需要我幫忙查什麼？請在 @機器人 後面輸入問題。"))
                return
            }
            await requestAIAnswer(question: latestMessage, conversation: conversation)
        } else {
            await requestAIAnswer(question: explicitQuestion, conversation: conversation)
        }
    }

    /// 等待鍵盤造成的版面更新套用後，再將最新訊息對齊聊天室底部。
    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        Task { @MainActor in
            await Task.yield()
            if animated {
                withAnimation(.snappy) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func sendShortcut(_ shortcut: ChatShortcut) {
        guard !isAIResponding else { return }
        let conversation = model.chatItems(for: group.id).compactMap(\.humanConversationLine)
        withAnimation(.snappy) { showsShortcuts = false }

        Task { @MainActor in
            guard await sendCloudMessage(shortcut.command) else { return }
            switch shortcut {
            case .query:
                guard let latestMessage = conversation.last else {
                    await appendBotReply(L10n.text("請問需要我幫忙查什麼？請先在聊天室描述問題，再點一次「幫我們查詢」。"))
                    return
                }
                await requestAIAnswer(question: latestMessage, conversation: conversation)
            case .analyze:
                guard conversation.count >= 2 else {
                    await appendBotReply(L10n.text("目前對話還不足以分析溝通狀況，請先讓成員進行一些討論。"))
                    return
                }
                await requestAIProjectAnalysis(conversation: conversation)
            }
        }
    }

    private func sendCloudMessage(_ text: String) async -> Bool {
        let messageID = UUID().uuidString.lowercased()
        model.appendChatItem(
            .message(
                id: messageID,
                sender: model.profileName,
                text: text,
                time: Date.now.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)),
                isCurrentUser: true,
                createdAt: .now,
                deliveryState: .sending
            ),
            to: group.id
        )
        let didSend = await model.sendChatMessage(
            id: messageID,
            text: text,
            groupID: group.id,
            displayName: model.profileName
        )
        model.updateChatMessageDeliveryState(
            id: messageID,
            groupID: group.id,
            deliveryState: didSend ? .sent : .failed
        )
        return didSend
    }

    private func retryMessage(id: String, text: String) {
        model.updateChatMessageDeliveryState(
            id: id,
            groupID: group.id,
            deliveryState: .sending
        )

        Task { @MainActor in
            let didSend = await model.sendChatMessage(
                id: id,
                text: text,
                groupID: group.id,
                displayName: model.profileName
            )
            model.updateChatMessageDeliveryState(
                id: id,
                groupID: group.id,
                deliveryState: didSend ? .sent : .failed
            )

            guard didSend, let command = botCommand(in: text) else { return }
            let conversation = model.chatItems(for: group.id).compactMap(\.humanConversationLine)
            await handleBotCommand(command, conversation: conversation)
        }
    }

    private func requestAIAnswer(question: String, conversation: [String]) async {
        isAIResponding = true
        defer { isAIResponding = false }
        do {
            let answer = try await AppleIntelligenceService().answer(
                question: question,
                conversation: conversation
            )
            await appendBotReply(answer)
        } catch {
            #if DEBUG
            Self.aiLogger.error(
                "Answer request failed:\n\(AppleIntelligenceDiagnostics.description(of: error), privacy: .public)"
            )
            #endif
            await appendBotReply(aiErrorMessage(error))
        }
    }

    private func requestAIProjectAnalysis(conversation: [String]) async {
        isAIResponding = true
        defer { isAIResponding = false }
        do {
            let generated = try await AppleIntelligenceService()
                .analyzeProject(
                    groupName: group.name,
                    groupDeadline: group.deadline,
                    tasks: model.projectTasks.filter { $0.groupID == group.id },
                    members: model.members.filter { group.memberIDs.contains($0.id) },
                    conversation: conversation
                )
            let analysis = model.saveCommunicationAnalysis(
                groupID: group.id,
                generated: generated
            )
            let analysisID = analysis.id.uuidString.lowercased()
            model.appendChatItem(
                .botAnalysis(id: analysisID, analysis: analysis),
                to: group.id
            )
            _ = await model.sendChatBotAnalysis(
                id: analysisID,
                analysis: analysis,
                groupID: group.id
            )
        } catch {
            #if DEBUG
            Self.aiLogger.error(
                "Analysis request failed:\n\(AppleIntelligenceDiagnostics.description(of: error), privacy: .public)"
            )
            #endif
            await appendBotReply(aiErrorMessage(error))
        }
    }

    private func appendBotReply(_ text: String) async {
        let replyID = UUID().uuidString.lowercased()
        model.appendChatItem(
            .botReply(id: replyID, text: text, createdAt: .now),
            to: group.id
        )
        _ = await model.sendChatBotReply(
            id: replyID,
            text: text,
            groupID: group.id
        )
    }

    private func aiErrorMessage(_ error: Error) -> String {
        if let serviceError = error as? AppleIntelligenceServiceError {
            return serviceError.localizedDescription
        }
        return L10n.text("Apple Intelligence 暫時無法完成這次請求，請稍後再試。")
    }
}

/// 可收起的聊天室機器人快捷指令；未來可在此增加查資料、建立任務等功能。
private enum ChatShortcut: CaseIterable, Identifiable {
    case query
    case analyze

    var id: Self { self }

    var command: String {
        switch self {
        case .query: L10n.text("@機器人 幫我們查詢")
        case .analyze: L10n.text("@機器人 分析專案")
        }
    }

    var icon: String {
        switch self {
        case .query: "magnifyingglass"
        case .analyze: "sparkles"
        }
    }
}

private struct ChatShortcutBar: View {
    let onSelect: (ChatShortcut) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ChatShortcut.allCases) { shortcut in
                    Button { onSelect(shortcut) } label: {
                        Label(shortcut.command, systemImage: shortcut.icon)
                            .font(.caption.weight(.black))
                            .foregroundStyle(BombTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(BombTheme.paper)
                            .clipShape(.capsule)
                            .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// 聊天室內的 AI 回覆卡；完整報告可在專案結算查看。
private struct ChatBotAnalysisCard: View {
    let analysis: CommunicationAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.text("拆彈 AI 通訊官"), systemImage: "sparkles")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text(L10n.format("{0} 分", String(describing: analysis.score)))
                    .font(.headline.monospacedDigit().weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
            }
            Text(analysis.summary)
                .font(.subheadline.weight(.semibold))
            Text(L10n.text("完整報告可至專案結算的「戰力報告」查看。"))
                .font(.caption.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.65))
            Text(analysis.updatedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .comicCard()
        .accessibilityElement(children: .combine)
    }
}

/// 一般查詢指令的機器人回覆泡泡。
private struct ChatBotReplyBubble: View {
    let text: String
    let createdAt: Date
    var title: String? = nil
    var icon = "sparkles"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(BombTheme.yellow)
                .frame(width: 32, height: 32)
                .background(BombTheme.ink)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title ?? L10n.text("拆彈 AI 通訊官"))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BombTheme.ink.opacity(0.62))

                Text(displayText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BombTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(BombTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(BombTheme.ink, lineWidth: 2)
                    }

                Text(createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BombTheme.ink.opacity(0.5))
            }
            Spacer(minLength: 42)
        }
        .accessibilityElement(children: .combine)
    }

    /// 舊 AI 回覆可能包含 Markdown 標記；保留項目符號但不直接顯示星號語法。
    private var displayText: String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "* ", with: "• ")
            .replacingOccurrences(of: "*", with: "")
    }
}

#Preview("Chat room") {
    @Previewable @State var model = AppStore(dataMode: .demo)
    NavigationStack {
        if let group = model.groups.first {
            ChatRoomView(model: model, group: group)
        }
    }
}
