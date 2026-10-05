//
//  SessionRenewalTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Staying signed in: restoring, renewing and rotating (ADR 0007).
struct SessionRenewalTests {
    private static func bearer(of request: URLRequest?) -> String? {
        request?.value(forHTTPHeaderField: "Authorization")
    }

    @Test("FR-AUTH-01: with nothing stored there is no account, and nothing is asked of NPO")
    func nothingStoredMeansNoAccount() async throws {
        let harness = SignInHarness()

        let account = try await harness.authenticator.restoredAccount()

        #expect(account == nil)
        #expect(harness.transport.sent.isEmpty)
    }

    @Test("FR-AUTH-01: a stored session that is still valid answers with its account")
    func validSessionIsRestored() async throws {
        let harness = SignInHarness()
        try await harness.signIn()

        let account = try await harness.authenticator.restoredAccount()

        #expect(account == Account(identifier: "account-1", hasPlus: true))
        #expect(harness.identityProvider.refreshCount == 0)
    }

    @Test("FR-AUTH-07: a lapsed token is renewed before a request has to fail first")
    func lapsedTokenIsRenewedFirst() async throws {
        let harness = SignInHarness()
        try await harness.signIn()
        harness.clock.advance(by: .seconds(2 * 3600))

        let account = try await harness.authenticator.restoredAccount()

        #expect(account?.hasPlus == true)
        #expect(harness.identityProvider.refreshCount == 1)
        #expect(Self.bearer(of: harness.backendRequests.last) == "Bearer id-token-2")
    }

    @Test("FR-AUTH-07: each renewal replaces the stored token before it is used again")
    func renewalReplacesTheStoredToken() async throws {
        let harness = SignInHarness()
        try await harness.signIn()
        let device = harness.store.storedSession?.deviceIdentifier

        harness.clock.advance(by: .seconds(2 * 3600))
        _ = try await harness.authenticator.restoredAccount()
        #expect(harness.store.storedSession?.refreshToken == harness.identityProvider.currentRefreshToken)

        harness.clock.advance(by: .seconds(2 * 3600))
        let account = try await harness.authenticator.restoredAccount()

        #expect(account?.hasPlus == true)
        #expect(harness.identityProvider.refreshCount == 2)
        #expect(harness.store.storedSession?.refreshToken == harness.identityProvider.currentRefreshToken)
        #expect(harness.store.storedSession?.deviceIdentifier == device)
    }

    @Test("FR-AUTH-03: a request refused for a lapsed session is retried once after a renewal")
    func refusedRequestIsRetriedOnce() async throws {
        let harness = SignInHarness(backend: { request in
            Self.bearer(of: request) == "Bearer id-token-1"
                ? .json(#"{"message":"Unauthorized"}"#, status: 401)
                : .json(SignInHarness.premiumAccount)
        })
        let challenge = try await harness.authenticator.startSignIn()
        harness.identityProvider.approve()

        let account = try await harness.authenticator.awaitApproval(of: challenge)

        #expect(account.hasPlus)
        #expect(harness.identityProvider.refreshCount == 1)
        #expect(harness.backendRequests.map(Self.bearer(of:)) == ["Bearer id-token-1", "Bearer id-token-2"])
    }

    @Test("FR-AUTH-03: a request refused again after a renewal is not retried in a loop")
    func secondRefusalIsNotRetried() async throws {
        let harness = SignInHarness(backend: { _ in .json(#"{"message":"Unauthorized"}"#, status: 401) })

        await #expect(throws: BackendError.unexpectedResponse(status: 401)) {
            try await harness.signIn()
        }
        #expect(harness.identityProvider.refreshCount == 1)
        #expect(harness.backendRequests.count == 2)
    }

    @Test("FR-AUTH-03, FR-AUTH-07: concurrent requests meeting a lapsed token cause exactly one renewal")
    func concurrentCallersRenewOnce() async throws {
        // Yielding before the identity provider answers lets every caller reach
        // the renewal while the first one is still in flight.
        let harness = SignInHarness(beforeIdentityResponse: { _ in
            for _ in 0..<20 { await Task.yield() }
        })
        try await harness.signIn()
        harness.clock.advance(by: .seconds(2 * 3600))
        let authenticator = harness.authenticator

        let accounts = try await withThrowingTaskGroup(of: Account?.self) { group in
            for _ in 0..<8 {
                group.addTask { try await authenticator.restoredAccount() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(accounts.count == 8)
        #expect(accounts.allSatisfy { $0?.hasPlus == true })
        #expect(harness.identityProvider.refreshCount == 1)
    }

    @Test("FR-AUTH-03, FR-AUTH-07: a renewal NPO rejects ends the session and forgets the token")
    func rejectedRenewalEndsTheSession() async throws {
        let harness = SignInHarness()
        try await harness.signIn()
        let stored = try #require(harness.store.storedSession)
        // The token was spent elsewhere: what is stored no longer matches NPO.
        _ = try await harness.identityProvider.refresh(refreshToken: stored.refreshToken)
        harness.clock.advance(by: .seconds(2 * 3600))

        await #expect(throws: BackendError.notSignedIn) {
            _ = try await harness.authenticator.restoredAccount()
        }
        #expect(harness.store.storedSession == nil)
        #expect(try await harness.authenticator.restoredAccount() == nil)
        // And the app hears it, whichever page was asking.
        var endings = harness.authenticator.endedSessions.makeAsyncIterator()
        #expect(await endings.next() != nil)
    }

    @Test("FR-AUTH-07: a renewal that never reached NPO keeps the token, and works the next time")
    func interruptedRenewalRecovers() async throws {
        let reconnected = Counter()
        let harness = SignInHarness()
        try await harness.signIn()
        harness.clock.advance(by: .seconds(2 * 3600))
        let flaky = StubTransport { request in
            if reconnected.value == 0 { throw URLError(.networkConnectionLost) }
            return try await harness.transport.send(request)
        }
        let authenticator = NPOAuthenticator(transport: flaky,
                                             tokenStore: harness.store,
                                             clock: harness.clock)

        await #expect(throws: BackendError.unreachable) {
            _ = try await authenticator.restoredAccount()
        }
        #expect(harness.store.storedSession?.idToken == "id-token-1")

        reconnected.increment()
        let account = try await authenticator.restoredAccount()

        #expect(account?.hasPlus == true)
        #expect(harness.store.storedSession?.idToken == "id-token-2")
    }

    @Test("FR-AUTH-04: signing out forgets the session on this television")
    func signOutForgetsTheSession() async throws {
        let harness = SignInHarness()
        try await harness.signIn()

        try harness.authenticator.signOut()

        #expect(harness.store.storedSession == nil)
        #expect(try await harness.authenticator.restoredAccount() == nil)
    }
}
