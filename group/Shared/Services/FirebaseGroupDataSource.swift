import FirebaseAuth
import FirebaseFirestore

extension GroupRepository {
    static func firebase() -> GroupRepository {
        let firestore = Firestore.firestore()
        let callable = GroupJoinRepository()
        return GroupRepository(reads: Reads(
            currentUID: { Auth.auth().currentUser?.uid },
            summaries: { try await callable.fetchAccessibleGroups() },
            members: { groupID in
                let result = try await firestore.collection("groups").document(groupID)
                    .collection("members").getDocuments(source: .server)
                return try result.documents.map { CloudDocument(id: $0.documentID, value: try $0.data(as: CloudMemberDocument.self)) }
            },
            tasks: { groupID in
                let result = try await firestore.collection("groups").document(groupID)
                    .collection("tasks").getDocuments(source: .server)
                return try result.documents.map { CloudDocument(id: $0.documentID, value: try $0.data(as: CloudTaskDocument.self)) }
            }
        ))
    }
}
