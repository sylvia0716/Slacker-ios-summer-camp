// swift-tools-version: 6.0
import PackageDescription

// Offline tests compile the same production mapping/repository source, without Firebase or UI.
let package = Package(
    name: "GroupCloudDataTests",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [],
    targets: [
        .target(name: "GroupCloudData", path: "group", sources: [
            "Models/AppLanguage.swift", "Models/SmartAgenda.swift", "Models/AgendaChatSummary.swift", "Models/CloudGroupData.swift", "Models/CloudAttachmentCollection.swift", "Models/GroupInviteCode.swift",
            "Models/Member.swift", "Models/Group.swift", "Models/ProjectTask.swift",
            "Models/Subtask.swift", "Models/Deliverable.swift", "Models/TaskAttachment.swift",
            "Shared/Services/GroupRepository.swift", "Shared/Services/CloudReadRetry.swift", "Models/AttachmentOperationError.swift",
            "Shared/Services/AttachmentDocumentReader.swift",
            "Shared/Services/AttachmentDownloadService.swift", "Shared/Services/AttachmentDeletionService.swift",
            "Store/AttachmentActionStore.swift", "Shared/Services/ProfileNicknameRepository.swift",
            "Shared/Services/PokeDeliveryState.swift", "Shared/Services/DeadlineReminderPlan.swift",
            "Shared/Services/ReviewReminderState.swift", "Shared/Services/ReviewNotificationRouter.swift"
        ], resources: [.process("Resources")]),
        .testTarget(name: "GroupCloudDataTests", dependencies: ["GroupCloudData"], path: "ios-cloud-tests")
    ],
    swiftLanguageModes: [.v5]
)
