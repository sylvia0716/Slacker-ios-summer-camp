import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

@MainActor
struct ProfilePhotoService {
    func save(_ data: Data, groupIDs: [String]) async throws {
        guard let user = Auth.auth().currentUser else { throw AttachmentOperationError.signedOut }
        guard let image = UIImage(data: data) else { throw AttachmentOperationError.invalidFile }
        let size = image.size
        let scale = min(1, 512 / max(size.width, size.height))
        let resized = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale)).image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw AttachmentOperationError.invalidFile }
        let path = "avatars/\(user.uid)/\(UUID().uuidString.lowercased()).jpg"
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(jpeg, metadata: metadata)
        do {
            guard Auth.auth().currentUser?.uid == user.uid else { throw AttachmentOperationError.signedOut }
            try await Firestore.firestore().collection("profiles").document(user.uid).setData(["avatarPath": path], merge: true)
        } catch {
            try? await ref.delete()
            throw error
        }
        try await share(jpeg, uid: user.uid, groupIDs: groupIDs)
    }

    func share(_ data: Data, uid: String, groupIDs: [String]) async throws {
        var firstError: Error?
        for groupID in Set(groupIDs) {
            guard Auth.auth().currentUser?.uid == uid else { throw AttachmentOperationError.signedOut }
            do {
                let path = "groups/\(groupID)/avatars/\(uid)/avatar.jpg"
                let ref = Storage.storage().reference(withPath: path)
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                _ = try await ref.putDataAsync(data, metadata: metadata)
                try await Firestore.firestore().collection("groups").document(groupID).collection("members").document(uid)
                    .updateData(["avatarPath": path, "avatarVersion": UUID().uuidString])
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    func load(uid: String) async throws -> Data? {
        let doc = try await Firestore.firestore().collection("profiles").document(uid).getDocument()
        guard let path = doc.data()?["avatarPath"] as? String, path.hasPrefix("avatars/\(uid)/") else { return nil }
        return try await Storage.storage().reference(withPath: path).data(maxSize: 2 * 1024 * 1024)
    }
}
