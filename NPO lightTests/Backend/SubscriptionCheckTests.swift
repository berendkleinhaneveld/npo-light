//
//  SubscriptionCheckTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Reading the account, and what the app backend wants on the request.
struct SubscriptionCheckTests {
    // Invented bodies, written inline because nobody has captured an account
    // without NPO Plus (see `Fixtures/README.md`).
    @Test("FR-AUTH-08: only an exact premium subscription type counts as NPO Plus", arguments: [
        #"{"guid":"account-1","subscriptionType":"free"}"#,
        #"{"guid":"account-1","subscriptionType":"Premium"}"#,
        #"{"guid":"account-1","subscriptionType":"premium-trial"}"#,
        #"{"guid":"account-1","subscriptionType":""}"#,
        #"{"guid":"account-1","subscriptionType":null}"#,
        #"{"guid":"account-1"}"#
    ])
    func anythingElseIsNotPlus(body: String) async throws {
        let harness = SignInHarness(backend: { _ in .json(body) })

        let account = try await harness.signIn()

        #expect(account == Account(identifier: "account-1", hasPlus: false))
        #expect(harness.store.storedSession != nil)
    }

    @Test("FR-AUTH-08: a check that fails on the network is a network problem, and keeps the session")
    func networkFailureKeepsTheSession() async throws {
        let harness = SignInHarness(backend: { _ in throw URLError(.timedOut) })

        await #expect(throws: BackendError.unreachable) {
            try await harness.signIn()
        }
        #expect(harness.store.storedSession != nil)
    }

    @Test("FR-AUTH-08: an account answer the app cannot read is not taken for a free account")
    func unreadableAnswerIsAnError() async throws {
        let harness = SignInHarness(backend: { _ in .json("<html>", status: 502) })

        await #expect(throws: BackendError.unexpectedResponse(status: 502)) {
            try await harness.signIn()
        }
        #expect(harness.store.storedSession != nil)
    }

    @Test func backendIsAskedWithTheIdToken() async throws {
        let harness = SignInHarness()

        try await harness.signIn()

        let request = try #require(harness.backendRequests.first)
        let session = try #require(harness.store.storedSession)
        #expect(request.url?.absoluteString == "https://ios.bff.start.npox.nl/account")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer id-token-1")
        #expect(request.value(forHTTPHeaderField: "party-id")?.removingPercentEncoding
            == session.deviceIdentifier)
    }
}
