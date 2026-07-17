import SwiftUI

/// First tab: lists groups the current user has joined and opens their detail screen.
struct GroupListView: View {
    let model: GroupBombModel
    @State private var isAddGroupPresented = false
    @State private var enteredGroup: Group?

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("選一組，繼續拆彈。")
                        .font(.subheadline.bold())

                    if model.groups.isEmpty {
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
                    } else {
                        ForEach(model.groups.sorted(by: { $0.deadline < $1.deadline })) { group in
                            NavigationLink {
                                GroupDetailView(group: group, model: model)
                            } label: {
                                GroupRow(
                                    group: group,
                                    progress: model.projectProgress(for: group.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("我的群組")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新增", systemImage: "plus") {
                    isAddGroupPresented = true
                }
            }
        }
        .sheet(isPresented: $isAddGroupPresented) {
            AddGroupSheet(model: model) { group in
                enteredGroup = group
            }
        }
        .navigationDestination(item: $enteredGroup) { group in
            GroupDetailView(group: group, model: model)
        }
    }
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
                                entryButton(
                                    title: "建立群組",
                                    symbol: "plus",
                                    mode: .create
                                )
                                entryButton(
                                    title: "加入群組",
                                    symbol: "person.badge.plus",
                                    mode: .join
                                )
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
                        if flow == .entry {
                            dismiss()
                        } else {
                            flow = .entry
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("下一步") {
                        advance()
                    }
                    .disabled(!canAdvance)
                }
            }
        }
        .presentationDetents([.medium])
        .alert("無法加入群組", isPresented: Binding(get: { joinError != nil }, set: { if !$0 { joinError = nil } })) {
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

/// One group entry. Future work: show the real member and task counts from Group relationships.
private struct GroupRow: View {
    let group: Group
    let progress: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(BombTheme.yellow)
                    Text(group.name).font(.title3.weight(.black))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold())
                }
                HStack {
                    Label(remainingTime(at: context.date), systemImage: "timer")
                    Spacer()
                    Label("專案進度 \(progress)%", systemImage: "chart.bar.fill")
                }
                .font(.caption.bold())
                ProgressView(value: Double(progress), total: 100).tint(BombTheme.yellow)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(BombTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func remainingTime(at date: Date) -> String {
        let remaining = max(0, Int(group.deadline.timeIntervalSince(date)))
        let days = remaining / 86_400
        let hours = remaining % 86_400 / 3_600

        if remaining == 0 {
            return "已截止"
        }

        if days > 0 {
            return "剩 \(days) 天"
        }

        return "剩 \(hours) 小時"
    }
}
