import SwiftUI

/// Page-scoped mock content for the first chat-room prototype.
/// Production chat and system-event models will be added only when the shared store is ready.
private enum ChatRoomPreviewItem: Identifiable {
    case message(id: String, sender: String, text: String, time: String, isCurrentUser: Bool)
    case systemEvent(id: String, icon: String, text: String)
    case botAnalysis(id: String, analysis: CommunicationAnalysis)
    case botReply(id: String, text: String)

    var id: String {
        switch self {
        case let .message(id, _, _, _, _), let .systemEvent(id, _, _), let .botAnalysis(id, _), let .botReply(id, _): id
        }
    }

    /// 供機器人評分使用的純文字訊息；系統事件與機器人回覆不會納入計算。
    var messageText: String? {
        guard case let .message(_, _, text, _, _) = self else { return nil }
        return text
    }
}

private struct ChatRoomPreviewData {
    let memberCount: Int
    let messages: [ChatRoomPreviewItem]

    static let sample = ChatRoomPreviewData(
        memberCount: 4,
        messages: [
            .systemEvent(id: "joined", icon: "person.2.fill", text: "拆彈小隊已全員到齊"),
            .message(
                id: "xiaoyu-update",
                sender: "小宇",
                text: "競品資料整理好了，我正在補比較矩陣。",
                time: "14:18",
                isCurrentUser: false
            ),
            .message(
                id: "me-reply",
                sender: "我",
                text: "收到！完成後直接丟連結，我來一起檢查。",
                time: "14:20",
                isCurrentUser: true
            ),
            .systemEvent(id: "progress", icon: "bolt.fill", text: "小宇將「製作競品分析」推進至 76%"),
            .message(
                id: "mimi-help",
                sender: "米米",
                text: "有人可以幫我確認封面配色嗎？",
                time: "14:32",
                isCurrentUser: false
            )
        ]
    )
}

/// Static group chat UI. Sending is intentionally local-only for this prototype.
struct ChatRoomView: View {
    @Environment(\.dismiss) private var dismiss
    let model: GroupBombModel
    let group: Group

    @State private var draft = ""
    @State private var items = ChatRoomPreviewData.sample.messages
    @State private var showsShortcuts = false

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                memberStatus

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(items) { item in
                                chatItem(item)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: items.count) {
                        guard let lastID = items.last?.id else { return }
                        withAnimation(.snappy) { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
            Text("\(ChatRoomPreviewData.sample.memberCount) 位成員在線")
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
    private func chatItem(_ item: ChatRoomPreviewItem) -> some View {
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
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        items.append(
            .message(
                id: UUID().uuidString,
                sender: "我",
                text: text,
                time: Date.now.formatted(date: .omitted, time: .shortened),
                isCurrentUser: true
            )
        )
        draft = ""
    }

    private func analyzeCommunication() {
        let messages = items.compactMap(\.messageText)
        let analysis = model.analyzeCommunication(groupID: group.id, messages: messages)
        items.append(.botAnalysis(id: analysis.id.uuidString, analysis: analysis))
    }

    private func sendShortcut(_ shortcut: ChatShortcut) {
        items.append(
            .message(
                id: UUID().uuidString,
                sender: "我",
                text: shortcut.command,
                time: Date.now.formatted(date: .omitted, time: .shortened),
                isCurrentUser: true
            )
        )
        withAnimation(.snappy) { showsShortcuts = false }

        switch shortcut {
        case .query:
            items.append(
                .botReply(
                    id: UUID().uuidString,
                    text: queryReply(for: items.compactMap(\.messageText))
                )
            )
        case .analyze:
            analyzeCommunication()
        }
    }

    /// MVP 的情境式查詢回覆；未來改接 AI 時可將聊天室文字傳給 service 取得真正答案。
    private func queryReply(for messages: [String]) -> String {
        let recentQuestion = messages
            .dropLast()
            .reversed()
            .first { $0.contains("？") || $0.contains("?") || $0.hasSuffix("嗎") }

        guard let recentQuestion else {
            return "請問需要我幫忙查什麼？你可以直接描述問題，例如：幫我確認封面配色。"
        }

        if recentQuestion.contains("封面") || recentQuestion.contains("配色") {
            return "我看到有人在確認封面配色：目前的黃黑配色辨識度很高，也符合拆彈任務的警示風格，可以繼續使用。建議標題維持黑字、內文搭配米白色，閱讀會更清楚。"
        }
        return "我看到你們在問「\(recentQuestion)」。可以再補上相關連結、截止時間或想比較的選項，我就能提供更精準的建議。"
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
    @Previewable @State var model = AppStore()
    NavigationStack {
        if let group = model.groups.first {
            ChatRoomView(model: model, group: group)
        }
    }
}
