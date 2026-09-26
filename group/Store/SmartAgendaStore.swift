import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation
import Observation

@MainActor @Observable
final class SmartAgendaStore {
    let groupID: String
    let uid: String
    private(set) var agenda: SmartAgenda?
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var isGenerating = false
    private(set) var isDownloading = false
    var error: String?
    var aiError: String?
    var previewURL: URL?
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var subscription = UUID()
    @ObservationIgnored private var downloadedFiles: [URL] = []
    @ObservationIgnored private var pendingUploads: [String: PendingUpload] = [:]
    private struct PendingUpload {
        let url: URL
        let modifiedAt: Date?
        let size: Int
        let attachment: SmartAgenda.Attachment
    }
    private var document: DocumentReference {
        Firestore.firestore().collection("groups").document(groupID).collection("smartAgenda").document("current")
    }

    init(groupID: String, uid: String) { self.groupID = groupID; self.uid = uid }

    func listen() {
        guard listener == nil, Auth.auth().currentUser?.uid == uid else { return }
        isLoading = true
        let token = UUID()
        subscription = token
        listener = document.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                guard let self, self.subscription == token, Auth.auth().currentUser?.uid == self.uid else { return }
                self.isLoading = false
                if let error { self.error = error.localizedDescription; return }
                do {
                    let value = try snapshot?.exists == true ? snapshot?.data(as: SmartAgenda.self) : nil
                    if value?.inputRevision != self.agenda?.inputRevision { self.aiError = nil }
                    self.agenda = value
                    self.error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    func stop() {
        subscription = UUID()
        listener?.remove()
        listener = nil
        for url in downloadedFiles { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        downloadedFiles = []
    }

    @discardableResult
    private func call(_ action: String, _ fields: [String: Any] = [:]) async throws -> [String: Any] {
        guard Auth.auth().currentUser?.uid == uid else { throw AgendaError.signedOut }
        var payload = fields
        payload["action"] = action
        payload["groupID"] = groupID
        let response = try await Functions.functions(region: "asia-east1").httpsCallable("updateSmartAgenda").call(payload)
        guard Auth.auth().currentUser?.uid == uid else { throw AgendaError.signedOut }
        guard let data = response.data as? [String: Any] else { throw AgendaError.invalidResponse }
        return data
    }

    func saveMeeting(topic: String, date: Date, duration: Int, revision: String?) async throws {
        guard !isSaving else { throw AgendaError.saving }
        isSaving = true
        defer { isSaving = false }
        try await call("meeting", ["topic": topic, "meetingAtMillis": date.timeIntervalSince1970 * 1000,
                                  "duration": duration, "expectedRevision": revision as Any? ?? NSNull()])
    }

    func saveLink(id: String, title: String, url: String, revision: String?) async throws {
        guard !isSaving else { throw AgendaError.saving }
        isSaving = true
        defer { isSaving = false }
        try await call("link", ["linkID": id, "title": title, "url": url,
                               "expectedRevision": revision as Any? ?? NSNull()])
    }

    func saveMaterial(id: String, note: String, attachment: SmartAgenda.Attachment?, file: URL?, revision: String?) async throws {
        guard !isSaving else { throw AgendaError.saving }
        isSaving = true
        defer { isSaving = false }
        var uploaded: SmartAgenda.Attachment?
        var submitted = false
        do {
            if let file { uploaded = try await upload(file, materialID: id) }
            let selected = uploaded ?? attachment
            var metadata: Any = NSNull()
            if let selected { metadata = try JSONSerialization.jsonObject(with: JSONEncoder().encode(selected)) }
            submitted = true
            try await call("material", ["materialID": id, "note": note, "attachment": metadata,
                                       "expectedRevision": revision as Any? ?? NSNull()])
            pendingUploads[id] = nil
        } catch {
            // A response can be lost after the write commits. Verify the exact record before retrying.
            if submitted, Auth.auth().currentUser?.uid == uid,
               let snapshot = try? await document.getDocument(source: .server),
               Auth.auth().currentUser?.uid == uid {
                let latest = try? snapshot.data(as: SmartAgenda.self)
                if let saved = latest?.materials[id], (saved.ownerUID ?? id) == uid,
                   saved.note == note.trimmingCharacters(in: .whitespacesAndNewlines),
                   saved.attachment == (uploaded ?? attachment) {
                    agenda = latest
                    pendingUploads[id] = nil
                    return
                }
                if let latest, latest.materials[id] == nil, revision != nil,
                   note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   uploaded == nil, attachment == nil {
                    agenda = latest
                    pendingUploads[id] = nil
                    return
                }
                // A timed-out callable may still commit after this read. Clean up only definite rejections.
                let failure = error as NSError
                let rejected = failure.domain == FunctionsErrorDomain && [
                    FunctionsErrorCode.invalidArgument, .permissionDenied, .failedPrecondition,
                    .aborted, .notFound, .unauthenticated
                ].contains { $0.rawValue == failure.code }
                if rejected, let uploaded,
                   !snapshot.exists || (latest != nil && latest?.materials.values.contains(where: { $0.attachment?.storagePath == uploaded.storagePath }) == false) {
                    try? await Storage.storage().reference(withPath: uploaded.storagePath).delete()
                    pendingUploads[id] = nil
                }
            }
            throw error
        }
    }

    private func upload(_ url: URL, materialID: String) async throws -> SmartAgenda.Attachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard let type = Self.fileTypes[ext] else { throw AgendaError.unsupportedFile }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = attributes.fileSize ?? 0
        guard size > 0, size <= 20 * 1024 * 1024 else { throw AgendaError.fileSize }
        // Keep the exact uploaded object after an uncertain response so a retry is idempotent.
        if let pending = pendingUploads[materialID], pending.url == url,
           pending.size == size, pending.modifiedAt == attributes.contentModificationDate {
            return pending.attachment
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 20 * 1024 * 1024 else { throw AgendaError.fileSize }
        let path = "groups/\(groupID)/agendaMaterials/\(uid)/\(UUID().uuidString.lowercased())/file.\(ext)"
        let metadata = StorageMetadata()
        metadata.contentType = type
        metadata.customMetadata = ["uploaderID": uid]
        _ = try await Storage.storage().reference(withPath: path).putDataAsync(data, metadata: metadata)
        let attachment = SmartAgenda.Attachment(fileName: url.lastPathComponent, storagePath: path,
                                               contentType: type, byteSize: Int64(data.count))
        pendingUploads[materialID] = PendingUpload(url: url, modifiedAt: attributes.contentModificationDate,
                                                 size: size, attachment: attachment)
        return attachment
    }

    func download(_ file: SmartAgenda.Attachment) async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            guard Auth.auth().currentUser?.uid == uid,
                  file.storagePath.hasPrefix("groups/\(groupID)/agendaMaterials/"),
                  file.byteSize > 0, file.byteSize <= 20 * 1024 * 1024 else { throw AgendaError.invalidResponse }
            let reference = Storage.storage().reference(withPath: file.storagePath)
            let metadata = try await reference.getMetadata()
            guard metadata.size == file.byteSize, metadata.contentType == file.contentType else { throw AgendaError.invalidResponse }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(URL(fileURLWithPath: file.fileName).lastPathComponent)
            downloadedFiles.append(url)
            _ = try await reference.writeAsync(toFile: url)
            guard Auth.auth().currentUser?.uid == uid else { throw AgendaError.signedOut }
            previewURL = url
        } catch { self.error = error.localizedDescription }
    }

    func retryGeneration() async {
        guard let agenda, agenda.allPrepared, agenda.stages.isEmpty, !isGenerating else { return }
        aiError = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            try await call("retry")
        } catch {
            if !Task.isCancelled { aiError = error.localizedDescription }
        }
    }

    func startMeeting() async throws {
        guard let revision = agenda?.inputRevision else { return }
        try await call("start", ["inputRevision": revision])
    }
    func endMeeting() async throws {
        guard let revision = agenda?.inputRevision else { return }
        try await call("end", ["inputRevision": revision])
    }

    static let fileTypes = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "pdf": "application/pdf",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "zip": "application/zip", "mov": "video/quicktime", "mp4": "video/mp4"
    ]
}

private enum AgendaError: LocalizedError {
    case signedOut, invalidResponse, unsupportedFile, fileSize, saving
    var errorDescription: String? {
        switch self {
        case .signedOut: "Please sign in again."
        case .invalidResponse: "Could not load the agenda. Please try again."
        case .unsupportedFile: "Choose a PNG, JPG, PDF, Word, PowerPoint, Excel, ZIP, MOV or MP4 file."
        case .fileSize: "Choose a non-empty file up to 20 MB."
        case .saving: "儲存中…"
        }
    }
}
