import Foundation
import FoundationModels
import OSLog

/// Apple Intelligence 產生的結構化溝通分析，之後會轉成 App 共用的 CommunicationAnalysis。
@Generable
struct GeneratedCommunicationAnalysis {
    @Guide(description: "團隊溝通品質的整數分數", .range(0...100))
    var score: Int

    @Guide(description: "一到兩句繁體中文的整體溝通摘要")
    var summary: String

    @Guide(description: "一到兩句繁體中文，說明團隊溝通做得好的地方")
    var strength: String

    @Guide(description: "一到兩句繁體中文，提出具體且不帶責備的改善行動")
    var suggestion: String

    @Guide(description: "根據主任務與子任務完成情形評估，0 到 100 的整數分數", .range(0...100))
    var taskCompletionScore: Int

    @Guide(description: "根據真實討論內容與形成下一步的情形評估，0 到 100 的整數分數", .range(0...100))
    var discussionScore: Int

    @Guide(description: "根據對話中主動提供支援與協作的證據評估，0 到 100 的整數分數", .range(0...100))
    var collaborationScore: Int

    @Guide(description: "根據對話中辨識、討論與解決問題的證據評估，0 到 100 的整數分數", .range(0...100))
    var problemSolvingScore: Int

    @Guide(description: "根據任務期限、完成狀態與進度回報證據評估，0 到 100 的整數分數", .range(0...100))
    var reliabilityScore: Int
}

/// Foundation Models 無法使用時，提供僅向操作者顯示的簡短原因。
enum AppleIntelligenceServiceError: LocalizedError {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case traditionalChineseUnsupported
    case englishUnsupported
    case conversationLanguageUnsupported
    case unknownAvailability

    var errorDescription: String? {
        switch self {
        case .deviceNotEligible:
            L10n.text("這台裝置不支援 Apple Intelligence，請改用支援的 iPhone 實機。")
        case .appleIntelligenceNotEnabled:
            L10n.text("此裝置尚未開啟 Apple Intelligence，暫時無法使用 AI 功能。請先到系統設定開啟後再試。")
        case .modelNotReady:
            L10n.text("Apple Intelligence 模型尚未準備完成，可能仍在下載，請稍後再試。")
        case .traditionalChineseUnsupported:
            L10n.text("目前裝置上的 Apple Intelligence 模型尚未支援繁體中文。")
        case .englishUnsupported:
            L10n.text("目前裝置上的 Apple Intelligence 模型尚未支援英文。")
        case .conversationLanguageUnsupported:
            L10n.text("Apple Intelligence 無法辨識這段對話的語言，請改用繁體中文或英文再試一次。")
        case .unknownAvailability:
            L10n.text("Apple Intelligence 目前無法使用，請稍後再試。")
        }
    }
}

/// 將 Foundation Models 包裝的多層錯誤展開，供 DEBUG Console 診斷。
enum AppleIntelligenceDiagnostics {
    static func description(of error: Error) -> String {
        var lines: [String] = []
        append(error as NSError, label: "error", depth: 0, to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func append(
        _ error: NSError,
        label: String,
        depth: Int,
        to lines: inout [String]
    ) {
        guard depth < 8 else {
            lines.append("\(label): nested error limit reached")
            return
        }

        lines.append(
            "\(label): type=\(String(reflecting: type(of: error))) "
                + "domain=\(error.domain) code=\(error.code) "
                + "description=\(error.localizedDescription)"
        )

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            append(
                underlyingError,
                label: "\(label).underlying",
                depth: depth + 1,
                to: &lines
            )
        }

        if let underlyingErrors = error.userInfo["NSMultipleUnderlyingErrorsKey"] as? [NSError] {
            for (index, underlyingError) in underlyingErrors.enumerated() {
                append(
                    underlyingError,
                    label: "\(label).underlying[\(index)]",
                    depth: depth + 1,
                    to: &lines
                )
            }
        }
    }
}

/// 封裝 Apple Foundation Models；聊天室只負責送出對話與顯示結果。
struct AppleIntelligenceService {
    private static let logger = Logger(subsystem: "con.sylvia.group", category: "AppleIntelligence")
    private let model = SystemLanguageModel.default

