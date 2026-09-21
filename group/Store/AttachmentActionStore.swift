import Foundation
import Observation

/// Per-result interaction state. Firebase access stays in AppStore/services.
@MainActor @Observable
final class AttachmentActionStore {
    private(set) var isWorking = false
    private(set) var progress = 0.0
    private(set) var isDeleting = false
    var errorMessage: String?
    var previewURL: URL?
    var externalURL: URL?
    var successMessage: String?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cachedURL: URL?

    func run(delete: Bool, attachment: TaskAttachment,
             download: @escaping (TaskAttachment, @escaping @MainActor (Double) -> Void) async throws -> URL,
             remove: @escaping (TaskAttachment) async throws -> Void) {
        guard !isWorking else { return }
        let version = UUID()
        generation = version
        isWorking = true
        isDeleting = delete
        progress = 0
        errorMessage = nil
        successMessage = nil
        work = Task {
            do {
                if delete {
                    try await remove(attachment)
                } else if attachment.kind == .externalLink {
                    guard let raw = attachment.externalURL, let url = URL(string: raw),
                          url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
                        throw AttachmentOperationError.invalidFile
                    }
                    guard generation == version, !Task.isCancelled else { return }
                    externalURL = url
                } else {
                    let file = try await download(attachment) { [weak self] value in
                        guard let self, self.generation == version else { return }
                        self.progress = min(max(value, 0), 1)
                    }
                    guard generation == version, !Task.isCancelled else {
                        AttachmentDownloadService.removeLocalFile(file)
                        return
                    }
                    clearPreview()
                    cachedURL = file
                    previewURL = file
                }
                guard generation == version, !Task.isCancelled else { return }
                successMessage = delete ? L10n.text("附件已刪除") : nil
            } catch {
                guard generation == version, !Task.isCancelled else { return }
                errorMessage = (error as? AttachmentOperationError)?.localizedDescription
                    ?? AttachmentOperationError.network.localizedDescription
            }
            if generation == version { isWorking = false }
        }
    }

    func clearPreview() {
        previewURL = nil
        if let cachedURL { AttachmentDownloadService.removeLocalFile(cachedURL) }
        cachedURL = nil
    }

    func cancel() {
        generation = UUID()
        work?.cancel()
        work = nil
        isWorking = false
        errorMessage = nil
        externalURL = nil
        successMessage = nil
        clearPreview()
    }
}
