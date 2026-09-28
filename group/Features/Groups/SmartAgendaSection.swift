import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct SmartAgendaSection: View {
    let store: SmartAgendaStore
    let members: [Member]
    let isLeader: Bool
    let onOpenDetails: () -> Void
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle { Text(L10n.text("自動化議程"))
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(BombTheme.ink)
            }
            SmartAgendaCard(store: store, members: members, isLeader: isLeader,
                            onOpenDetails: onOpenDetails)
        }
    }
}

struct SmartAgendaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SmartAgendaStore
    @State private var linkDraft: SmartAgendaLinkDraft?
    @State private var showsEditOptions = false
    @State private var showsMeetingEditor = false
    @State private var materialDraft: SmartAgendaMaterialDraft?
    let members: [Member]
    let isLeader: Bool

    var body: some View {
        ScrollView {
            SmartAgendaCard(store: store, members: members, isLeader: isLeader,
                            onEditLink: { linkDraft = $0 },
                            onEdit: {
                                if store.agenda == nil { showsMeetingEditor = true }
                                else { showsEditOptions = true }
                            })
                .padding(16)
                .padding(.bottom, 24)
        }
        .background(BombTheme.yellow.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .bombTabBarHidden()
        .onAppear { store.listen(generatesPlans: true) }
        .onChange(of: store.agenda == nil) { _, missing in
            if missing && !store.isLoading { dismiss() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: L10n.text("自動化議程")) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel(L10n.text("返回"))
            } trailing: {
                EmptyView()
            }
        }
        .accessibilityHidden(linkDraft != nil || showsEditOptions || showsMeetingEditor || materialDraft != nil)
        .overlay {
            if let draft = linkDraft {
                SmartAgendaLinkEditor(store: store, draft: draft) { linkDraft = nil }
                    .id(draft.id)
                    .transition(.opacity)
            } else if showsEditOptions || showsMeetingEditor || materialDraft != nil {
                ZStack {
                    BombTheme.ink.opacity(0.48)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if !store.isSaving {
                                showsEditOptions = false
                                showsMeetingEditor = false
                                materialDraft = nil
                            }
                        }
                    if let draft = materialDraft {
                        SmartAgendaMaterialEditor(store: store, draft: draft) { materialDraft = nil }
                            .id(draft.id)
                            .transition(.opacity)
                    } else if showsMeetingEditor {
                        SmartAgendaMeetingEditor(store: store) { showsMeetingEditor = false }
                            .transition(.opacity)
                    } else {
                        editOptions
                            .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: linkDraft?.id)
        .animation(.easeOut(duration: 0.2), value: showsEditOptions)
        .animation(.easeOut(duration: 0.2), value: showsMeetingEditor)
        .animation(.easeOut(duration: 0.2), value: materialDraft?.id)
    }

    private func materialTitle(_ entry: SmartAgenda.MaterialEntry) -> String {
        String((entry.material.note.isEmpty ? entry.material.attachment?.fileName ?? "" : store.agenda?.displayNote(entry.material.note) ?? entry.material.note).prefix(60))
    }

    private var editOptions: some View {
        let entries = store.agenda?.materials(for: store.uid) ?? []
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L10n.text("編輯議程"), systemImage: "square.and.pencil")
                    .font(.title2.weight(.black))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showsEditOptions = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(BombTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("取消"))
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(entries) { entry in
                        editOptionButton(entries.count == 1 ? L10n.text("編輯我的資料") : materialTitle(entry),
                                         icon: "person.crop.circle", highlighted: true) {
                            showsEditOptions = false
                            materialDraft = SmartAgendaMaterialDraft(entry: entry)
                        }
                    }
                    editOptionButton(L10n.text("新增我的資料"), icon: "plus") {
                        showsEditOptions = false
                        materialDraft = SmartAgendaMaterialDraft()
                    }
                    if isLeader, store.agenda?.meetingStartedAt == nil {
                        editOptionButton(L10n.text("編輯會議"), icon: "list.bullet") {
                            showsEditOptions = false
                            showsMeetingEditor = true
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: CGFloat(min(entries.count + (isLeader ? 2 : 1), 4)) * 68)
        }
        .foregroundStyle(BombTheme.ink)
        .padding(20)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
    }

    private func editOptionButton(_ title: String, icon: String, highlighted: Bool = false,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(highlighted ? BombTheme.ink : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(highlighted ? BombTheme.yellow : BombTheme.ink, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

}

/// Both screens read the same cloud agenda; only the detail page shows preparation content.
private struct SmartAgendaCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let store: SmartAgendaStore
    let members: [Member]
    let isLeader: Bool
    let onOpenDetails: (() -> Void)?
    let onEditLink: ((SmartAgendaLinkDraft) -> Void)?
    let onEdit: (() -> Void)?
    @State private var showsMeeting = false
    @State private var starting = false

    init(store: SmartAgendaStore, members: [Member], isLeader: Bool,
         onOpenDetails: (() -> Void)? = nil,
         onEditLink: ((SmartAgendaLinkDraft) -> Void)? = nil,
         onEdit: (() -> Void)? = nil) {
        self.store = store
        self.members = members
        self.isLeader = isLeader
        self.onOpenDetails = onOpenDetails
        self.onEditLink = onEditLink
        self.onEdit = onEdit
    }

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .topTrailing) {
            if let onOpenDetails {
                Button(action: onOpenDetails) { cardContent }
                    .buttonStyle(.plain)
                    .accessibilityHint(L10n.text("查看議程詳情"))
            } else {
                cardContent
            }
            if !store.isLoading, onOpenDetails == nil { editControl.padding(16) }
        }
        .foregroundStyle(BombTheme.ink)
        .tint(BombTheme.ink)
        .sheet(isPresented: $showsMeeting) { SmartAgendaMeetingSession(store: store, isLeader: isLeader) }
        .quickLookPreview($store.previewURL)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                meetingHeader
                if let agenda = store.agenda {
                    rule
                    HStack {
                        Text(L10n.text("團隊準備")).font(.subheadline.weight(.black))
                        Spacer()
                        Text(verbatim: "\(agenda.preparedUIDs.count)/\(agenda.memberUIDs.count)")
                            .font(.subheadline.weight(.black)).monospacedDigit()
                            .frame(minWidth: 44, alignment: .trailing)
                            .accessibilityLabel(L10n.format("{0}/{1} 人已準備", String(agenda.preparedUIDs.count), String(agenda.memberUIDs.count)))
                    }.padding(.vertical, 8)
                    if onOpenDetails != nil, agenda.allPrepared, agenda.stages.isEmpty {
                        Text(L10n.text(store.isGenerating || agenda.isGenerating(at: .now)
                                       ? "正在產生會議議程…" : "議程尚未產生"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BombTheme.secondaryText)
                            .padding(.bottom, 4)
                    }
                    if onOpenDetails == nil {
                        rule
                        if !pendingMembers.isEmpty {
                            Text(L10n.format("尚未準備：{0}", pendingMembers.map(\.name).joined(separator: L10n.text("、"))))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BombTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }
                        ForEach(preparedMembers) { person in
                            if let uid = person.firebaseUID {
                                ForEach(agenda.materials(for: uid)) { entry in
                                    preparationRow(person, material: entry.material)
                                }
                                if person.id != preparedMembers.last?.id { rule }
                            }
                        }
                        meetingLinks(agenda)
                        if agenda.allPrepared || agenda.meetingStartedAt != nil { plan(agenda) }
                    }
                }
            }
            if let error = store.error {
                Text(L10n.text(error)).font(.caption).foregroundStyle(BombTheme.red).padding(.top, 8)
            }
            if store.isDownloading { ProgressView().padding(.top, 8) }
        }
        .padding(16)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BombTheme.ink, lineWidth: 3))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private var preparedMembers: [Member] {
        members.filter { person in person.firebaseUID.map { !(store.agenda?.materials(for: $0).isEmpty ?? true) } ?? false }
    }
    private var pendingMembers: [Member] {
        guard let agenda = store.agenda else { return [] }
        return members.filter { person in
            guard let uid = person.firebaseUID else { return false }
            return agenda.memberUIDs.contains(uid) && !agenda.preparedUIDs.contains(uid)
        }
    }
    private var rule: some View { Rectangle().fill(BombTheme.ink.opacity(0.2)).frame(height: 0.7) }
    private var meetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("會議主題")).font(.footnote.weight(.black)).foregroundStyle(BombTheme.secondaryText)
                    if let agenda = store.agenda {
                        Text(agenda.displayTopic).font(.headline.weight(.black)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L10n.text(isLeader ? "設定會議" : "等待組長設定會議。"))
                            .font(.subheadline.weight(.black)).padding(.vertical, 8)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if onOpenDetails != nil {
                    // Use the member card's chevron footprint to align both icon centers.
                    Image(systemName: "chevron.down")
                        .hidden()
                        .overlay { Image(systemName: "chevron.right") }
                        .font(.subheadline.weight(.black))
                        .frame(width: 36, height: 44, alignment: .trailing)
                        .accessibilityHidden(true)
                } else {
                    // Reserve the detail page's edit button without nesting buttons.
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }
            }
            if let agenda = store.agenda {
                Text(agenda.summary).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.bottom, 12)
    }

    @ViewBuilder private var editControl: some View {
        if let onEdit, store.agenda != nil || isLeader {
            Button(action: onEdit) { editIcon }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("編輯議程"))
        }
    }

    private var editIcon: some View {
        Image(systemName: "pencil")
            .font(.headline.weight(.semibold))
            .frame(width: 44, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
    }

    private func preparationRow(_ person: Member, material: SmartAgenda.Material) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MemberPhotoAvatar(groupID: store.groupID, uid: person.firebaseUID, name: person.name, size: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(person.name)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BombTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !material.note.isEmpty {
                    Text(store.agenda?.displayNote(material.note) ?? material.note).font(.footnote.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let file = material.attachment {
                    Button { Task { await store.download(file) } } label: {
                        Label(file.fileName, systemImage: "paperclip").font(.footnote.weight(.semibold))
                            .lineLimit(2).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).disabled(store.isDownloading)
                }
            }.foregroundStyle(BombTheme.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 10)
    }

    private func meetingLinks(_ agenda: SmartAgenda) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(agenda.meetingLinks) { entry in
                HStack(spacing: 8) {
                    if let url = entry.link.destination {
                        Link(destination: url) {
                            Label(entry.link.displayTitle, systemImage: "link")
                                .font(.subheadline.weight(.black))
                                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                    if entry.link.ownerUID == store.uid || isLeader {
                        Button { onEditLink?(SmartAgendaLinkDraft(entry: entry)) } label: {
                            editIcon
                        }.buttonStyle(.plain).accessibilityLabel(L10n.text("編輯會議連結"))
                    }
                }
            }
            Button { onEditLink?(SmartAgendaLinkDraft()) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .accessibilityHidden(true)
                    Text(L10n.text("新增會議連結"))
                }
                .font(.subheadline.weight(.black))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 1.5))
                .contentShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 7).padding(.bottom, 12)
    }

    private func retryMessage(_ message: String?) -> some View {
        var text = AttributedString(message.map { L10n.text($0) + " " } ?? "")
        var retry = AttributedString(L10n.text("重試"))
        retry.link = URL(string: "groupbomb-action://retry-agenda")
        retry.font = .caption.bold()
        retry.underlineStyle = .single
        text.append(retry)
        return Text(text).font(.caption).foregroundStyle(BombTheme.secondaryText)
            .environment(\.openURL, OpenURLAction { _ in
                Task { await store.retryGeneration() }
                return .handled
            })
    }

    private func plan(_ agenda: SmartAgenda) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            rule
            Text(L10n.text(agenda.planSource == "sample" ? "範例會議議程" : "AI 建議議程"))
                .font(.subheadline.weight(.black)).padding(.top, 5).padding(.bottom, 4)
            if agenda.stages.isEmpty {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if store.isGenerating || agenda.isGenerating(at: context.date) {
                        HStack { ProgressView().controlSize(.small); Text(L10n.text("正在產生會議議程…")).font(.subheadline.weight(.semibold)) }
                            .padding(.vertical, 14)
                    } else if store.cannotGenerateOnThisDevice {
                        Text(L10n.text("請由支援 Apple Intelligence 的成員開啟專案以產生議程。"))
                            .font(.caption)
                            .foregroundStyle(BombTheme.secondaryText)
                    } else {
                        retryMessage(store.aiError ?? agenda.generationError
                                     ?? "使用 Apple Intelligence 產生議程並同步給成員。")
                    }
                }
            } else {
                ForEach(agenda.stages) { stage in
                    (dynamicTypeSize.isAccessibilitySize
                     ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                     : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                        Text(stage.time).font(.footnote.weight(.black))
                            .foregroundStyle(BombTheme.secondaryText)
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 80, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(agenda.displayTitle(stage)).font(.subheadline.weight(.black))
                            Text(agenda.displayGoal(stage)).font(.footnote.weight(.semibold)).foregroundStyle(BombTheme.secondaryText)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                    if stage.id != agenda.stages.last?.id { rule }
                }
                if agenda.meetingStartedAt != nil {
                    Button(L10n.text("開啟會議")) { showsMeeting = true }
                        .buttonStyle(BombFormPrimaryButtonStyle()).padding(.top, 12)
                } else if isLeader {
                    Button {
                        starting = true
                        Task {
                            defer { starting = false }
                            do { try await store.startMeeting(); showsMeeting = true }
                            catch { store.error = error.localizedDescription }
                        }
                    } label: {
                        Text(L10n.text(starting ? "正在開始…" : "開始會議"))
                    }.buttonStyle(BombFormPrimaryButtonStyle()).padding(.top, 12).disabled(starting)
                } else {
                    Text(L10n.text("等待組長開始會議。"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BombTheme.secondaryText)
                        .padding(.top, 8)
                }
            }
        }
    }
}