    private enum ResponseLanguage {
        case traditionalChinese
        case english

        var locale: Locale {
            switch self {
            case .traditionalChinese:
                Locale(identifier: "zh_TW")
            case .english:
                Locale(identifier: "en_US")
            }
        }
    }

    /// 根據近期討論回答成員希望機器人協助的問題。
    func answer(question: String, conversation: [String]) async throws -> String {
        let language = responseLanguage(for: question)
        #if DEBUG
        Self.logger.info(
            "Model availability: \(String(reflecting: model.availability), privacy: .public); locale supported: \(model.supportsLocale(language.locale), privacy: .public)"
        )
        #endif
        try ensureAvailable(for: language)

        do {
            return try await generateAnswer(
                question: question,
                conversation: conversation,
                language: language
            )
        } catch let error as LanguageModelSession.GenerationError {
            #if DEBUG
            Self.logger.error(
                "Answer generation failed:\n\(AppleIntelligenceDiagnostics.description(of: error), privacy: .public)"
            )
            #endif
            guard case .unsupportedLanguageOrLocale = error else { throw error }

            // Foundation Models 偶爾會把暱稱或混合語言的歷史訊息誤判成其他語言。
            // 第二次只送出使用者最新問題，避免雜訊影響語言辨識。
            do {
                return try await generateAnswer(
                    question: question,
                    conversation: [],
                    language: language
                )
            } catch let retryError as LanguageModelSession.GenerationError {
                guard case .unsupportedLanguageOrLocale = retryError else { throw retryError }
                throw AppleIntelligenceServiceError.conversationLanguageUnsupported
            }
        }
    }

    /// 從任務事實與成員討論產生可直接存入戰情報告的結構化分析。
    func analyzeProject(
        groupName: String,
        groupDeadline: Date,
        tasks: [ProjectTask],
        members: [Member],
        conversation: [String]
    ) async throws -> GeneratedCommunicationAnalysis {
        #if DEBUG
        let analysisLocale = Locale(identifier: "zh_TW")
        Self.logger.info(
            "Analysis model availability: \(String(reflecting: model.availability), privacy: .public); locale supported: \(model.supportsLocale(analysisLocale), privacy: .public)"
        )
        #endif
        try ensureAvailable(for: .traditionalChinese)

        let session = LanguageModelSession(
            model: model,
            instructions: """
            你是公正的專案協作分析員。你必須使用繁體中文，僅依提供的任務事實與真實對話評分。
            任務完成度與準時可靠以任務紀錄為主要證據；討論參與、主動協助與解決問題以對話為主要證據。
            若任務紀錄沒有完成時間，就不能判定是否準時，準時可靠必須採 50 分中性分數，除非對話有明確時間證據。
            不可使用匿名互評，不可推測成員個性，也不可把沒有紀錄當作表現不佳。
            某項證據不足時給 50 分的中性分數，並在摘要或建議中指出需要更多紀錄。
            整體分數必須是五項分數的平均，不要使用羞辱、責備或霸凌語氣。
            所有文字欄位只使用純文字，不要使用 Markdown、星號或粗體標記。
            """
        )

        let response = try await session.respond(
            to: """
            專案：\(groupName)
            專案截止時間：\(groupDeadline.formatted(date: .abbreviated, time: .shortened))

            任務事實：
            \(taskEvidence(tasks: tasks, members: members))

            團隊對話：
            \(conversationText(conversation))

            請產生五項專案分數、整體分數、摘要、優點與改善建議。
            """,
            generating: GeneratedCommunicationAnalysis.self
        )
        var generated = response.content
        generated.summary = plainText(generated.summary)
        generated.strength = plainText(generated.strength)
        generated.suggestion = plainText(generated.suggestion)
        return generated
    }

