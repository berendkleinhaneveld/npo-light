//
//  SignInModelTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct SignInModelTests {
    private let recorder = SignedInRecorder()

    private func model(_ authenticator: StubAuthenticator, clock: TestClock = TestClock()) -> SignInModel {
        SignInModel(authenticator: authenticator, clock: clock, onSignedIn: recorder.record)
    }

    @Test("FR-AUTH-06: the code is on screen while the app waits, with no further input")
    func showsTheCodeWhileWaiting() async {
        let reached = Gate()
        let approved = Gate()
        let authenticator = StubAuthenticator(approval: { _ in
            reached.open()
            await approved.wait()
            return StubAuthenticator.plusAccount
        })
        let model = model(authenticator)
        #expect(model.state == .requesting)

        let signIn = Task { await model.signIn() }
        await reached.wait()

        #expect(model.state == .waiting(StubAuthenticator.challenge))
        #expect(recorder.accounts.isEmpty)

        approved.open()
        await signIn.value

        #expect(recorder.accounts == [StubAuthenticator.plusAccount])
    }

    @Test("FR-AUTH-06, FR-AUTH-08: an account without NPO Plus signs in, and is handed on for the check")
    func freeAccountIsHandedOn() async {
        let model = model(StubAuthenticator(approval: { _ in StubAuthenticator.freeAccount }))

        await model.signIn()

        #expect(recorder.accounts == [StubAuthenticator.freeAccount])
        #expect(model.state == .waiting(StubAuthenticator.challenge))
    }

    @Test("FR-AUTH-06: each way a sign-in ends without an account is told apart", arguments: [
        (BackendError.signInExpired, SignInModel.Problem.expired),
        (BackendError.signInDeclined, SignInModel.Problem.declined),
        (BackendError.unreachable, SignInModel.Problem.unreachable),
        (BackendError.unexpectedResponse(status: 500), SignInModel.Problem.unexpected)
    ])
    func problemsAreToldApart(error: BackendError, problem: SignInModel.Problem) async {
        let model = model(StubAuthenticator(approval: { _ in throw error }))

        await model.signIn()

        #expect(model.state == .failed(problem))
        #expect(recorder.accounts.isEmpty)
    }

    @Test("FR-AUTH-06: a code that could not be asked for is a network problem with a retry")
    func failedRequestCanBeRetried() async {
        let attempts = Counter()
        let authenticator = StubAuthenticator(start: {
            if attempts.increment() == 1 { throw BackendError.unreachable }
            return StubAuthenticator.challenge
        })
        let model = model(authenticator)

        await model.signIn()
        #expect(model.state == .failed(.unreachable))

        await model.retry()

        #expect(recorder.accounts == [StubAuthenticator.plusAccount])
    }

    @Test("FR-AUTH-06: an expired code is replaced by a fresh one, which is what is polled for")
    func expiredCodeIsReplaced() async {
        let fresh = DeviceCodeChallenge(userCode: "20261002",
                                        verificationURL: StubAuthenticator.challenge.verificationURL,
                                        completeVerificationURL: URL(filePath: "/fresh"),
                                        pollInterval: .seconds(5),
                                        expiresAt: Date(timeIntervalSince1970: 900),
                                        deviceCode: "device-code-2")
        let starts = Counter()
        let authenticator = StubAuthenticator(
            start: { starts.increment() == 1 ? StubAuthenticator.challenge : fresh },
            approval: { challenge in
                if challenge == StubAuthenticator.challenge { throw BackendError.signInExpired }
                return StubAuthenticator.plusAccount
            }
        )
        let model = model(authenticator)

        await model.signIn()
        #expect(model.state == .failed(.expired))

        await model.retry()

        #expect(model.state == .waiting(fresh))
        #expect(authenticator.awaitedChallenges == [StubAuthenticator.challenge, fresh])
        #expect(recorder.accounts == [StubAuthenticator.plusAccount])
    }

    @Test("FR-AUTH-06: after a network problem the code on screen is kept while it is still good")
    func retryKeepsAGoodCode() async {
        let polls = Counter()
        let authenticator = StubAuthenticator(approval: { _ in
            if polls.increment() == 1 { throw BackendError.unreachable }
            return StubAuthenticator.plusAccount
        })
        let model = model(authenticator, clock: TestClock(now: Date(timeIntervalSince1970: 100)))

        await model.signIn()
        await model.retry()

        #expect(authenticator.startCount == 1)
        #expect(authenticator.awaitedChallenges == [StubAuthenticator.challenge, StubAuthenticator.challenge])
        #expect(recorder.accounts == [StubAuthenticator.plusAccount])
    }

    @Test("FR-AUTH-06: after a network problem a code that lapsed meanwhile is replaced")
    func retryReplacesALapsedCode() async {
        let polls = Counter()
        let clock = TestClock(now: Date(timeIntervalSince1970: 100))
        let authenticator = StubAuthenticator(approval: { _ in
            if polls.increment() == 1 { throw BackendError.unreachable }
            return StubAuthenticator.plusAccount
        })
        let model = model(authenticator, clock: clock)

        await model.signIn()
        clock.advance(by: .seconds(600))
        await model.retry()

        #expect(authenticator.startCount == 2)
        #expect(recorder.accounts == [StubAuthenticator.plusAccount])
    }

    @Test("FR-AUTH-08: a retry after a lost subscription check uses the session that was already stored")
    func retryUsesTheStoredSession() async {
        let authenticator = StubAuthenticator(
            approval: { _ in throw BackendError.unreachable },
            restored: { StubAuthenticator.plusAccount }
        )
        let model = model(authenticator)

        await model.signIn()
        await model.retry()

        #expect(authenticator.startCount == 1)
        #expect(authenticator.awaitedChallenges.count == 1)
        #expect(recorder.accounts == [StubAuthenticator.plusAccount])
    }

    @Test("FR-AUTH-06: a sign-in that is abandoned reports no problem")
    func abandonedSignInReportsNothing() async {
        let model = model(StubAuthenticator(approval: { _ in throw CancellationError() }))

        await model.signIn()

        #expect(model.state == .waiting(StubAuthenticator.challenge))
        #expect(recorder.accounts.isEmpty)
    }
}
