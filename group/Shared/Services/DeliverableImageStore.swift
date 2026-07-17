import Foundation
import UIKit

enum DeliverableImageStoreError: LocalizedError {
    case invalidImage
    case compressionFailed
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidImage: "無法載入這張照片，請改選另一張"
        case .compressionFailed: "照片處理失敗，請再試一次"
        case .cacheUnavailable: "照片儲存失敗，請再試一次"
        }
    }
}

/// Session-only MVP image storage. Deliverable keeps only the generated cache filename.
enum DeliverableImageStore {
    static func compressedJPEG(from data: Data, maxDimension: CGFloat = 1_600) throws -> (image: UIImage, data: Data) {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
            throw DeliverableImageStoreError.invalidImage
        }

        let longestSide = max(source.size.width, source.size.height)
        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpeg = resized.jpegData(compressionQuality: 0.75) else {
            throw DeliverableImageStoreError.compressionFailed
        }
        return (resized, jpeg)
    }

    static func save(_ data: Data, deliverableID: UUID) throws -> String {
        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw DeliverableImageStoreError.cacheUnavailable
        }
        let filename = "deliverable-\(deliverableID.uuidString.lowercased()).jpg"
        do {
            try data.write(to: cache.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            throw DeliverableImageStoreError.cacheUnavailable
        }
    }

    static func image(named filename: String) -> UIImage? {
        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return UIImage(contentsOfFile: cache.appendingPathComponent(filename).path)
    }
}
