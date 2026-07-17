import PhotosUI
import SwiftUI
import UIKit

struct DeliverablePhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: ProjectTask
    let onSubmit: (Deliverable) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var compressedData: Data?
    @State private var title = ""
    @State private var detail = ""
    @State private var errorMessage: String?
    @State private var isLoadingPhoto = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("成果任務：\(task.title)")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.secondary)

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 210)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, lineWidth: 3))
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 34, weight: .black))
                                Text(isLoadingPhoto ? "正在處理照片…" : "選擇照片")
                                    .font(.headline.weight(.black))
                            }
                            .foregroundStyle(BombTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .background(BombTheme.yellow.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, style: StrokeStyle(lineWidth: 3, dash: [8])))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingPhoto)

                    field(title: "成果標題") {
                        TextField("例如：完成版簡報", text: $title)
                            .textFieldStyle(.plain)
                    }

                    field(title: "成果說明") {
                        TextField("簡短說明這張成果照片", text: $detail, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.plain)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BombTheme.red)
                    }

                    Button("送出成果") { submit() }
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? BombTheme.ink : Color.gray)
                        .clipShape(.capsule)
                        .disabled(!canSubmit)

                    Button("取消") { dismiss() }
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(BombTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(BombTheme.paper.ignoresSafeArea())
            .navigationTitle("上傳成果照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .presentationDetents([.fraction(0.72)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            loadPhoto(from: newItem)
        }
    }

    private var canSubmit: Bool {
        previewImage != nil && compressedData != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoadingPhoto
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

    private func loadPhoto(from item: PhotosPickerItem) {
        isLoadingPhoto = true
        errorMessage = nil
        previewImage = nil
        compressedData = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw DeliverableImageStoreError.invalidImage
                }
                let result = try DeliverableImageStore.compressedJPEG(from: data)
                await MainActor.run {
                    previewImage = result.image
                    compressedData = result.data
                    isLoadingPhoto = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "照片載入失敗，請再試一次"
                    isLoadingPhoto = false
                }
            }
        }
    }

    private func submit() {
        guard let compressedData else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliverableID = UUID()
        do {
            let filename = try DeliverableImageStore.save(compressedData, deliverableID: deliverableID)
            onSubmit(
                Deliverable(
                    id: deliverableID,
                    title: trimmedTitle,
                    detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                    url: nil,
                    localImageFilename: filename,
                    submittedAt: .now,
                    isApproved: false
                )
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "照片儲存失敗，請再試一次"
        }
    }
}
