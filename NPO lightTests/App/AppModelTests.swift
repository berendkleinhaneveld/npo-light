//
//  AppModelTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct AppModelTests {
    @Test("FR-AUTH-01: launching without a stored session shows sign-in")
    func noSessionShowsSignIn() async {
        let model = AppModel(authenticator: StubAuthenticator(), clock: HookClock())
        #expect(model.session == .restoring)

        await model.restore()

        #expect(model.session == .signedOut)
    }

    @Test("FR-AUTH-01: launching with a valid stored session is signed in without asking")
    func storedSessionIsSignedIn() async {
        let model = AppModel(authenticator: StubAuthenticator(restored: { StubAuthenticator.plusAccount }),
                             clock: HookClock())

        await model.restore()

        #expect(model.session == .signedIn(StubAuthenticator.plusAccount))
    }

    @Test("FR-AUTH-03, FR-AUTH-07: a session NPO no longer recognises returns to sign-in")
    func deadSessionShowsSignIn() async {
        let model = AppModel(authenticator: StubAuthenticator(restored: { throw BackendError.notSignedIn }),
                             clock: HookClock())

        await model.restore()

        #expect(model.session == .signedOut)
    }

    @Test("FR-AUTH-08: an unreachable backend is a network problem, and signs nobody out")
    func unreachableSignsNobodyOut() async {
        let authenticator = StubAuthenticator(restored: { throw BackendError.unreachable })
        let model = AppModel(authenticator: authenticator, clock: HookClock())

        await model.restore()

        #expect(model.session == .unreachable)
        #expect(authenticator.signOutCount == 0)
    }

    @Test("FR-AUTH-08: retrying after a network problem checks the account again")
    func retryChecksAgain() async {
        let attempts = Counter()
        let authenticator = StubAuthenticator(restored: {
            if attempts.increment() == 1 { throw BackendError.unreachable }
            return StubAuthenticator.plusAccount
        })
        let model = AppModel(authenticator: authenticator, clock: HookClock())

        await model.restore()
        await model.restore()

        #expect(model.session == .signedIn(StubAuthenticator.plusAccount))
    }

    @Test("FR-AUTH-08: an account with NPO Plus proceeds with nothing to dismiss")
    func plusAccountProceeds() {
        let model = AppModel(authenticator: StubAuthenticator(), clock: HookClock())

        model.admit(StubAuthenticator.plusAccount)

        #expect(model.session == .signedIn(StubAuthenticator.plusAccount))
    }

    @Test("FR-AUTH-08: an account without NPO Plus is told why, and is not signed out until acknowledged")
    func freeAccountWaitsForAcknowledgement() {
        let authenticator = StubAuthenticator()
        let model = AppModel(authenticator: authenticator, clock: HookClock())

        model.admit(StubAuthenticator.freeAccount)

        #expect(model.session == .plusRequired)
        #expect(authenticator.signOutCount == 0)

        model.acknowledgePlusRequired()

        #expect(model.session == .signedOut)
        #expect(authenticator.signOutCount == 1)
    }

    @Test("FR-AUTH-08: a subscription that lapsed while signed in is caught at the next check")
    func lapsedSubscriptionIsCaught() async {
        let model = AppModel(authenticator: StubAuthenticator(restored: { StubAuthenticator.freeAccount }),
                             clock: HookClock())

        await model.restore()

        #expect(model.session == .plusRequired)
    }

    @Test("FR-AUTH-04: signing out returns to sign-in")
    func signOutShowsSignIn() {
        let authenticator = StubAuthenticator()
        let model = AppModel(authenticator: authenticator, clock: HookClock())
        model.admit(StubAuthenticator.plusAccount)

        model.signOut()

        #expect(model.session == .signedOut)
        #expect(authenticator.signOutCount == 1)
    }

    @Test("FR-AUTH-03: a session NPO ends while the app is running returns to sign-in")
    func endedSessionShowsSignIn() async {
        let attempts = Counter()
        let authenticator = StubAuthenticator(restored: {
            attempts.increment() == 1 ? StubAuthenticator.plusAccount : nil
        })
        let model = AppModel(authenticator: authenticator, clock: HookClock())
        await model.restore()
        #expect(model.session == .signedIn(StubAuthenticator.plusAccount))

        authenticator.endSession()
        await model.watchSession()

        #expect(model.session == .signedOut)
    }

    @Test("FR-AUTH-03: a session that ended is not taken for one somebody signed in with since")
    func newSessionOutlivesOldEnding() async {
        let authenticator = StubAuthenticator(restored: { StubAuthenticator.plusAccount })
        let model = AppModel(authenticator: authenticator, clock: HookClock())
        await model.restore()

        authenticator.endSession()
        await model.watchSession()

        #expect(model.session == .signedIn(StubAuthenticator.plusAccount))
    }
}
