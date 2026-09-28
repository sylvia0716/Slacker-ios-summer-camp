import SwiftUI

struct SmartAgendaManager: View {
    let collection: SmartAgendaCollectionStore
    let onClose: () -> Void
    @State private var editing: SmartAgendaStore?
    @State private var deletion: Deletion?
    @State private var deleting = false
    @State private var error: String?

    private struct Deletion {
        let store: SmartAgendaStore
        let revision: String
        let topic: String
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BombTheme.ink.opacity(0.48).ignoresSafeArea()
                    .onTapGesture {
                        if let editing {
                            if !editing.isSaving { self.editing = nil }
                        } else if !deleting { onClose() }
                    }
                if let editing {
                    SmartAgendaMeetingEditor(store: editing) { self.editing = nil }
                        .id(editing.id)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(L10n.text(deletion == nil ? "管理議程" : "刪除議程"), systemImage: "list.bullet")
                                .font(.title2.weight(.black))
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark").font(.headline.weight(.black))
                                    .foregroundStyle(.white).frame(width: 36, height: 36)
                                    .background(BombTheme.ink, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("取消"))
                            .disabled(deleting)
                        }
                        if let deletion {
                            Text(deletion.topic).font(.headline)
                            Text(L10n.text("刪除後，這場會議的準備資料、連結與 AI 議程也會移除。"))
                                .font(.subheadline)
                            actionButton(deleting ? "刪除中…" : "刪除議程", icon: "trash", color: BombTheme.red) {
                                deleting = true
                                error = nil
                                Task {
                                    defer { deleting = false }
                                    do {
                                        try await deletion.store.deleteMeeting(revision: deletion.revision)
                                        self.deletion = nil
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                            actionButton("取消", icon: "xmark", color: BombTheme.ink) {
                                self.deletion = nil
                                error = nil
                            }
                        } else {
                            if collection.isLoading { ProgressView().frame(maxWidth: .infinity) }
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(collection.meetings) { store in
                                        if let agenda = store.agenda {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(agenda.displayTopic).font(.headline.weight(.black))
                                                Text(agenda.summary).font(.subheadline).foregroundStyle(BombTheme.secondaryText)
                                                HStack {
                                                    Spacer()
                                                    Button { editing = store } label: {
                                                        Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
                                                    }
                                                    .disabled(agenda.meetingStartedAt != nil)
                                                    .accessibilityLabel(L10n.text("編輯會議") + "：" + agenda.displayTopic)
                                                    Button {
                                                        error = nil
                                                        deletion = Deletion(store: store, revision: agenda.meetingRevision, topic: agenda.displayTopic)
                                                    } label: {
                                                        Image(systemName: "trash").frame(width: 44, height: 44)
                                                    }
                                                    .accessibilityLabel(L10n.text("刪除議程") + "：" + agenda.displayTopic)
                                                }
                                                .font(.headline.weight(.bold))
                                                .buttonStyle(.plain)
                                            }
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 1.5))
                                        }
                                    }
                                }
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .frame(maxHeight: min(CGFloat(collection.meetings.count) * 146, max(140, geometry.size.height - 300)))
                            actionButton("新增議程", icon: "plus", color: BombTheme.yellow) { editing = collection.newMeeting() }
                        }
                        if let message = error ?? collection.error {
                            Text(L10n.text(message)).font(.footnote).foregroundStyle(BombTheme.red)
                        }
                    }
                    .disabled(deleting)
                    .foregroundStyle(BombTheme.ink)
                    .padding(20)
                    .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(BombTheme.ink, lineWidth: 3))
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: editing?.id)
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.text(title), systemImage: icon).font(.headline.weight(.black))
                .foregroundStyle(color == BombTheme.yellow ? BombTheme.ink : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(color, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