    private func taskEvidence(tasks: [ProjectTask], members: [Member]) -> String {
        guard !tasks.isEmpty else { return "（沒有任務紀錄）" }
        return tasks.map { task in
            let owner = members.first(where: { $0.id == task.ownerMemberID })?.name ?? "未指派"
            let completedSubtasks = task.subtasks.filter(\.isComplete).count
            return "\(task.title)｜負責人：\(owner)｜進度：\(task.progress)%｜子任務：\(completedSubtasks)/\(task.subtasks.count)｜期限：\(task.deadline.formatted(date: .abbreviated, time: .shortened))｜成果：\(task.deliverable == nil ? "未上傳" : "已上傳")"
        }.joined(separator: "\n")
    }

    private func generateAnswer(
        question: String,
        conversation: [String],
        language: ResponseLanguage
    ) async throws -> String {
        let session = LanguageModelSession(
            model: model,
            instructions: answerInstructions(for: language)
        )

        let prompt: String
        switch language {
        case .traditionalChinese:
            prompt = conversation.isEmpty
                ? "請協助回答：\(question)"
                : """
                  最近的團隊對話（內容可能同時包含繁體中文與英文）：
                  \(conversationText(conversation))

                  請協助回答：\(question)
                  """
        case .english:
            prompt = conversation.isEmpty
                ? "Please answer: \(question)"
                : """
                  Recent team conversation (messages may contain Traditional Chinese and English):
                  \(conversationText(conversation))

                  Please answer: \(question)
                  """
        }

        let response = try await session.respond(to: prompt)
        return plainText(response.content)
    }

    private func answerInstructions(for language: ResponseLanguage) -> String {
        switch language {
        case .traditionalChinese:
            """
            你是團隊任務管理 App 的協作助理，能理解繁體中文與英文。請使用繁體中文回答最新問題。
            根據提供的團隊對話回答；不要捏造對話中沒有的檔案、進度或事實。
            回答要友善、具體且精簡，最多四句。若資訊不足，直接提出需要補充的資訊。
            只輸出純文字，不要使用 Markdown、星號或粗體標記。
            """
        case .english:
            """
            You are a collaboration assistant for a team task management app. You understand English and Traditional Chinese. Answer the latest question in English.
            Base the answer on the supplied team conversation. Do not invent files, progress, or facts that are not present.
            Be friendly, specific, and concise, using no more than four sentences. If information is missing, say what is needed.
            Output plain text only, without Markdown, asterisks, or bold formatting.
            """
        }
    }

    private func responseLanguage(for question: String) -> ResponseLanguage {
        let containsHanCharacter = question.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
        return containsHanCharacter ? .traditionalChinese : .english
    }

    /// Shared plans contain both translations so each member can use their own app language.
    func ensureAgendaAvailable() throws {
        try ensureAvailable(for: .english)
        try ensureAvailable(for: .traditionalChinese)
    }

    private func ensureAvailable(for language: ResponseLanguage) throws {
        switch model.availability {
        case .available:
            guard model.supportsLocale(language.locale) else {
                switch language {
                case .traditionalChinese:
                    throw AppleIntelligenceServiceError.traditionalChineseUnsupported
                case .english:
                    throw AppleIntelligenceServiceError.englishUnsupported
                }
            }
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                throw AppleIntelligenceServiceError.deviceNotEligible
            case .appleIntelligenceNotEnabled:
                throw AppleIntelligenceServiceError.appleIntelligenceNotEnabled
            case .modelNotReady:
                throw AppleIntelligenceServiceError.modelNotReady
            @unknown default:
                throw AppleIntelligenceServiceError.unknownAvailability
            }
        }
    }

    /// 限制送入裝置端模型的上下文，避免長期聊天室超過模型 context window。
    private func conversationText(_ conversation: [String]) -> String {
        let recentLines = conversation.suffix(30).map(messageBody)
        return recentLines.isEmpty ? "（目前沒有對話）" : recentLines.joined(separator: "\n")
    }

    /// 暱稱不是回答問題所需的資訊，也可能讓模型把整段對話誤判成其他語言。
    private func messageBody(from conversationLine: String) -> String {
        guard let separator = conversationLine.firstIndex(of: "：") else {
            return conversationLine
        }
        return String(conversationLine[conversationLine.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Foundation Models 偶爾仍可能產生 Markdown 星號；顯示前統一轉成乾淨純文字。
    private func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