struct SmartAgendaMeetingEditor: View {
    let store: SmartAgendaStore
    let onDismiss: () -> Void
    @State private var topic: String
    @State private var date: Date
    @State private var duration: Int
    @State private var error: String?
    private let revision: String?
    private let initialTopic: SmartAgenda.EditableText
    init(store: SmartAgendaStore, onDismiss: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
        revision = store.agenda?.meetingRevision
        initialTopic = store.agenda?.editableTopic ?? .init(original: "", displayed: "")
        _topic = State(initialValue: initialTopic.displayed)
        _date = State(initialValue: store.agenda?.meetingAt ?? Date.now.addingTimeInterval(3600))
        _duration = State(initialValue: store.agenda?.duration ?? 20)
    }
    private var canSave: Bool {
        !store.isSaving && !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && topic.count <= 120
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(L10n.text(revision == nil ? "設定會議" : "編輯會議"), systemImage: "list.bullet")
                        .font(.title2.weight(.black))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(BombTheme.ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("取消"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("會議主題")).font(.subheadline.weight(.black))
                    TextField(L10n.text("會議主題"), text: $topic).bombFormField()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("日期與時間")).font(.subheadline.weight(.black))
                    DatePicker(L10n.text("會議"), selection: $date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .bombFormField()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("會議長度")).font(.subheadline.weight(.black))
                    Stepper(L10n.format("{0} 分鐘", String(duration)), value: $duration, in: 5...180, step: 5)
                        .bombFormField()
                }
                if let error { Text(L10n.text(error)).foregroundStyle(BombTheme.red) }
                actionButton(store.isSaving ? "儲存中…" : "儲存", icon: "checkmark", highlighted: true, action: save)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                actionButton("取消", icon: "xmark", action: onDismiss)
            }
            .disabled(store.isSaving)
            .foregroundStyle(BombTheme.ink)
            .tint(BombTheme.ink)
            .padding(20)
            .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isModal)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.center)
    }

    private func actionButton(_ title: String, icon: String, highlighted: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.text(title), systemImage: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(highlighted ? BombTheme.ink : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(highlighted ? BombTheme.yellow : BombTheme.ink, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave else { return }
        Task {
            do {
                try await store.saveMeeting(topic: initialTopic.valueToSave(topic), date: date,
                                            duration: duration, revision: revision)
                onDismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct SmartAgendaMaterialDraft: Identifiable {
    let id: String
    let material: SmartAgenda.Material?

    init(entry: SmartAgenda.MaterialEntry? = nil) {
        id = entry?.id ?? UUID().uuidString.lowercased()
        material = entry?.material
    }
}

private struct SmartAgendaMaterialEditor: View {
    let store: SmartAgendaStore
    let draft: SmartAgendaMaterialDraft
    let onDismiss: () -> Void
    @State private var note: String
    @State private var attachment: SmartAgenda.Attachment?
    @State private var selectedFile: URL?
    @State private var showsImporter = false
    @State private var error: String?
    private let revision: String?
    private let initialNote: SmartAgenda.EditableText
    init(store: SmartAgendaStore, draft: SmartAgendaMaterialDraft, onDismiss: @escaping () -> Void) {
        self.store = store
        self.draft = draft
        self.onDismiss = onDismiss
        let own = draft.material
        revision = own?.revision
        let original = own?.note ?? ""
        initialNote = store.agenda?.editableNote(original) ?? .init(original: original, displayed: original)
        _note = State(initialValue: initialNote.displayed)
        _attachment = State(initialValue: own?.attachment)
    }
    private var canSave: Bool {
        !store.isSaving && note.count <= 1000
            && (draft.material != nil || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || selectedFile != nil || attachment != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(L10n.text(draft.material == nil ? "新增我的資料" : "編輯我的資料"), systemImage: "person.crop.circle")
                        .font(.title2.weight(.black))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(BombTheme.ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("取消"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("準備內容")).font(.subheadline.weight(.black))
                    TextField(L10n.text("你想在會議中討論什麼？"), text: $note, axis: .vertical)
                        .lineLimit(3...5).bombFormField()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("附件")).font(.subheadline.weight(.black))
                    if let name = selectedFile?.lastPathComponent ?? attachment?.fileName {
                        HStack {
                            Label(name, systemImage: "paperclip").lineLimit(2)
                            Spacer()
                            Button { selectedFile = nil; attachment = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel(L10n.text("移除附件"))
                        }.bombFormField()
                    }
                    Button(L10n.text("選擇檔案"), systemImage: "plus") { showsImporter = true }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .bombFormField()
                }
                if let error { Text(L10n.text(error)).foregroundStyle(BombTheme.red) }
                actionButton(store.isSaving ? "儲存中…" : "儲存", icon: "checkmark", highlighted: true, action: save)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                actionButton("取消", icon: "xmark", action: onDismiss)
            }
            .disabled(store.isSaving)
            .foregroundStyle(BombTheme.ink)
            .tint(BombTheme.ink)
            .padding(20)
            .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isModal)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(.center)
        .fileImporter(isPresented: $showsImporter,
                      allowedContentTypes: SmartAgendaStore.fileTypes.keys.compactMap { UTType(filenameExtension: $0) }) { result in
            do { selectedFile = try result.get(); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }

    private func actionButton(_ title: String, icon: String, highlighted: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.text(title), systemImage: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(highlighted ? BombTheme.ink : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(highlighted ? BombTheme.yellow : BombTheme.ink, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave else { return }
        Task {
            do {
                try await store.saveMaterial(id: draft.id, note: initialNote.valueToSave(note), attachment: attachment,
                                             file: selectedFile, revision: revision)
                onDismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct SmartAgendaMeetingSession: View {
    let store: SmartAgendaStore
    let isLeader: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let agenda = store.agenda, let started = agenda.meetingStartedAt {
                    let elapsed = max(0, Int(context.date.timeIntervalSince(started)))
                    let remaining = max(0, agenda.duration * 60 - elapsed)
                    VStack(alignment: .leading, spacing: 20) {
                        Text(agenda.displayTopic).font(.title2.bold())
                        Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                        if let current = agenda.stages.first(where: { elapsed < $0.end * 60 }) {
                            Text(current.time).foregroundStyle(BombTheme.secondaryText)
                            Text(agenda.displayTitle(current)).font(.title3.bold())
                            Text(agenda.displayGoal(current))
                        } else { Text(L10n.text("會議已結束")).font(.title3.bold()) }
                        Spacer()
                        if let error { Text(L10n.text(error)).font(.caption).foregroundStyle(BombTheme.red) }
                        if isLeader {
                            Button(L10n.text("結束會議")) {
                                Task {
                                    do { try await store.endMeeting(); dismiss() }
                                    catch { self.error = error.localizedDescription }
                                }
                            }.buttonStyle(BombFormPrimaryButtonStyle())
                        }
                    }.padding(24)
                } else { Text(L10n.text("會議尚未開始。")) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(BombTheme.paper)
            .navigationTitle(L10n.text("會議")).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L10n.text("完成")) { dismiss() } }
        }
    }
}
