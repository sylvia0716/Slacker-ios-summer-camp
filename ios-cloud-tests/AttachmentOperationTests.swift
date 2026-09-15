import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct AttachmentOperationTests {
    func file() -> TaskAttachment {
        let g = UUID().uuidString.lowercased(), t = UUID().uuidString.lowercased(), a = UUID().uuidString.lowercased()
        return TaskAttachment(id: a, taskID: t, groupID: g, uploaderID: "uploader",
                              title: "PDF", kind: .pdf,
                              storagePath: "groups/\(g)/tasks/\(t)/attachments/\(a)/report-12345678.pdf",
                              contentType: "application/pdf", byteSize: 3, status: .ready)
    }

    @Test func downloadCreatesAndCleansLocalFile() async throws {
        let service = AttachmentDownloadService(client: .init(currentUID: { "member" }, write: { _, url, progress in
            try Data([1, 2, 3]).write(to: url)
            progress(0.5)
        }))
        var progress = 0.0
        let url = try await service.download(file()) { progress = $0 }
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(progress == 1)
        AttachmentDownloadService.removeLocalFile(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func accountSwitchDiscardsDownloadedFile() async {
        var uid: String? = "A"
        var writtenURL: URL?
        let service = AttachmentDownloadService(client: .init(currentUID: { uid }, write: { _, url, _ in
            writtenURL = url
            try Data([1, 2, 3]).write(to: url)
            uid = "B"
        }))
        await #expect(throws: AttachmentOperationError.accountChanged) { try await service.download(file()) { _ in } }
        #expect(writtenURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func invalidDownloadSizeCleansFile() async {
        var writtenURL: URL?
        let service = AttachmentDownloadService(client: .init(currentUID: { "A" }, write: { _, url, _ in
            writtenURL = url
            try Data([1]).write(to: url)
        }))
        await #expect(throws: AttachmentOperationError.invalidFile) { try await service.download(file()) { _ in } }
        #expect(writtenURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func signedOutNeverAccessesBackend() async {
        let service = AttachmentDeletionService(client: .init(currentUID: { nil }, deleteObject: { _ in Issue.record("Unexpected write") }, deleteMetadata: { _ in Issue.record("Unexpected write") }))
        await #expect(throws: AttachmentOperationError.signedOut) { try await service.delete(file()) }
    }

    @Test func leaderIsNotBlockedByClientOwnershipCheck() async throws {
        var calls: [String] = []
        let service = AttachmentDeletionService(client: .init(currentUID: { "leader" }, deleteObject: { _ in calls.append("storage") }, deleteMetadata: { item in
            #expect(item.uploaderID == "uploader")
            calls.append("metadata")
        }))
        try await service.delete(file())
        #expect(calls == ["storage", "metadata"])
    }

    @Test func permissionDeniedStopsBeforeMetadata() async {
        let service = AttachmentDeletionService(client: .init(currentUID: { "member" }, deleteObject: { _ in throw AttachmentOperationError.permissionDenied }, deleteMetadata: { _ in Issue.record("Must not delete metadata") }))
        await #expect(throws: AttachmentOperationError.permissionDenied) { try await service.delete(file()) }
    }

    @Test func partialDeletionCanBeRetried() async throws {
        var objectExists = true, attempts = 0
        let service = AttachmentDeletionService(client: .init(currentUID: { "uploader" }, deleteObject: { _ in
            if !objectExists { throw AttachmentOperationError.notFound }
            objectExists = false
        }, deleteMetadata: { _ in
            attempts += 1
            if attempts == 1 { throw AttachmentOperationError.network }
        }))
        let attachment = file()
        await #expect(throws: AttachmentOperationError.metadataPending(AttachmentOperationError.network.localizedDescription)) { try await service.delete(attachment) }
        try await service.delete(attachment)
        #expect(attempts == 2)
    }

    @Test func URLDeletionOnlyDeletesMetadata() async throws {
        var deleted = false
        var attachment = file()
        attachment.kind = .externalLink
        attachment.storagePath = nil
        attachment.externalURL = "https://example.org"
        let service = AttachmentDeletionService(client: .init(currentUID: { "leader" }, deleteObject: { _ in Issue.record("Must not access Storage") }, deleteMetadata: { _ in deleted = true }))
        try await service.delete(attachment)
        #expect(deleted)
    }

    @Test func interactionPreventsDuplicateSubmissionAndReportsFailure() async {
        let state = AttachmentActionStore()
        var calls = 0
        let remove: (TaskAttachment) async throws -> Void = { _ in
            calls += 1
            throw AttachmentOperationError.permissionDenied
        }
        let download: (TaskAttachment, @escaping @MainActor (Double) -> Void) async throws -> URL = { _, _ in
            throw AttachmentOperationError.network
        }
        state.run(delete: true, attachment: file(), download: download, remove: remove)
        state.run(delete: true, attachment: file(), download: download, remove: remove)
        for _ in 0..<100 where state.isWorking { await Task.yield() }
        #expect(calls == 1)
        #expect(state.errorMessage == AttachmentOperationError.permissionDenied.localizedDescription)
        #expect(state.successMessage == nil)
    }

    @Test func cancellationPreventsLatePreview() async {
        let state = AttachmentActionStore()
        var continuation: CheckedContinuation<URL, Never>?
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("group-bomb-attachments").appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("attachment.pdf")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data([1, 2, 3]).write(to: url)
        state.run(delete: false, attachment: file(), download: { _, _ in
            await withCheckedContinuation { continuation = $0 }
        }, remove: { _ in })
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        state.cancel()
        continuation?.resume(returning: url)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: url.path) { await Task.yield() }
        #expect(state.previewURL == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!state.isWorking)
    }
}
