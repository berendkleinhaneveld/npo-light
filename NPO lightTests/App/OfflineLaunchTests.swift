//
//  OfflineLaunchTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

@MainActor
struct OfflineLaunchTests {
    nonisolated private static let plus = StubAuthenticator.plusAccount

    @Test("NFR-REL-01: a launch that cannot reach NPO goes on with the account it admitted before")
    func offlineLaunchShowsHome() async {
        let authenticator = StubAuthenticator(restored: { throw BackendError.unreachable })
        let model = AppModel(authenticator: authenticator, clock: HookClock(), remembered: Self.plus)

        await model.restore()

        #expect(model.session == .signedIn(Self.plus))
        #expect(model.isOffline)
        #expect(authenticator.signOutCount == 0)
    }

    @Test("NFR-REL-01: a launch that reaches NPO is not offline")
    func reachableLaunchIsOnline() async {
        let model = AppModel(authenticator: StubAuthenticator(restored: { Self.plus }),
                             clock: HookClock(),
                             remembered: Self.plus)

        await model.restore()

        #expect(model.session == .signedIn(Self.plus))
        #expect(!model.isOffline)
    }

    @Test("NFR-REL-01: coming back online is noticed without a relaunch")
    func reconnectsWithoutRelaunch() async {
        let attempts = Counter()
        let authenticator = StubAuthenticator(restored: {
            if attempts.increment() < 3 { throw BackendError.unreachable }
            return Self.plus
        })
        let model = AppModel(authenticator: authenticator, clock: HookClock(), remembered: Self.plus)
        await model.restore()

        await model.reconnect()

        #expect(model.session == .signedIn(Self.plus))
        #expect(!model.isOffline)
        #expect(authenticator.restoreCount == 3)
    }

    @Test("NFR-REL-01: nothing is asked again while NPO can be reached")
    func onlineAsksNothingAgain() async {
        let authenticator = StubAuthenticator(restored: { Self.plus })
        let model = AppModel(authenticator: authenticator, clock: HookClock())
        await model.restore()

        await model.reconnect()

        #expect(authenticator.restoreCount == 1)
    }

    @Test("FR-AUTH-08: a subscription that lapsed while offline is caught when NPO answers again")
    func lapsedPlusIsCaughtOnReturn() async {
        let attempts = Counter()
        let kept = Kept()
        let model = AppModel(authenticator: StubAuthenticator(restored: {
            if attempts.increment() == 1 { throw BackendError.unreachable }
            return StubAuthenticator.freeAccount
        }), clock: HookClock(), remembered: Self.plus, keep: { kept.record($0) })
        await model.restore()

        await model.reconnect()

        #expect(model.session == .plusRequired)
        #expect(!model.isOffline)
        // The next launch without a network has no account to go on with.
        #expect(kept.accounts == [nil])
    }

    @Test("FR-AUTH-03: a session that ended while offline returns to sign-in when NPO answers again")
    func deadSessionIsCaughtOnReturn() async {
        let attempts = Counter()
        let model = AppModel(authenticator: StubAuthenticator(restored: {
            if attempts.increment() == 1 { throw BackendError.unreachable }
            throw BackendError.notSignedIn
        }), clock: HookClock(), remembered: Self.plus)
        await model.restore()

        await model.reconnect()

        #expect(model.session == .signedOut)
        #expect(!model.isOffline)
    }

    @Test("NFR-REL-01: the admitted account is kept for a launch without a network, and forgotten at sign-out")
    func admittedAccountIsKept() {
        let kept = Kept()
        let model = AppModel(authenticator: StubAuthenticator(), clock: HookClock(), keep: { kept.record($0) })

        model.admit(Self.plus)
        model.admit(Self.plus)
        model.signOut()

        #expect(kept.accounts == [Self.plus, nil])
    }

    @Test("FR-AUTH-04: after signing out, a launch without a network does not show the home page")
    func signedOutStaysOutOffline() async {
        let model = AppModel(authenticator: StubAuthenticator(restored: { throw BackendError.unreachable }),
                             clock: HookClock(),
                             remembered: Self.plus)
        model.signOut()

        await model.restore()

        #expect(model.session == .unreachable)
    }

    @Test("NFR-REL-01: the admitted account survives a relaunch")
    func storedAccountSurvivesRelaunch() throws {
        let suite = "offline-launch-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        #expect(StoredAccount(suite: suite).account == nil)

        StoredAccount(suite: suite).account = Self.plus

        #expect(StoredAccount(suite: suite).account == Self.plus)
    }

    @Test("FR-AUTH-08: an account without NPO Plus is never kept as admitted")
    func freeAccountIsNotStored() {
        let suite = "offline-launch-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        StoredAccount(suite: suite).account = Self.plus

        StoredAccount(suite: suite).account = StubAuthenticator.freeAccount

        #expect(StoredAccount(suite: suite).account == nil)
    }
}

/// What the model asked to be written down, in order.
@MainActor
private final class Kept {
    private(set) var accounts: [Account?] = []

    func record(_ account: Account?) {
        accounts.append(account)
    }
}
