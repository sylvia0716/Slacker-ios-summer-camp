import SwiftUI
import FirebaseFirestore
import FirebaseStorage

struct MemberPhotoAvatar: View {
    let groupID: String?
    let uid: String?
    let name: String
    // nil: ordinary avatar; false: awaiting confirmation; true: confirmed.
    var confirmed: Bool? = nil
    var size: CGFloat = 32
    @State private var photo: UIImage?
    @State private var path: String?
    @State private var version: String?
    @State private var listener: ListenerRegistration?
    @State private var subscriptionID = UUID()

    var body: some View {
        ZStack {
            Circle().fill(BombTheme.ink)
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .black)).foregroundStyle(BombTheme.yellow)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .saturation(confirmed == false ? 0 : 1)
        .opacity(confirmed == false ? 0.5 : 1)
        .task(id: "\(groupID ?? "")/\(uid ?? "")") {
            listener?.remove()
            let subscription = UUID()
            subscriptionID = subscription
            photo = nil
            path = nil
            version = nil
            guard let uid, let groupID else { return }
            listener = Firestore.firestore().collection("groups").document(groupID).collection("members").document(uid).addSnapshotListener { snapshot, _ in
                let value = snapshot?.data()?["avatarPath"] as? String
                let revision = snapshot?.data()?["avatarVersion"] as? String
                Task { @MainActor in
                    guard subscriptionID == subscription else { return }
                    path = value == "groups/\(groupID)/avatars/\(uid)/avatar.jpg" ? value : nil
                    version = revision
                }
            }
        }
        .task(id: "\(path ?? "")/\(version ?? "")") {
            photo = nil
            guard let path else { return }
            if let data = try? await Storage.storage().reference(withPath: path).data(maxSize: 2 * 1024 * 1024), !Task.isCancelled {
                photo = UIImage(data: data)
            }
        }
        .onDisappear {
            subscriptionID = UUID()
            listener?.remove()
            listener = nil
            photo = nil
        }
    }
}
