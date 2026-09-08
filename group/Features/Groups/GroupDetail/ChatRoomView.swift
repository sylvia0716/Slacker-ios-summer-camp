import SwiftUI

/// 群組聊天室畫面；完整時間軸由 AppStore 依群組保存至裝置本機。
struct ChatRoomView: View {
    private static let bottomAnchorID = "chat-room-bottom"

    @Environment(\.dismiss) private var dismiss
    let model: GroupBombModel
    let group: Group
    private let tutorialStep: Binding<TutorialStep?>?

    @State private var draft = ""
    @State private var showsShortcuts = false
    @State private var isAIResponding = false
    @State private var isAwayFromLatest = false
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

                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(model.chatItems(for: group.id)) { item in
                                    chatItem(item)
                                        .id(item.id)
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
                        .onChange(of: isComposerFocused) { _, isFocused in
                            guard isFocused else { return }
                            scrollToBottom(using: proxy)
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
                            .accessibilityLabel("回到最新訊息")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if tutorialStep?.wrappedValue == .chatEntry {
                tutorialStep?.wrappedValue = .aiChat
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(BombTheme.paper)
                    .clipShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回群組")

            VStack(alignment: .leading, spacing: 2) {
                Text("小隊聊天室")
                    .font(.system(.title3, design: .rounded, weight: .black))
                Text(group.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title3.weight(.black))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var memberStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(BombTheme.green)
                .frame(width: 9, height: 9)
            Text("\(group.memberIDs.count) 位群組成員")
                .font(.caption.weight(.black))
            Spacer()
            Text("今天")
                .font(.caption.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BombTheme.paper.opacity(0.75))
    }

    @ViewBuilder
    private func chatItem(_ item: ChatRoomItem) -> some View {
        switch item {
        case let .message(_, sender, text, time, isCurrentUser):
            messageBubble(sender: sender, text: text, time: time, isCurrentUser: isCurrentUser)
        case let .systemEvent(_, icon, text):
            Label(text, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(BombTheme.ink.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(BombTheme.paper.opacity(0.8))
                .clipShape(.capsule)
                .frame(maxWidth: .infinity)
        case let .botAnalysis(_, analysis):
            ChatBotAnalysisCard(analysis: analysis)
        case let .botReply(_, text):
            ChatBotReplyBubble(text: text)
        }
    }

    private func messageBubble(sender: String, text: String, time: String, isCurrentUser: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 42) }

            if !isCurrentUser { avatar(for: sender) }

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

                Text(time)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BombTheme.ink.opacity(0.5))
            }

            if !isCurrentUser { Spacer(minLength: 42) }
        }
    }

