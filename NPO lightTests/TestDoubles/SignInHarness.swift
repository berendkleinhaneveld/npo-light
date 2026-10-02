//
//  SignInHarness.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// The real authenticator over a fake identity provider and a canned app
/// backend, sharing one clock and one in-memory token store (ADR 0009).
///
/// Requests for `id.npo.nl` go to ``identityProvider``; everything else is the
/// app backend, answered by the closure the test supplies.
nonisolated struct SignInHarness {
    static let premiumAccount = #"{"guid":"account-1","subscriptionType":"premium"}"#

    let clock: TestClock
    let store: InMemoryTokenStore
    let identityProvider: FakeIdentityProvider
    let transport: StubTransport
    let authenticator: NPOAuthenticator

    /// - Parameters:
    ///   - beforeIdentityResponse: runs before the identity provider answers,
    ///     for a test that has to make two callers overlap.
    ///   - backend: answers the app backend's requests.
    init(
        beforeIdentityResponse: @escaping @Sendable (URLRequest) async -> Void = { _ in },
        backend: @escaping @Sendable (URLRequest) async throws -> HTTPResponse = { _ in
            .json(SignInHarness.premiumAccount)
        }
    ) {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let store = InMemoryTokenStore()
        let identityProvider = FakeIdentityProvider(clock: clock, beforeResponse: beforeIdentityResponse)
        let transport = StubTransport { request in
            if request.url?.host == "id.npo.nl" {
                return try await identityProvider.send(request)
            }
            return try await backend(request)
        }
        self.clock = clock
        self.store = store
        self.identityProvider = identityProvider
        self.transport = transport
        authenticator = NPOAuthenticator(transport: transport, tokenStore: store, clock: clock)
    }

    /// Signs in the way a user would: a code, an approval, a poll.
    @discardableResult
    func signIn() async throws -> Account {
        let challenge = try await authenticator.startSignIn()
        identityProvider.approve()
        return try await authenticator.awaitApproval(of: challenge)
    }

    /// Every request that went to the app backend, oldest first.
    var backendRequests: [URLRequest] {
        transport.sent.filter { $0.url?.host != "id.npo.nl" }
    }
}

extension URLRequest {
    /// The fields of a form body, as the identity provider would read them.
    var formFields: [String: String] {
        guard let httpBody, let encoded = String(data: httpBody, encoding: .utf8) else {
            return [:]
        }
        var fields: [String: String] = [:]
        for pair in encoded.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            fields[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return fields
    }
}

/// A counter several tasks can share.
nonisolated final class Counter: Sendable {
    private let count = Mutex(0)

    /// Adds one and answers with the new value.
    @discardableResult
    func increment() -> Int {
        count.withLock { value in
            value += 1
            return value
        }
    }

    var value: Int { count.withLock { $0 } }
}
