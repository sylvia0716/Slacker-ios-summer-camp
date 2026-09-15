import FirebaseAuth
import FirebaseFirestore
import Foundation

/// 持續監聽群組任務，讓所有成員共用相同的任務與子任務進度。
final class TaskSyncRepository {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    @discardableResult
    func listen(
        groupID: String,
        expectedUserID: String,
        onChange: @escaping (Result<[CloudDocument<CloudTaskDocument>], Error>) -> Void
    ) -> ListenerRegistration {
        var receivedServerSnapshot = false
        return firestore.collection("groups").document(groupID)
            .collection("tasks")
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                guard Auth.auth().currentUser?.uid == expectedUserID else {
                    onChange(.failure(GroupLoadError.accountChanged))
                    return
                }
                if let error {
                    onChange(.failure(error))
                    return
                }

                // 帳號切換時不顯示其他工作階段殘留的本機快取。
                if snapshot?.metadata.isFromCache == true {
                    if receivedServerSnapshot { onChange(.failure(GroupLoadError.network)) }
                    return
                }
                receivedServerSnapshot = true

                do {
                    let documents = try (snapshot?.documents ?? []).map {
                        CloudDocument(id: $0.documentID, value: try $0.data(as: CloudTaskDocument.self))
                    }
                    onChange(.success(documents))
                } catch {
                    onChange(.failure(error))
                }
            }
    }
}
