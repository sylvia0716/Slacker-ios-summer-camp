import Testing
@testable import GroupCloudData

struct DeveloperAccessTests {
    @Test func claimMustBeAnExplicitBoolean() {
        let invalidClaims: [Any] = [false, "true", 1, "developer"]
        for claim in invalidClaims {
            var state = DeveloperAccessState()
            let request = state.begin(uid: "a", email: "a@example.com", isAnonymous: false)
            state.finish(request: request, claims: [DeveloperAccessState.claimKey: claim])
            #expect(!state.isAllowed)
        }
        var state = DeveloperAccessState()
        let request = state.begin(uid: "a", email: "a@example.com", isAnonymous: false)
        state.finish(request: request, claims: [DeveloperAccessState.claimKey: true])
        #expect(state.isAllowed)
    }

    @Test func anonymousAndSignedOutCannotUseTools() {
        let cases: [(String?, String?, Bool)] = [(nil, nil, false), ("a", nil, true), ("a", "a@example.com", true)]
        for (uid, email, anonymous) in cases {
            var state = DeveloperAccessState()
            let request = state.begin(uid: uid, email: email, isAnonymous: anonymous)
            state.finish(request: request, claims: [DeveloperAccessState.claimKey: true])
            #expect(!state.isAllowed)
        }
    }

    @Test func accountChangeRejectsStaleResponse() {
        var state = DeveloperAccessState()
        let a = state.begin(uid: "a", email: "a@example.com", isAnonymous: false)
        state.finish(request: a, claims: [DeveloperAccessState.claimKey: true])
        #expect(state.isAllowed)
        let b = state.begin(uid: "b", email: "b@example.com", isAnonymous: false)
        #expect(!state.isAllowed)
        state.finish(request: a, claims: [DeveloperAccessState.claimKey: true])
        #expect(!state.isAllowed)
        state.finish(request: b, claims: [:])
        #expect(!state.isAllowed)
    }

    @Test func revocationOrFailureRemovesAccess() {
        var state = DeveloperAccessState()
        let request = state.begin(uid: "a", email: "a@example.com", isAnonymous: false)
        state.finish(request: request, claims: [DeveloperAccessState.claimKey: true])
        let refresh = state.begin(uid: "a", email: "a@example.com", isAnonymous: false)
        state.finish(request: refresh, claims: nil)
        #expect(!state.isAllowed)
        state.finish(request: request, claims: [DeveloperAccessState.claimKey: true])
        #expect(!state.isAllowed)
        _ = state.begin(uid: nil, email: nil, isAnonymous: false)
        #expect(!state.isAllowed)
    }
}
