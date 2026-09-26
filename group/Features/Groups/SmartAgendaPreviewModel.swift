#if DEBUG
import Foundation
import Observation

/// Local-only data for reviewing Smart Agenda; no Firebase or AI requests.
@MainActor @Observable
final class SmartAgendaPreviewModel {
    struct Person: Identifiable {
        let id: String
        let name: String
    }

    struct Material {
        var note = ""
        var fileName: String?
        var fileURL: URL?
        var isPrepared: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fileName != nil }
    }

    struct Stage: Identifiable {
        var id: Int { start }
        let start: Int
        let end: Int
        let title: String
        let goal: String
        var time: String { "\(start)–\(end) min" }
    }

    let projectName = "大家來測試 🤠"
    let projectCode = "RM4RHR"
    let projectProgress = 25
    let countdownDays = "5"
    let countdownHours = "20"
    let countdownMinutes = "02"
    let members = [Person(id: "mia", name: "Mia"), Person(id: "alex", name: "Alex"),
                   Person(id: "jamie", name: "Jamie"), Person(id: "sam", name: "Sam")]
    let leaderID = "mia"
    var currentMemberID = "mia"
    var topic = "Finalize Our Demo"
    var meetingDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 15))!
    var duration = 20
    var materials: [String: Material]
    var stages: [Stage] = []
    var isGenerating = false
    var preparationRevision = 0
    var replayRevision = 0
    var isPlaying = false
    var meetingStartedAt: Date?

    static let sampleMaterials: [String: Material] = [
        "mia": Material(note: "Check the opening and runtime.", fileName: "Demo Flow.mov"),
        "alex": Material(note: "Let’s focus on feature order.", fileName: "Feature Priorities.pdf"),
        "jamie": Material(note: "I drafted a shorter narration.", fileName: "Narration Draft.docx"),
        "sam": Material(note: "I collected the visual references.", fileName: "Visual References.zip")
    ]

    init() {
        materials = Self.sampleMaterials
        stages = makeSamplePlan()
    }

    var isLeader: Bool { currentMemberID == leaderID }
    var currentMember: Person { members.first { $0.id == currentMemberID }! }
    var preparedMembers: [Person] { members.filter { materials[$0.id]?.isPrepared == true } }
    var preparedCount: Int { preparedMembers.count }
    var allPrepared: Bool { !members.isEmpty && preparedCount == members.count }
    var myMaterial: Material { materials[currentMemberID] ?? Material() }
    var meetingSummary: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return "\(formatter.string(from: meetingDate)) · \(duration) min"
    }

    func saveMeeting(topic: String, date: Date, duration: Int) {
        guard isLeader, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingDate = date
        self.duration = duration
        invalidatePlan()
    }

    func saveMyMaterial(_ material: Material) {
        materials[currentMemberID] = material.isPrepared ? material : nil
        invalidatePlan()
    }

    func invalidatePlan() {
        stages = []
        meetingStartedAt = nil
        isGenerating = allPrepared
        preparationRevision += 1
    }

    func generatePreviewPlan() async {
        guard allPrepared, stages.isEmpty else { return }
        let revision = preparationRevision
        isGenerating = true
        do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
        guard !Task.isCancelled, allPrepared, revision == preparationRevision else { return }
        stages = makeSamplePlan()
        isGenerating = false
    }

    func replayPreparation() async {
        guard replayRevision > 0 else { return }
        isPlaying = true
        materials = [:]
        invalidatePlan()
        defer { isPlaying = false }
        for member in members {
            do { try await Task.sleep(for: .seconds(1.0)) } catch { return }
            guard !Task.isCancelled else { return }
            materials[member.id] = Self.sampleMaterials[member.id]
            invalidatePlan()
        }
    }

    func showCompletedExample() {
        materials = Self.sampleMaterials
        stages = makeSamplePlan()
        isGenerating = false
        preparationRevision += 1
    }

    /// Sample copy only. Boundaries always start at zero and end at the chosen duration.
    private func makeSamplePlan() -> [Stage] {
        let fourStages = duration > 30
        let titles = fourStages
            ? ["Review prepared materials", "Decide feature order", "Resolve open questions", "Finalize and assign"]
            : ["Review prepared materials", "Decide feature order", "Finalize and assign"]
        let goals = fourStages
            ? ["Confirm the opening and runtime", "Choose the key features", "Agree on the remaining decisions", "Approve the script and assign revisions"]
            : ["Confirm the opening and runtime", "Choose the key features", "Approve the script and assign revisions"]
        let weights = fourStages ? [0.2, 0.3, 0.3, 0.2] : [0.25, 0.35, 0.4]
        var start = 0
        return titles.indices.map { index in
            let end = index == titles.count - 1 ? duration : start + max(1, Int(Double(duration) * weights[index]))
            defer { start = end }
            return Stage(start: start, end: end, title: titles[index], goal: goals[index])
        }
    }
}
#endif
