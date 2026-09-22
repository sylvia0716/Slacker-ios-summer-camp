import Foundation
import Testing
@testable import GroupCloudData

struct AttachmentDocumentReaderTests {
    @Test func preservesContentsAndOriginalFilename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for ext in ["PDF", "docx", "xlsx", "pptx", "zip"] {
            let url = root.appendingPathComponent("測試附件.\(ext)")
            let bytes = Data([1, 2, 3, 4])
            try bytes.write(to: url)
            let file = try AttachmentDocumentReader.read(at: url)
            #expect(file.data == bytes)
            #expect(file.originalFilename == url.lastPathComponent)
            #expect(!file.contentType.isEmpty)
        }
    }

    @Test func rejectsEmptyUnsupportedAndOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, size) in [("empty.pdf", 0), ("script.exe", 1), ("large.zip", 20 * 1024 * 1024 + 1)] {
            let url = root.appendingPathComponent(name)
            try Data(repeating: 0, count: size).write(to: url)
            #expect(throws: DocumentReadError.self) { try AttachmentDocumentReader.read(at: url) }
        }
    }

    @Test func photosPreserveOriginalBytesAndTypes() throws {
        do {
            let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP8zwACTGCSAQANHQEDgslx/wAAAABJRU5ErkJggg==")!
            let photo = try AttachmentDocumentReader.readPhoto(bytes)
            #expect(photo.data == bytes)
            #expect(photo.contentType == "image/png")
            #expect(photo.originalFilename == "photo.png")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: url) }
            try bytes.write(to: url)
            #expect(try AttachmentDocumentReader.read(at: url).data == bytes)
        }
        do {
            let bytes = Data(base64Encoded: "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAACAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDi6KKK+ZP3E//Z")!
            let photo = try AttachmentDocumentReader.readPhoto(bytes)
            #expect(photo.data == bytes)
            #expect(photo.contentType == "image/jpeg")
            #expect(photo.originalFilename == "photo.jpg")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            defer { try? FileManager.default.removeItem(at: url) }
            try bytes.write(to: url)
            #expect(try AttachmentDocumentReader.read(at: url).data == bytes)
        }
    }
}
