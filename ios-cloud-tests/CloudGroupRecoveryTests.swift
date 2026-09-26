import Foundation
import Testing
@testable import GroupCloudData

@Suite @MainActor
struct CloudGroupRecoveryTests {
    private let summary = CloudGroupSummary(id: UUID(), name: "Recovery test", deadline: .distantFuture, inviteCode: "TEST")
    private var member: CloudDocument<CloudMemberDocument> {
        CloudDocument(id: "A", value: CloudMemberDocument(userID: "A", role: .member, joinedAt: .distantPast))
    }
    private var offline: NSError { NSError(domain: "FIRFirestoreErrorDomain", code: 14) }

    @Test func retriesOnlyTransientErrors() {
        for code in [NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                     NSURLErrorDNSLookupFailed, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost] {
            #expect(CloudReadRetry.isTransient(NSError(domain: NSURLErrorDomain, code: code)))
        }
        for domain in ["FIRFirestoreErrorDomain", "com.firebase.functions"] {
            for code in [4, 10, 14] { #expect(CloudReadRetry.isTransient(NSError(domain: domain, code: code))) }
            for code in [3, 7, 9, 16] { #expect(!CloudReadRetry.isTransient(NSError(domain: domain, code: code))) }
        }
        #expect(!CloudReadRetry.isTransient(CancellationError()))
        #expect(!CloudReadRetry.isTransient(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(!CloudReadRetry.isTransient(GroupLoadError.invalidData))
        #expect(!CloudReadRetry.isTransient(GroupLoadError.accountChanged))
        #expect(!CloudReadRetry.isTransient(NSError(domain: "unrelated", code: 14)))
        #expect(CloudReadRetry.isTransient(NSError(domain: "wrapper", code: 0, userInfo: [NSUnderlyingErrorKey: offline])))
        // Do not hide a real permission rejection even if a network error is nested inside it.
        #expect(!CloudReadRetry.isTransient(NSError(domain: "com.firebase.functions", code: 7,
                                                   userInfo: [NSUnderlyingErrorKey: offline])))
    }

    @Test func coldStartRecoversFromDNSAndTokenTransportFailures() async throws {
        var reads = 0, waits: [Duration] = []
        let repository = GroupRepository(reads: .init(currentUID: { "A" }, summaries: {
            reads += 1
            if reads == 1 { throw NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed) }
            if reads == 2 { throw NSError(domain: "FIRAuthErrorDomain", code: 17020) }
            return [summary]
        }, members: { _ in [member] }, tasks: { _ in [] }), wait: { waits.append($0) })
        let loaded = try await repository.load()
        #expect(loaded.map(\.group.id) == [summary.id])
        #expect(reads == 3)
        #expect(waits == [.seconds(1), .seconds(2)])
    }

    @Test func aFailedHydrationIsReloadedAsOneFreshSnapshot() async throws {
        var taskReads = 0, summaryReads = 0
        let id = UUID().uuidString
        let repository = GroupRepository(reads: .init(currentUID: { "A" }, summaries: {
            summaryReads += 1
            return [summary]
        }, members: { _ in [member] }, tasks: { _ in
            taskReads += 1
            if taskReads == 1 { throw offline }
            return [CloudDocument(id: id, value: CloudTaskDocument(title: "Recovered task", ownerMemberID: "A"))]
        }), wait: { _ in })
        let loaded = try await repository.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].tasks.map(\.title) == ["Recovered task"])
        #expect(summaryReads == 2)
        #expect(taskReads == 2)
    }

    @Test func persistentNetworkFailureIsBoundedAndNeverBecomesAnEmptySuccess() async {
        var reads = 0, waits: [Duration] = []
        let repository = GroupRepository(reads: .init(currentUID: { "A" }, summaries: {
            reads += 1
            throw offline
        }, members: { _ in [] }, tasks: { _ in [] }), wait: { waits.append($0) })
        await #expect(throws: NSError.self) { try await repository.load() }
        #expect(reads == 5)
        #expect(waits == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])
    }

    @Test func permissionFailureIsSurfacedImmediately() async {
        var reads = 0
        let repository = GroupRepository(reads: .init(currentUID: { "A" }, summaries: {
            reads += 1
            throw NSError(domain: "com.firebase.functions", code: 7)
        }, members: { _ in [] }, tasks: { _ in [] }), wait: { _ in Issue.record("Permission errors must not retry") })
        await #expect(throws: NSError.self) { try await repository.load() }
        #expect(reads == 1)
    }

    @Test func changingAccountDuringRecoveryStopsOldReads() async {
        var uid = "A", reads = 0
        let repository = GroupRepository(reads: .init(currentUID: { uid }, summaries: {
            reads += 1
            throw offline
        }, members: { _ in [] }, tasks: { _ in [] }), wait: { _ in uid = "B" })
        await #expect(throws: GroupLoadError.self) { try await repository.load() }
        #expect(reads == 1)
    }

    @Test func suspensionCancelsRetryBeforeAnotherCloudRead() async {
        var reads = 0
        let operation = Task {
            let repository = GroupRepository(reads: .init(currentUID: { "A" }, summaries: {
                reads += 1
                throw offline
            }, members: { _ in [] }, tasks: { _ in [] }), wait: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
            await #expect(throws: CancellationError.self) { try await repository.load() }
        }
        await operation.value
        #expect(reads == 1)
    }
}
