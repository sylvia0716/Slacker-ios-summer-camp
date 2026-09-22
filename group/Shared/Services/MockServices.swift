import Foundation

/// Placeholder boundary for fake upload, AI, and chat behavior used by the MVP.
/// Future work: split each service into its own file only when it gains real behavior.
enum MockServices {
    static var fileUploadMessage: String { L10n.text("成果檔案已暫存") }
    static var aiReportMessage: String { L10n.text("AI 分析報告準備中") }
}
