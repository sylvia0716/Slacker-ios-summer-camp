import Foundation

struct SmartAgenda: Decodable {
    struct EditableText {
        let original: String
        let displayed: String

        func valueToSave(_ edited: String) -> String {
            edited.trimmingCharacters(in: .whitespacesAndNewlines) == displayed.trimmingCharacters(in: .whitespacesAndNewlines)
                ? original : edited
        }
    }
    struct Attachment: Codable, Equatable {
        let fileName: String
        let storagePath: String
        let contentType: String
        let byteSize: Int64
    }
    struct Material: Decodable {
        let note: String
        let attachment: Attachment?
        let revision: String
        let membershipVersion: String
        let ownerUID: String?
        let createdAtMillis: Double?
    }
    struct MaterialEntry: Identifiable {
        let id: String
        let material: Material
    }
    struct MeetingLink: Decodable {
        let title: String
        let url: String
        let ownerUID: String
        let createdAtMillis: Double
        let revision: String

        var destination: URL? { Self.validURL(url) }
        var displayTitle: String { title.isEmpty ? destination?.host ?? url : title }

        static func validURL(_ text: String) -> URL? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count <= 2048, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                  let parts = URLComponents(string: value),
                  ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
                  let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
            return parts.url
        }
    }
    struct LinkEntry: Identifiable {
        let id: String
        let link: MeetingLink
    }
    struct Stage: Decodable, Identifiable {
        var id: Int { start }
        let start: Int
        let end: Int
        let title: String
        let goal: String
        let titleZhHant: String?
        let goalZhHant: String?
        var time: String { L10n.format("{0}–{1} 分鐘", String(start), String(end)) }
    }
    struct Generation: Decodable {
        let ownerUID: String?
        let expiresAt: Date
    }
    let topic: String
    let meetingAt: Date
    let duration: Int
    let meetingRevision: String
    let inputRevision: String
    let materials: [String: Material]
    let links: [String: MeetingLink]?
    let memberUIDs: [String]
    let preparedUIDs: [String]
    let stages: [Stage]
    let planState: String
    let planError: String?
    let planSource: String?
    let testFixture: String?
    let generation: Generation?
    let meetingStartedAt: Date?
    let updatedAt: Date?

    var allPrepared: Bool { !memberUIDs.isEmpty && preparedUIDs.count == memberUIDs.count }

    var meetingLinks: [LinkEntry] {
        (links ?? [:]).map { LinkEntry(id: $0.key, link: $0.value) }.sorted {
            $0.link.createdAtMillis == $1.link.createdAtMillis
                ? $0.id < $1.id : $0.link.createdAtMillis < $1.link.createdAtMillis
        }
    }

    func isGenerating(at date: Date) -> Bool {
        guard allPrepared, stages.isEmpty else { return false }
        return planState == "generating" && generation?.ownerUID != nil
            && (generation?.expiresAt ?? .distantPast) > date
    }

    func materials(for uid: String) -> [MaterialEntry] {
        materials.compactMap { id, material in
            (material.ownerUID ?? id) == uid ? MaterialEntry(id: id, material: material) : nil
        }.sorted {
            let first = $0.material.createdAtMillis ?? 0, second = $1.material.createdAtMillis ?? 0
            return first == second ? $0.id < $1.id : first < second
        }
    }

    // Translate only the known app-created fixture, never arbitrary member-authored content.
    private var isSampleFixture: Bool { testFixture == "smart-agenda-2026-09-26" }
    var displayTopic: String { isSampleFixture ? L10n.text(topic) : topic }
    func displayNote(_ note: String) -> String { isSampleFixture ? L10n.text(note) : note }
    var editableTopic: EditableText { .init(original: topic, displayed: displayTopic) }
    func editableNote(_ note: String) -> EditableText { .init(original: note, displayed: displayNote(note)) }
    func displayTitle(_ stage: Stage) -> String {
        if AppLanguageSettings.shared.language == .traditionalChinese, let value = stage.titleZhHant { return value }
        return isSampleFixture && planSource == "sample" ? L10n.text(stage.title) : stage.title
    }
    func displayGoal(_ stage: Stage) -> String {
        if AppLanguageSettings.shared.language == .traditionalChinese, let value = stage.goalZhHant { return value }
        return isSampleFixture && planSource == "sample" ? L10n.text(stage.goal) : stage.goal
    }
    var generationError: String? {
        guard planState == "failed" else { return nil }
        return "Apple Intelligence 暫時無法完成這次請求，請稍後再試。"
    }
    var summary: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM d EEE jm")
        return "\(formatter.string(from: meetingAt)) · \(L10n.format("{0} 分鐘", String(duration)))"
    }
}
