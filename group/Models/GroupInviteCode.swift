import Foundation

enum GroupInviteCode {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func generate() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var random = SystemRandomNumberGenerator()
        return String((0..<6).map { _ in alphabet[Int.random(in: alphabet.indices, using: &random)] })
    }

    static func isValid(_ code: String) -> Bool {
        code.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil
    }
}
