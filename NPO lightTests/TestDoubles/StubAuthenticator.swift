//
//  StubAuthenticator.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// An `Authenticating` that answers from closures, in the app's own types: the
/// double for everything above the NPO boundary (ADR 0009). No JSON up here.
nonisolated final class StubAuthenticator: Authenticating {
    static let challenge = DeviceCodeChallenge(
        userCode: "51411921",
        verificationURL: URL(filePath: "/koppel"),
        completeVerificationURL: URL(filePath: "/koppel-with-code"),
        pollInterval: .seconds(5),
        expiresAt: Date(timeIntervalSince1970: 300),
        deviceCode: "device-code"
    )

    static let plusAccount = Account(identifier: "account-1", hasPlus: true)
    static let freeAccount = Account(identifier: "account-2", hasPlus: false)

    private struct Calls {
        var starts = 0
        var approvals: [DeviceCodeChallenge] = []
        var restores = 0
        var signOuts = 0
    }

    private let start: @Sendable () async throws -> DeviceCodeChallenge
    private let approval: @Sendable (DeviceCodeChallenge) async throws -> Account
    private let restored: @Sendable () async throws -> Account?
    private let signingOut: @Sendable () throws -> Void
    private let calls = Mutex(Calls())
    private let endings = AsyncStream.makeStream(of: Void.self)

    var endedSessions: AsyncStream<Void> { endings.stream }

    /// NPO ended the session while the app was running, and nothing ends it
    /// after that: whoever listens is let go.
    func endSession() {
        endings.continuation.yield()
        endings.continuation.finish()
    }

    init(
        start: @escaping @Sendable () async throws -> DeviceCodeChallenge = { StubAuthenticator.challenge },
        approval: @escaping @Sendable (DeviceCodeChallenge) async throws -> Account = { _ in
            StubAuthenticator.plusAccount
        },
        restored: @escaping @Sendable () async throws -> Account? = { nil },
        signingOut: @escaping @Sendable () throws -> Void = {}
    ) {
        self.start = start
        self.approval = approval
        self.restored = restored
        self.signingOut = signingOut
    }

    var startCount: Int { calls.withLock { $0.starts } }
    var awaitedChallenges: [DeviceCodeChallenge] { calls.withLock { $0.approvals } }
    var restoreCount: Int { calls.withLock { $0.restores } }
    var signOutCount: Int { calls.withLock { $0.signOuts } }

    func startSignIn() async throws -> DeviceCodeChallenge {
        calls.withLock { $0.starts += 1 }
        return try await start()
    }

    func awaitApproval(of challenge: DeviceCodeChallenge) async throws -> Account {
        calls.withLock { $0.approvals.append(challenge) }
        return try await approval(challenge)
    }

    func restoredAccount() async throws -> Account? {
        calls.withLock { $0.restores += 1 }
        return try await restored()
    }

    func signOut() throws {
        calls.withLock { $0.signOuts += 1 }
        try signingOut()
    }
}

/// Holds a caller until the test lets it through, so that a state which only
/// exists while something is waiting can be looked at.
nonisolated final class Gate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func open() {
        continuation.yield()
    }

    func wait() async {
        for await _ in stream { return }
    }
}

/// The accounts sign-in handed over, in order.
@MainActor
final class SignedInRecorder {
    private(set) var accounts: [Account] = []

    func record(_ account: Account) {
        accounts.append(account)
    }
}
