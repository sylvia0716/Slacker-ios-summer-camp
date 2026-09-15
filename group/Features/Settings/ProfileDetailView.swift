import PhotosUI
import SwiftUI

/// Nickname is shared with Firebase; other profile fields retain their existing behavior.
struct ProfileDetailView: View {
    let model: GroupBombModel

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    @State private var draftRole: String
    @State private var draftBio: String
    @State private var draftAvatarSymbol: String
    @State private var draftAvatarData: Data?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isLoadingAvatar = false
    @State private var saveError: String?

    init(model: GroupBombModel) {
        self.model = model
        _draftName = State(initialValue: model.profileName)
        _draftRole = State(initialValue: model.profileRole)
        _draftBio = State(initialValue: model.profileBio)
        _draftAvatarSymbol = State(initialValue: model.profileAvatarSymbol)
        _draftAvatarData = State(initialValue: model.profileAvatarData)
    }

    var body: some View {
        ZStack {
            BombTheme.yellow.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 0) {
                        avatarEditor
                            .padding(.bottom, 18)
                        Divider()
                        profileFields
                    }
                    .comicCard()

                    saveButton
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            BombHeader(title: "編輯個人資料") {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(BombHeaderButtonStyle())
                .accessibilityLabel("返回設定")
                .disabled(model.isSavingNickname)
            } trailing: {
                EmptyView()
            }
        }
        .interactiveDismissDisabled(model.isSavingNickname)
        .alert("儲存失敗", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("確定", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            isLoadingAvatar = true

            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data {
                        draftAvatarData = data
                    }
                    isLoadingAvatar = false
                }
            }
        }
    }

    private var avatarEditor: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarImage(
                        data: draftAvatarData,
                        fallbackSymbol: draftAvatarSymbol
                    )
                        .frame(width: 118, height: 118)
                        .clipShape(.circle)
                        .overlay(Circle().stroke(BombTheme.paper, lineWidth: 6))

                    Image(systemName: "camera.fill")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(BombTheme.yellow)
                        .clipShape(.circle)
                        .overlay(Circle().stroke(BombTheme.ink, lineWidth: 3))

                    if isLoadingAvatar {
                        ZStack {
                            Circle().fill(.black.opacity(0.55))
                            ProgressView().tint(.white)
                        }
                        .frame(width: 118, height: 118)
                    }
                }
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Label("編輯大頭貼", systemImage: "photo.on.rectangle.angled")
            }
            .font(.headline.weight(.black))
            .foregroundStyle(BombTheme.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditProfileField(
                icon: "person.fill",
                title: "暱稱",
                prompt: "輸入暱稱",
                text: $draftName
            )

            Divider()

            EditProfileField(
                icon: "shield.lefthalf.filled",
                title: "身分標籤",
                prompt: "輸入身分標籤",
                text: $draftRole
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("自我介紹", systemImage: "text.quote")
                    .font(.body.weight(.black))

                TextField("寫一段自我介紹", text: $draftBio, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(.white.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(BombTheme.ink.opacity(0.20), lineWidth: 1.5)
                    )
            }
            .padding(.vertical, 14)
        }
    }

    private var saveButton: some View {
        Button {
            let name = draftName, role = draftRole, bio = draftBio
            let symbol = draftAvatarSymbol, avatar = draftAvatarData
            Task {
                do {
                    try await model.saveProfileNickname(name)
                    model.profileRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.profileBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.profileAvatarSymbol = symbol
                    model.profileAvatarData = avatar
                    dismiss()
                } catch {
                    saveError = (error as? NicknameError)?.localizedDescription ?? NicknameError.network.localizedDescription
                }
            }
        } label: {
            Label(model.isSavingNickname ? "儲存中…" : "儲存變更", systemImage: "checkmark.circle.fill")
                .font(.headline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(BombTheme.ink)
        .clipShape(.capsule)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
    }

    private var canSave: Bool {
        !model.isSavingNickname && !isLoadingAvatar &&
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

}

private struct EditProfileField: View {
    let icon: String
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.body.weight(.black))

            TextField(prompt, text: $text)
                .font(.body.weight(.semibold))
                .padding(12)
                .background(.white.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(BombTheme.ink.opacity(0.20), lineWidth: 1.5)
                )
        }
        .padding(.vertical, 14)
    }
}
