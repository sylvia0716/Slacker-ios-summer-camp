import SwiftUI

struct SmartAgendaLinkDraft: Identifiable {
    let id: String
    let link: SmartAgenda.MeetingLink?

    init(entry: SmartAgenda.LinkEntry? = nil) {
        id = entry?.id ?? UUID().uuidString.lowercased()
        link = entry?.link
    }
}

struct SmartAgendaLinkEditor: View {
    let store: SmartAgendaStore
    let draft: SmartAgendaLinkDraft
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    @State private var error: String?
    @State private var confirmsDeletion = false

    init(store: SmartAgendaStore, draft: SmartAgendaLinkDraft) {
        self.store = store
        self.draft = draft
        _title = State(initialValue: draft.link?.title ?? "")
        _url = State(initialValue: draft.link?.url ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("連結名稱（選填）")) {
                    TextField(L10n.text("連結名稱"), text: $title)
                }
                Section(L10n.text("網址")) {
                    TextField("https://", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if draft.link != nil {
                    Button(L10n.text("刪除連結"), role: .destructive) { confirmsDeletion = true }
                }
                if let error { Text(L10n.text(error)).foregroundStyle(BombTheme.red) }
            }
            .disabled(store.isSaving)
            .scrollContentBackground(.hidden).background(SmartAgendaStyle.paper)
            .navigationTitle(L10n.text(draft.link == nil ? "新增會議連結" : "編輯會議連結"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("取消")) { dismiss() }.disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(store.isSaving ? "儲存中…" : "儲存")) { save() }
                        .disabled(store.isSaving || title.count > 120 || SmartAgenda.MeetingLink.validURL(url) == nil)
                }
            }
            .alert(L10n.text("刪除連結？"), isPresented: $confirmsDeletion) {
                Button(L10n.text("刪除連結"), role: .destructive) { save(removing: true) }
                Button(L10n.text("取消"), role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large]).interactiveDismissDisabled(store.isSaving)
    }

    private func save(removing: Bool = false) {
        Task {
            do {
                try await store.saveLink(id: draft.id, title: removing ? "" : title,
                                         url: removing ? "" : url, revision: draft.link?.revision)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
