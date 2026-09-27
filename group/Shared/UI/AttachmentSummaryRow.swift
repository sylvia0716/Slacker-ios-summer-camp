import SwiftUI

/// Shared attachment presentation in delivery and attachment editing.
struct AttachmentSummaryRow: View {
    let model: GroupBombModel
    let taskID: UUID
    let deliverable: Deliverable

    var body: some View {
        HStack(spacing: 12) {
            AttachmentPhotoThumbnail(model: model, taskID: taskID, deliverable: deliverable)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                Text(deliverable.title)
                    .font(.subheadline.weight(.black))
                    .fixedSize(horizontal: false, vertical: true)
                Text(deliverable.submittedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
                    .font(.footnote.weight(.bold)).foregroundStyle(BombTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.down.to.line")
                .font(.title3.weight(.bold))
        }
        .padding(10)
        .background(BombTheme.paper, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(BombTheme.ink.opacity(0.12), lineWidth: 1))
        .foregroundStyle(BombTheme.ink)
    }
}
