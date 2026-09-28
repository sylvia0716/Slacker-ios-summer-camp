import Foundation
import CoreFoundation

/// Only Firebase-issued boolean claims enable local developer tools; never a profile role/email.
struct DeveloperAccessState {
    static let claimKey = "groupBombDeveloper"
    private(set) var uid: String?
    private(set) var isAllowed = false
    private var requestID = UUID()
    private var eligible = false

    mutating func begin(uid: String?, email: String?, isAnonymous: Bool) -> UUID {
        let eligible = uid?.isEmpty == false && email?.isEmpty == false && !isAnonymous
        if uid != self.uid || !eligible { isAllowed = false }
        self.uid = uid
        self.eligible = eligible
        requestID = UUID()
        return requestID
    }

    mutating func finish(request: UUID, claims: [String: Any]?) {
        guard request == requestID else { return }
        guard eligible, let value = claims?[Self.claimKey] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            isAllowed = false
            return
        }
        isAllowed = value.boolValue
    }
}
