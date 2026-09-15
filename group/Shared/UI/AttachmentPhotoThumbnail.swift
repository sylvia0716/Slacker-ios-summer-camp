import SwiftUI
import UIKit
import ImageIO

/// Authenticated image thumbnail. No public download URL or persistent cross-account image cache.
struct AttachmentPhotoThumbnail: View {
    let model: GroupBombModel
    let taskID: UUID
    let deliverable: Deliverable
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var loading = false
    @State private var failed = false

    private var attachment: TaskAttachment? {
        model.attachmentsByTaskID[taskID]?.first { $0.id == deliverable.attachmentID && $0.kind == .image }
    }

    private var requestKey: String {
        "\(model.firebaseUID ?? "")/\(attachment?.id ?? "")/\(scenePhase == .active)"
    }

    var body: some View {
        SwiftUI.Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if loading {
                ProgressView().tint(BombTheme.ink)
            } else {
                Image(systemName: failed ? "arrow.clockwise" : "photo")
                    .font(.title2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(failed ? "縮圖載入失敗，點擊下載預覽" : "成果照片預覽")
        .task(id: requestKey) {
            image = nil
            loading = false
            failed = false
            guard scenePhase == .active else { return }
            // Existing local/demo images retain their original behavior.
            if deliverable.attachmentID == nil {
                if let filename = deliverable.localImageFilename {
                    image = DeliverableImageStore.image(named: filename)
                }
                return
            }
            guard let attachment, model.firebaseUID != nil else { return }
            let key = requestKey
            loading = true
            do {
                let url = try await model.downloadAttachment(attachment) { _ in }
                defer { AttachmentDownloadService.removeLocalFile(url) }
                guard !Task.isCancelled, requestKey == key else { return }
                // Decode a small image instead of retaining a full-resolution photo per card.
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 320
                      ] as CFDictionary) else { throw AttachmentOperationError.invalidFile }
                image = UIImage(cgImage: thumbnail)
                loading = false
            } catch {
                guard !Task.isCancelled, requestKey == key else { return }
                loading = false
                failed = true
            }
        }
        .onDisappear { image = nil }
    }
}