    private func avatar(for name: String) -> some View {
        ZStack {
            Circle().fill(BombTheme.ink)
            Text(String(name.prefix(1)))
                .font(.caption.weight(.black))
                .foregroundStyle(BombTheme.yellow)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if isAIResponding {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(BombTheme.ink)
                    Text("Apple Intelligence 思考中…")
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
                .accessibilityLabel(showsShortcuts ? "收起快捷指令" : "展開快捷指令")

                TextField("輸入訊息", text: $draft, axis: .vertical)
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
                .accessibilityLabel("發送訊息")
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

        model.appendChatItem(
            .message(
                id: UUID().uuidString,
                sender: "我",
                text: text,
                time: Date.now.formatted(date: .omitted, time: .shortened),
                isCurrentUser: true
            ),
            to: group.id
        )
        draft = ""

        guard let command = botCommand(in: text) else { return }
        handleBotCommand(command, conversation: conversation)
    }

    /// 同時支援半形與全形 @，讓直接輸入提及和快捷按鈕採用相同 AI 流程。
    private func botCommand(in text: String) -> String? {
        let prefixes = ["@機器人", "＠機器人"]
        guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else { return nil }
        return String(text.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleBotCommand(_ command: String, conversation: [String]) {
        guard !isAIResponding else {
            appendBotReply("我正在處理上一個請求，請稍後再試一次。")
            return
        }

        guard !command.isEmpty else {
            appendBotReply("請問需要我幫忙什麼？你可以輸入「@機器人 你的問題」。")
            return
        }

        if command.contains("分析溝通") {
            guard conversation.count >= 2 else {
                appendBotReply("目前對話還不足以分析溝通狀況，請先讓成員進行一些討論。")
                return
            }
            requestAICommunicationAnalysis(conversation: conversation)
            return
        }

        let queryPrefix = "幫我們查詢"
        let explicitQuestion: String
        if command.hasPrefix(queryPrefix) {
            explicitQuestion = String(command.dropFirst(queryPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            explicitQuestion = command
        }

        if explicitQuestion.isEmpty {
            guard let latestMessage = conversation.last else {
                appendBotReply("請問需要我幫忙查什麼？請在 @機器人 後面輸入問題。")
                return
            }
            requestAIAnswer(question: latestMessage, conversation: conversation)
        } else {
            requestAIAnswer(question: explicitQuestion, conversation: conversation)
        }
    }

    /// 等待鍵盤造成的版面更新套用後，再將最新訊息對齊聊天室底部。
    private func scrollToBottom(using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            withAnimation(.snappy) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func sendShortcut(_ shortcut: ChatShortcut) {
        guard !isAIResponding else { return }
        let conversation = model.chatItems(for: group.id).compactMap(\.humanConversationLine)

        model.appendChatItem(
            .message(
                id: UUID().uuidString,
                sender: "我",
                text: shortcut.command,
                time: Date.now.formatted(date: .omitted, time: .shortened),
                isCurrentUser: true
            ),
            to: group.id
        )
        withAnimation(.snappy) { showsShortcuts = false }

        switch shortcut {
        case .query:
            guard let latestMessage = conversation.last else {
                appendBotReply("請問需要我幫忙查什麼？請先在聊天室描述問題，再點一次「幫我們查詢」。")
                return
            }
            requestAIAnswer(question: latestMessage, conversation: conversation)
        case .analyze:
            guard conversation.count >= 2 else {
                appendBotReply("目前對話還不足以分析溝通狀況，請先讓成員進行一些討論。")
                return
            }
            requestAICommunicationAnalysis(conversation: conversation)
        }
    }

    private func requestAIAnswer(question: String, conversation: [String]) {
        isAIResponding = true
        Task { @MainActor in
            defer { isAIResponding = false }
            do {
                let answer = try await AppleIntelligenceService().answer(
                    question: question,
                    conversation: conversation
                )
                appendBotReply(answer)
            } catch {
                appendBotReply(aiErrorMessage(error))
            }
        }
    }

    private func requestAICommunicationAnalysis(conversation: [String]) {
        isAIResponding = true
        Task { @MainActor in
            defer { isAIResponding = false }
            do {
                let generated = try await AppleIntelligenceService()
                    .analyzeCommunication(conversation: conversation)
                let analysis = model.saveCommunicationAnalysis(
                    groupID: group.id,
                    generated: generated
                )
                model.appendChatItem(
                    .botAnalysis(id: analysis.id.uuidString, analysis: analysis),
                    to: group.id
                )
            } catch {
                appendBotReply(aiErrorMessage(error))
            }
        }
    }

    private func appendBotReply(_ text: String) {
        model.appendChatItem(
            .botReply(id: UUID().uuidString, text: text),
            to: group.id
        )
    }

    private func aiErrorMessage(_ error: Error) -> String {
        if let serviceError = error as? AppleIntelligenceServiceError {
            return serviceError.localizedDescription
        }
        return "Apple Intelligence 暫時無法完成這次請求，請稍後再試。"
    }
}

/// 可收起的聊天室機器人快捷指令；未來可在此增加查資料、建立任務等功能。
private enum ChatShortcut: CaseIterable, Identifiable {
    case query
    case analyze

    var id: Self { self }

    var command: String {
        switch self {
        case .query: "@機器人 幫我們查詢"
        case .analyze: "@機器人 分析溝通"
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

/// 聊天室內的 AI 回覆卡；完整報告可在設定的 AI 戰情成績單查看。
private struct ChatBotAnalysisCard: View {
    let analysis: CommunicationAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("拆彈 AI 通訊官", systemImage: "sparkles")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(analysis.score) 分")
                    .font(.headline.monospacedDigit().weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BombTheme.yellow)
                    .clipShape(.capsule)
            }
            Text(analysis.summary)
                .font(.subheadline.weight(.semibold))
            Text("完整報告已送至「設定 > 戰力報告」。")
                .font(.caption.weight(.bold))
                .foregroundStyle(BombTheme.ink.opacity(0.65))
        }
        .comicCard()
    }
}

/// 一般查詢指令的機器人回覆泡泡。
private struct ChatBotReplyBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.black))
                .foregroundStyle(BombTheme.yellow)
                .frame(width: 32, height: 32)
                .background(BombTheme.ink)
                .clipShape(.circle)
            Text(text)
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
            Spacer(minLength: 42)
        }
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
