import FirebaseAuth
import FirebaseFirestore
import Observation

/// One subscription per project; each meeting keeps its own preparation, plan and editing state.
@MainActor @Observable
final class SmartAgendaCollectionStore {
    let groupID: String
    let uid: String
    private(set) var meetings: [SmartAgendaStore] = []
    private(set) var isLoading = true
    var error: String?
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var subscription = UUID()

    init(groupID: String, uid: String) { self.groupID = groupID; self.uid = uid }

    func newMeeting() -> SmartAgendaStore {
        SmartAgendaStore(groupID: groupID, uid: uid, id: UUID().uuidString.lowercased())
    }

    func listen() {
        guard listener == nil, Auth.auth().currentUser?.uid == uid else { return }
        isLoading = true
        let token = UUID()
        subscription = token
        listener = Firestore.firestore().collection("groups").document(groupID)
            .collection("smartAgenda").addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self, self.subscription == token, Auth.auth().currentUser?.uid == self.uid else { return }
                    self.isLoading = false
                    if let error { self.error = error.localizedDescription; return }
                    guard let snapshot else { return }
                    do {
                        let values = try snapshot.documents.filter { $0.data()["deleted"] as? Bool != true }
                            .map { ($0.documentID, try $0.data(as: SmartAgenda.self)) }
                        var previous = Dictionary(uniqueKeysWithValues: self.meetings.map { ($0.id, $0) })
                        let updated = values.map { id, value in
                            let store = previous.removeValue(forKey: id) ?? SmartAgendaStore(groupID: self.groupID, uid: self.uid, id: id)
                            store.receive(value)
                            return store
                        }
                        for store in previous.values { store.receive(nil); store.stop() }
                        self.meetings = updated.sorted {
                            if $0.agenda?.meetingAt != $1.agenda?.meetingAt {
                                return ($0.agenda?.meetingAt ?? .distantPast) < ($1.agenda?.meetingAt ?? .distantPast)
                            }
                            return $0.id < $1.id
                        }
                        self.error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
    }

    func stop() {
        subscription = UUID()
        listener?.remove()
        listener = nil
        meetings.forEach { $0.stop() }
    }
}
