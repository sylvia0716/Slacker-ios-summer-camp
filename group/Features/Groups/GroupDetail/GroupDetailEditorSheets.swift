import SwiftUI

struct DeadlineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var deadline: Date
    let onSave: () -> Void

    var body: some View {
        BombFormSheet(title: L10n.text("修改截止時間")) {
            DatePicker(
                L10n.text("截止時間"),
                selection: $deadline,
                in: Date.now...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .bombFormField()
        } actions: {
            BombFormActions(
                primaryTitle: L10n.text("儲存"),
                isEnabled: deadline > .now,
                onPrimary: onSave,
                onSecondary: { dismiss() }
            )
        }
        .presentationDetents([.medium])
    }
}

struct GroupNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    let onSave: () -> Void

    var body: some View {
        BombFormSheet(title: L10n.text("修改群組名稱")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("群組名稱"))
                    .font(.subheadline.weight(.black))
                TextField(L10n.text("群組名稱"), text: $name)
                    .bombFormField()
            }
        } actions: {
            BombFormActions(
                primaryTitle: L10n.text("儲存"),
                isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onPrimary: onSave,
                onSecondary: { dismiss() }
            )
        }
        .presentationDetents([.medium])
    }
}
