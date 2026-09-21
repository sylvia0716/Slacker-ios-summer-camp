import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum DeliverableSource: String, CaseIterable, Identifiable {
    case photo = "照片"
    case file = "檔案"
    case link = "連結"

    var id: Self { self }
}

private enum SubmissionState: Equatable {
    case waiting
    case preparing
    case uploading(Double)
    case success
    case failure(String)
}

@MainActor @Observable
private final class DeliverableSubmissionStore {
    private(set) var preparedAttachment: PreparedAttachment?
    private(set) var selectedFilename: String?
    private(set) var state: SubmissionState = .waiting

    @ObservationIgnored private let uploadService = AttachmentUploadService()

    var isBusy: Bool {
        switch state {
        case .preparing, .uploading: true
        default: false
        }
    }

    func reportUnavailableTask() {
        state = .failure(L10n.text("此任務尚未從雲端載入，請返回群組列表重新整理。"))
    }

    func resetSelection() {
        guard !isBusy else { return }
        preparedAttachment = nil
        selectedFilename = nil
        state = .waiting
    }

    func loadPhoto(from item: PhotosPickerItem) async {
        state = .preparing
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw DeliverableImageStoreError.invalidImage
            }
            let result = try DeliverableImageStore.compressedJPEG(from: data)
            guard result.data.count <= AttachmentUploadService.maximumFileSize else {
                throw AttachmentUploadError.fileTooLarge
            }
            preparedAttachment = PreparedAttachment(
                data: result.data,
                originalFilename: "photo.jpg",
                contentType: "image/jpeg",
                kind: .image
            )
            selectedFilename = L10n.text("成果照片.jpg")
            state = .waiting
        } catch {
            clearPreparedSelection()
            state = .failure(Self.message(for: error))
        }
    }

    func loadDocument(from url: URL) async {
        state = .preparing
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try Self.readDocument(at: url)
            }.value
            preparedAttachment = prepared
            selectedFilename = prepared.originalFilename
            state = .waiting
        } catch {
            clearPreparedSelection()
            state = .failure(Self.message(for: error))
        }
    }

    func submit(
        groupID: String,
        taskID: String,
        title: String,
        detail: String,
        link: String?,
        onSuccess: (Deliverable) -> Void
    ) async {
        guard !isBusy else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            state = .failure(L10n.text("請輸入成果標題。"))
            return
        }

        do {
            let attachment: TaskAttachment
            if let link {
                state = .uploading(0)
                attachment = try await uploadService.submitURL(
                    link.trimmingCharacters(in: .whitespacesAndNewlines),
                    groupID: groupID,
                    taskID: taskID,
                    title: normalizedTitle,
                    detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } else {
                guard let preparedAttachment else {
                    state = .failure(L10n.text("請先選擇照片或檔案。"))
                    return
                }
                state = .uploading(0)
                attachment = try await uploadService.upload(
                    preparedAttachment,
                    groupID: groupID,
                    taskID: taskID,
                    title: normalizedTitle,
                    detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
                ) { [weak self] progress in
                    self?.state = .uploading(progress)
                }
            }

            var cacheFilename: String?
            if attachment.kind == .image,
               let data = preparedAttachment?.data,
               let deliverableID = UUID(uuidString: attachment.id) {
                cacheFilename = try? DeliverableImageStore.save(data, deliverableID: deliverableID)
            }
            state = .success
            onSuccess(Deliverable(attachment: attachment, localImageFilename: cacheFilename))
        } catch {
            state = .failure(Self.message(for: error))
        }
    }

    private func clearPreparedSelection() {
        preparedAttachment = nil
        selectedFilename = nil
    }

    func handleSelectionFailure() {
        clearPreparedSelection()
        state = .failure(L10n.text("無法讀取選取的檔案，請重新選擇。"))
    }

    nonisolated private static func readDocument(at url: URL) throws -> PreparedAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let filename = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        guard let attributes = Self.documentAttributes(for: fileExtension) else {
            throw AttachmentUploadError.unsupportedFileType
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize,
           fileSize > AttachmentUploadService.maximumFileSize {
            throw AttachmentUploadError.fileTooLarge
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= AttachmentUploadService.maximumFileSize else {
            throw AttachmentUploadError.fileTooLarge
        }
        return PreparedAttachment(
            data: data,
            originalFilename: filename,
            contentType: attributes.contentType,
            kind: attributes.kind
        )
    }

    nonisolated private static func documentAttributes(
        for fileExtension: String
    ) -> (contentType: String, kind: AttachmentKind)? {
        switch fileExtension {
        case "pdf": ("application/pdf", .pdf)
        case "pptx": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", .presentation)
        case "docx": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", .document)
        case "xlsx": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", .spreadsheet)
        case "zip": ("application/zip", .archive)
        default: nil
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return L10n.text("操作失敗，請檢查網路後重新嘗試。")
    }
}

/// 群組頁與「我的任務」共用的成果送出介面。
struct DeliverableSubmissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: ProjectTask
    let onSubmit: (Deliverable) -> Void

    @State private var store = DeliverableSubmissionStore()
    @State private var source = DeliverableSource.photo
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var title = ""
    @State private var detail = ""
    @State private var link = ""

    private static let allowedDocumentTypes: [UTType] = ["pdf", "pptx", "docx", "xlsx", "zip"]
        .compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.format("成果任務：{0}", String(describing: task.title)))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.secondary)

                    Picker(L10n.text("成果類型"), selection: $source) {
                        ForEach(DeliverableSource.allCases) { option in
                            Text(L10n.text(option.rawValue)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(store.isBusy)

                    sourcePicker

                    field(title: L10n.text("成果標題")) {
                        TextField(L10n.text("例如：完成版簡報"), text: $title)
                            .textFieldStyle(.plain)
                    }

                    field(title: L10n.text("成果說明")) {
                        TextField(L10n.text("簡短說明這份成果"), text: $detail, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.plain)
                    }

                    statusView

                    Button(submitButtonTitle) {
                        Task { await submit() }
                    }
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? BombTheme.ink : Color.gray)
                    .clipShape(.capsule)
                    .disabled(!canSubmit)

                    if case .failure = store.state {
                        Button(L10n.text("重新嘗試")) {
                            Task { await submit() }
                        }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(BombTheme.yellow.opacity(0.6))
                        .clipShape(.capsule)
                        .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                        .disabled(store.isBusy)
                    }

                    Button(store.state == .success ? L10n.text("完成") : L10n.text("取消")) { dismiss() }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(BombTheme.paper.ignoresSafeArea())
            .navigationTitle(L10n.text("上傳成果"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .presentationDetents([.fraction(0.82)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .interactiveDismissDisabled(store.isBusy)
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: Self.allowedDocumentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case .failure = result { store.handleSelectionFailure() }
                return
            }
            Task {
                await store.loadDocument(from: url)
                if title.isEmpty, let filename = store.selectedFilename {
                    title = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                await store.loadPhoto(from: item)
                if title.isEmpty, store.selectedFilename != nil {
                    title = L10n.text("成果照片")
                }
            }
        }
        .onChange(of: source) {
            selectedPhoto = nil
            store.resetSelection()
        }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        switch source {
        case .photo:
            let previewData = store.preparedAttachment?.kind == .image
                ? store.preparedAttachment?.data
                : nil
            let pickerTitle = store.state == .preparing ? L10n.text("正在處理照片…") : L10n.text("選擇照片")
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                PhotoSelectionLabel(previewData: previewData, title: pickerTitle)
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)

        case .file:
            Button { showsFileImporter = true } label: {
                pickerPlaceholder(
                    icon: "doc.badge.plus",
                    title: store.selectedFilename ?? L10n.text("選擇 PDF、PPTX、DOCX、XLSX 或 ZIP")
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)

        case .link:
            field(title: L10n.text("HTTPS 網址")) {
                TextField("https://", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
            }
            .disabled(store.isBusy)
        }
    }

    private func pickerPlaceholder(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .black))
            Text(title)
                .font(.subheadline.weight(.black))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(BombTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .padding(.horizontal, 16)
        .background(BombTheme.yellow.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, style: StrokeStyle(lineWidth: 3, dash: [8])))
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.state {
        case .waiting:
            Label(
                source == .link || store.preparedAttachment != nil ? L10n.text("等待送出") : L10n.text("等待選擇"),
                systemImage: "clock"
            )
            .foregroundStyle(.secondary)
        case .preparing:
            Label(L10n.text("正在準備檔案…"), systemImage: "hourglass")
                .foregroundStyle(BombTheme.ink)
        case let .uploading(progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(source == .link ? L10n.text("正在儲存連結…") : L10n.text("正在上傳…"))
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.black))
                ProgressView(value: progress)
                    .tint(BombTheme.red)
            }
        case .success:
            Label(L10n.text("上傳成功"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.black))
                .foregroundStyle(BombTheme.green)
        case let .failure(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(BombTheme.red)
        }
    }

    private var canSubmit: Bool {
        guard !store.isBusy, store.state != .success,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if source == .link {
            return !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return store.preparedAttachment != nil
    }

    private var submitButtonTitle: String {
        switch store.state {
        case .uploading: L10n.text("正在上傳")
        case .success: L10n.text("已送出")
        default: L10n.text("送出成果")
        }
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline.weight(.black))
            content()
                .padding(13)
                .background(.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(BombTheme.ink, lineWidth: 2))
        }
    }

    private func submit() async {
        guard let groupID = task.firestoreGroupID, let taskID = task.firestoreDocumentID else {
            store.reportUnavailableTask()
            return
        }
        await store.submit(
            groupID: groupID,
            taskID: taskID,
            title: title,
            detail: detail,
            link: source == .link ? link : nil,
            onSuccess: onSubmit
        )
    }
}

private struct PhotoSelectionLabel: View {
    let previewData: Data?
    let title: String

    var body: some View {
        if let previewData, let image = UIImage(data: previewData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, lineWidth: 3))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 32, weight: .black))
                Text(title)
                    .font(.subheadline.weight(.black))
            }
            .foregroundStyle(BombTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(BombTheme.yellow.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, style: StrokeStyle(lineWidth: 3, dash: [8])))
        }
    }
}
