import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedAttachment: Sendable {
    let data: Data
    let originalFilename: String
    let contentType: String
    let kind: AttachmentKind
}

/// Coordinates reads with Files providers, including documents downloaded from iCloud.
enum AttachmentDocumentReader {
    nonisolated static func readPhoto(_ data: Data) throws -> PreparedAttachment {
        guard !data.isEmpty else { throw DocumentReadError.empty }
        guard data.count <= AttachmentFilePolicy.maximumSize else { throw DocumentReadError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) else { throw DocumentReadError.unsupported }
        let identifier = type as String
        guard identifier == UTType.png.identifier || identifier == UTType.jpeg.identifier else {
            throw DocumentReadError.unsupportedPhoto
        }
        let isPNG = identifier == UTType.png.identifier
        return PreparedAttachment(data: data, originalFilename: isPNG ? "photo.png" : "photo.jpg",
                                  contentType: isPNG ? "image/png" : "image/jpeg", kind: .image)
    }

    nonisolated static func read(at url: URL) throws -> PreparedAttachment {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let types: [String: (String, AttachmentKind)] = [
            "png": ("image/png", .image),
            "jpg": ("image/jpeg", .image),
            "jpeg": ("image/jpeg", .image),
            "pdf": ("application/pdf", .pdf),
            "pptx": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", .presentation),
            "docx": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", .document),
            "xlsx": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", .spreadsheet),
            "zip": ("application/zip", .archive)
        ]
        guard let (contentType, kind) = types[url.pathExtension.lowercased()] else {
            throw DocumentReadError.unsupported
        }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { file in
            result = Result {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw DocumentReadError.empty }
                guard (values.fileSize ?? 0) <= AttachmentFilePolicy.maximumSize else { throw DocumentReadError.tooLarge }
                let data = try Data(contentsOf: file)
                guard !data.isEmpty else { throw DocumentReadError.empty }
                guard data.count <= AttachmentFilePolicy.maximumSize else { throw DocumentReadError.tooLarge }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw DocumentReadError.unavailable }
        let data = try result.get()
        if kind == .image {
            let photo = try readPhoto(data)
            guard photo.contentType == contentType else { throw DocumentReadError.unsupportedPhoto }
        }
        return PreparedAttachment(data: data, originalFilename: url.lastPathComponent,
                                  contentType: contentType, kind: kind)
    }
}

enum DocumentReadError: LocalizedError {
    case unsupported, unsupportedPhoto, empty, tooLarge, unavailable
    var errorDescription: String? {
        switch self {
        case .unsupported: "僅支援 PNG、JPG、PDF、PPTX、DOCX、XLSX 和 ZIP。"
        case .unsupportedPhoto: "請選擇 PNG 或 JPG 照片。"
        case .empty: "檔案沒有可上傳的內容，請重新選擇。"
        case .tooLarge: "檔案不可超過 20 MB。"
        case .unavailable: "無法讀取檔案，請確認檔案已下載後重試。"
        }
    }
}
