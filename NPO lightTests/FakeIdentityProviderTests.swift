//
//  FakeIdentityProviderTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The fake identity provider carries real behaviour, so it gets real tests:
/// a double that quietly stops modelling the rule it exists for is worse than
/// no double at all (ADR 0009).
struct FakeIdentityProviderTests {
    @Test func pollIsPendingUntilApproved() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let deviceCode = try await provider.startedDeviceCode()

        let pending = try await provider.poll(deviceCode: deviceCode)

        #expect(pending.status == 400)
        #expect(try oauthError(in: pending) == "authorization_pending")
        #expect(provider.currentRefreshToken == nil)
    }

    @Test func approvalIssuesTokensOnce() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let deviceCode = try await provider.startedDeviceCode()
        provider.approve()

        let issued = try await provider.poll(deviceCode: deviceCode)
        let again = try await provider.poll(deviceCode: deviceCode)

        #expect(issued.status == 200)
        #expect(try field("refresh_token", in: issued) == "refresh-token-1")
        // The grant is consumed by the first exchange; polling on is a bug.
        #expect(again.status == 400)
        #expect(try oauthError(in: again) == "invalid_grant")
        #expect(provider.pollCount == 2)
    }

    @Test func refreshRotatesTheToken() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let deviceCode = try await provider.startedDeviceCode()
        provider.approve()
        let issued = try await provider.poll(deviceCode: deviceCode)
        let first = try field("refresh_token", in: issued)

        let refreshed = try await provider.refresh(refreshToken: first)

        #expect(refreshed.status == 200)
        #expect(try field("refresh_token", in: refreshed) == "refresh-token-2")
        #expect(provider.currentRefreshToken == "refresh-token-2")
    }

    /// The rule that decided the shape of this double. NPO's refresh tokens are
    /// single-use, so an app that keeps the old one after a successful refresh
    /// is dead on the next attempt — and a stub that always answers with fresh
    /// tokens would let that ship.
    @Test func spentRefreshTokenIsRefused() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let deviceCode = try await provider.startedDeviceCode()
        provider.approve()
        let spent = try field("refresh_token", in: try await provider.poll(deviceCode: deviceCode))
        _ = try await provider.refresh(refreshToken: spent)

        let reused = try await provider.refresh(refreshToken: spent)

        #expect(reused.status == 400)
        #expect(try oauthError(in: reused) == "invalid_grant")
        #expect(provider.refreshCount == 2)
    }

    @Test func codeExpiresAfterTheWindow() async throws {
        let clock = TestClock()
        let provider = FakeIdentityProvider(clock: clock)
        let deviceCode = try await provider.startedDeviceCode()

        clock.advance(by: .seconds(FakeIdentityProvider.windowInSeconds))
        provider.approve()
        let expired = try await provider.poll(deviceCode: deviceCode)

        #expect(try oauthError(in: expired) == "expired_token")
    }

    @Test func decliningAnswersAccessDenied() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let deviceCode = try await provider.startedDeviceCode()

        provider.decline()
        let declined = try await provider.poll(deviceCode: deviceCode)

        #expect(try oauthError(in: declined) == "access_denied")
    }

    @Test func aFreshCodeInvalidatesTheOld() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let stale = try await provider.startedDeviceCode()
        _ = try await provider.startedDeviceCode()

        provider.approve()
        let refused = try await provider.poll(deviceCode: stale)

        #expect(try oauthError(in: refused) == "invalid_grant")
    }
}
