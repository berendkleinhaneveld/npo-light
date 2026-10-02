//
//  SignInTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The device-code grant, held to the wire (ADR 0007, ADR 0009).
struct SignInTests {
    @Test("FR-AUTH-06: the challenge carries the code and both addresses exactly as NPO gave them")
    func challengeMatchesTheResponse() async throws {
        let body = try Fixture.data("device-authorization-200")
        let clock = TestClock(now: Date(timeIntervalSince1970: 500))
        let transport = StubTransport { _ in HTTPResponse(status: 200, body: body) }
        let authenticator = NPOAuthenticator(transport: transport,
                                             tokenStore: InMemoryTokenStore(),
                                             clock: clock)

        let challenge = try await authenticator.startSignIn()

        #expect(challenge.userCode == "51411921")
        #expect(challenge.verificationURL.absoluteString == "https://id.npo.nl/koppel")
        #expect(challenge.completeVerificationURL.absoluteString
            == "https://id.npo.nl/koppel?userCode=51411921")
        #expect(challenge.pollInterval == .seconds(5))
        #expect(challenge.expiresAt == Date(timeIntervalSince1970: 800))
    }

    @Test("FR-AUTH-06: the code is asked for as NPO's television client")
    func asksAsTheTelevisionClient() async throws {
        let harness = SignInHarness()

        _ = try await harness.authenticator.startSignIn()

        let request = try #require(harness.transport.sent.first)
        #expect(request.url?.absoluteString == "https://id.npo.nl/connect/deviceauthorization")
        #expect(request.httpMethod == "POST")
        #expect(request.formFields["client_id"] == "npostart-app-tvos-prod")
        #expect(request.formFields["scope"] == "openid offline_access npo-id.org-npo")
    }

    @Test("FR-AUTH-06: approval is noticed by polling at the interval NPO advertised")
    func pollsUntilApproved() async throws {
        let polls = Counter()
        let harness = SignInHarness()
        let challenge = try await harness.authenticator.startSignIn()
        let approving = StubTransport { request in
            if request.url?.path == "/connect/token", polls.increment() == 3 {
                harness.identityProvider.approve()
            }
            return try await harness.transport.send(request)
        }
        let authenticator = NPOAuthenticator(transport: approving,
                                             tokenStore: harness.store,
                                             clock: harness.clock)

        let account = try await authenticator.awaitApproval(of: challenge)

        #expect(account == Account(identifier: "account-1", hasPlus: true))
        #expect(harness.identityProvider.pollCount == 3)
        #expect(harness.clock.waits == [.seconds(5), .seconds(5), .seconds(5)])
    }

    @Test("FR-AUTH-06, FR-AUTH-02: an approved sign-in leaves the tokens in the token store")
    func approvalStoresTheSession() async throws {
        let harness = SignInHarness()

        try await harness.signIn()

        let session = try #require(harness.store.storedSession)
        #expect(session.idToken == "id-token-1")
        #expect(session.refreshToken == harness.identityProvider.currentRefreshToken)
        #expect(session.accessTokenExpiresAt == harness.clock.now.addingTimeInterval(3600))
        #expect(!session.deviceIdentifier.isEmpty)
    }

    @Test("FR-AUTH-06: a code nobody approves in time is reported as expired")
    func unapprovedCodeExpires() async throws {
        let harness = SignInHarness()
        let challenge = try await harness.authenticator.startSignIn()

        await #expect(throws: BackendError.signInExpired) {
            _ = try await harness.authenticator.awaitApproval(of: challenge)
        }
        #expect(harness.identityProvider.pollCount == 60)
        #expect(harness.store.storedSession == nil)
    }

    @Test("FR-AUTH-06: a pairing rejected on the other device is reported as declined")
    func rejectedPairingIsDeclined() async throws {
        let harness = SignInHarness()
        let challenge = try await harness.authenticator.startSignIn()
        harness.identityProvider.decline()

        await #expect(throws: BackendError.signInDeclined) {
            _ = try await harness.authenticator.awaitApproval(of: challenge)
        }
    }

    @Test("FR-AUTH-06: a sign-in that fails on the network is not reported as expired or declined")
    func lostNetworkIsUnreachable() async throws {
        let transport = StubTransport { _ in throw URLError(.notConnectedToInternet) }
        let authenticator = NPOAuthenticator(transport: transport,
                                             tokenStore: InMemoryTokenStore(),
                                             clock: TestClock())

        await #expect(throws: BackendError.unreachable) {
            _ = try await authenticator.startSignIn()
        }
    }

    @Test("FR-AUTH-06: being told to slow down lengthens the wait between polls")
    func slowsDownWhenAsked() async throws {
        let polls = Counter()
        let harness = SignInHarness()
        let challenge = try await harness.authenticator.startSignIn()
        harness.identityProvider.approve()
        let hurried = StubTransport { request in
            if request.url?.path == "/connect/token", polls.increment() == 1 {
                return .json(#"{"error":"slow_down"}"#, status: 400)
            }
            return try await harness.transport.send(request)
        }
        let authenticator = NPOAuthenticator(transport: hurried,
                                             tokenStore: harness.store,
                                             clock: harness.clock)

        _ = try await authenticator.awaitApproval(of: challenge)

        #expect(harness.clock.waits == [.seconds(5), .seconds(10)])
    }

    @Test("FR-AUTH-06, FR-AUTH-08: the captured responses carry a sign-in through to the account")
    func capturedShapesSignIn() async throws {
        let pending = try Fixture.data("token-authorization-pending-400")
        let success = try Fixture.data("token-success-200")
        let account = try Fixture.data("account-premium-200")
        let authorization = try Fixture.data("device-authorization-200")
        let polls = Counter()
        let transport = StubTransport { request in
            switch request.url?.path {
            case "/connect/deviceauthorization":
                return HTTPResponse(status: 200, body: authorization)
            case "/connect/token":
                return polls.increment() == 1
                    ? HTTPResponse(status: 400, body: pending)
                    : HTTPResponse(status: 200, body: success)
            default:
                return HTTPResponse(status: 200, body: account)
            }
        }
        let store = InMemoryTokenStore()
        let authenticator = NPOAuthenticator(transport: transport, tokenStore: store, clock: TestClock())

        let challenge = try await authenticator.startSignIn()
        let signedIn = try await authenticator.awaitApproval(of: challenge)

        #expect(signedIn == Account(identifier: "00000000-0000-0000-0000-000000000001", hasPlus: true))
        #expect(store.storedSession?.idToken == "sanitised.id.token")
        #expect(store.storedSession?.refreshToken == "sanitised-refresh-token")
    }
}
