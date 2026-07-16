import SwiftUI

/// Page-scoped mock content for the first chat-room prototype.
/// Production chat and system-event models will be added only when the shared store is ready.
private enum ChatRoomPreviewItem: Identifiable {
    case message(id: String, sender: String, text: String, time: String, isCurrentUser: Bool)
    case systemEvent(id: String, icon: String, text: String)

    var id: String {
        switch self {
        case let .message(id, _, _, _, _), let .systemEvent(id, _, _): id
        }
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
    let groupName: String

    @State private var draft = ""
    @State private var items = ChatRoomPreviewData.sample.messages

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
                Text(groupName)
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
        HStack(spacing: 10) {
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
}

#Preview("Chat room") {
    NavigationStack {
        ChatRoomView(groupName: "期末報告拆彈小隊")
    }
}
