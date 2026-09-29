import Foundation

struct InboxNotification: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case applicationPending, applicationApproved, applicationRejected, admissionReview
        case pokeThreshold, meeting, taskDeadline, projectDeadline, reviewAvailable, reviewReminder

        var symbol: String {
            switch self {
            case .applicationPending: "clock"
            case .applicationApproved: "checkmark.circle.fill"
            case .applicationRejected: "xmark.circle"
            case .admissionReview: "person.badge.clock"
            case .pokeThreshold: "hand.tap.fill"
            case .meeting: "calendar"
            case .taskDeadline: "checklist"
            case .projectDeadline: "hourglass"
            case .reviewAvailable, .reviewReminder: "star.bubble.fill"
            }
        }
    }

    let id: String
    let kind: Kind
    let groupID: String
    let groupName: String
    var subject = ""
    var relatedID: String?
    var eventDate: Date?
    let createdAt: Date
    var isRead = false

    var title: String {
        switch kind {
        case .applicationPending: L10n.text("入群申請審核中")
        case .applicationApproved: L10n.text("入群申請已通過")
        case .applicationRejected: L10n.text("未通過審核")
        case .admissionReview: L10n.text("待審核入群")
        case .pokeThreshold: L10n.text("隊友在找你")
        case .meeting: L10n.text("會議提醒")
        case .taskDeadline: L10n.text("我的任務即將到期")
        case .projectDeadline: L10n.text("專案倒數提醒")
        case .reviewAvailable: L10n.text("專案已結束，來幫隊友評分吧！")
        case .reviewReminder: L10n.text("別忘了完成隊友互評")
        }
    }

    var message: String {
        switch kind {
        case .applicationPending:
            L10n.format("已送出加入「{0}」的申請，等待組長審核。", groupName)
        case .applicationApproved:
            L10n.format("你加入「{0}」的申請已通過。", groupName)
        case .applicationRejected:
            L10n.format("你加入「{0}」的申請未通過，可重新申請。", groupName)
        case .admissionReview:
            L10n.format("{0} 申請加入「{1}」。", subject, groupName)
        case .pokeThreshold:
            L10n.format("你在「{0}」累積被戳超過 10 下。", groupName)
        case .meeting:
            L10n.format("「{0}」的會議「{1}」將於 {2} 開始。", groupName, subject,
                        eventDate?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)) ?? "")
        case .taskDeadline, .projectDeadline:
            L10n.format("「{0}」即將截止，請留意進度。", subject)
        case .reviewAvailable:
            L10n.format("「{0}」已開放互評。", groupName)
        case .reviewReminder:
            L10n.format("「{0}」的隊友互評，抽空完成吧。", groupName)
        }
    }

    static func application(_ request: GroupJoinRequest, incoming: Bool) -> Self {
        let kind: Kind
        if incoming {
            kind = .admissionReview
        } else {
            kind = switch request.status {
            case .pending: .applicationPending
            case .approved: .applicationApproved
            case .rejected: .applicationRejected
            }
        }
        return Self(id: "admission.\(request.groupID).\(request.requestID).\(kind.rawValue)",
                    kind: kind, groupID: request.groupID, groupName: request.groupName,
                    subject: request.applicantName, relatedID: request.requestID,
                    createdAt: incoming ? request.requestedAt : request.reviewedAt ?? request.requestedAt)
    }
}
