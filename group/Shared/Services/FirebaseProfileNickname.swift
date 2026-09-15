import FirebaseAuth
import FirebaseFirestore

extension ProfileNicknameRepository {
    static func firebase() -> ProfileNicknameRepository {
        ProfileNicknameRepository(client: Client(currentUID: { Auth.auth().currentUser?.uid }, saveAccountName: { name in
            guard let user = Auth.auth().currentUser else { throw NicknameError.signedOut }
            let request = user.createProfileChangeRequest()
            request.displayName = name
            do { try await request.commitChanges() }
            catch { throw NicknameError.network }
        }, saveMemberName: { groupID, uid, name in
            guard Auth.auth().currentUser?.uid == uid else { throw NicknameError.accountChanged }
            // updateData never creates a membership; deployed Rules allow only self displayName updates.
            try await Firestore.firestore().collection("groups").document(groupID).collection("members")
                .document(uid).updateData(["displayName": name])
        }))
    }
}
