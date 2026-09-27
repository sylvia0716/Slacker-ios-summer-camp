import Foundation

/// Retry temporary read failures only. Authentication, permission and data errors need attention.
enum CloudReadRetry {
    static let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]

    static func isTransient(_ error: Error) -> Bool {
        if let error = error as? GroupLoadError {
            if case .network = error { return true }
            return false
        }
        var current = error as NSError
        for _ in 0..<5 {
            switch current.domain {
            case NSURLErrorDomain:
                return [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                        NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
                        NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed].contains(current.code)
            case "FIRFirestoreErrorDomain", "com.firebase.functions":
                // Firebase's canonical gRPC codes: deadline exceeded, aborted, unavailable.
                if [4, 10, 14].contains(current.code) { return true }
                if [3, 7, 9, 16].contains(current.code) { return false }
            case "FIRAuthErrorDomain":
                return current.code == 17020 // Auth token refresh failed due to the network.
            default: break
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }
}
