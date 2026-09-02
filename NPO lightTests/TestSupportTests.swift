//
//  TestSupportTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The doubles the rest of the suite will lean on (ADR 0009). None of these
/// name a requirement: they prove the scaffolding, not the app.
struct TestSupportTests {
    @Test func stubRecordsWhatItWasSent() async throws {
        let stub = StubTransport { _ in .json(#"{"ok":"yes"}"#) }
        let request = try FakeIdentityProvider.request(path: "/connect/token", form: ["a": "b"])

        let response = try await stub.send(request)

        #expect(response.status == 200)
        #expect(stub.sent.count == 1)
        #expect(stub.sent.first?.url?.path == "/connect/token")
    }

    @Test func stubCanFailAndDelay() async throws {
        let clock = TestClock()
        let stub = StubTransport { _ in
            try await clock.wait(for: .seconds(30))
            throw BackendError.unreachable
        }
        let request = try FakeIdentityProvider.request(path: "/connect/token", form: [:])

        await #expect(throws: BackendError.unreachable) {
            _ = try await stub.send(request)
        }
        #expect(clock.waits == [.seconds(30)])
    }

    @Test func clockRecordsAndAdvances() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1000))

        try await clock.wait(for: .seconds(5))
        clock.advance(by: .seconds(15))

        #expect(clock.waits == [.seconds(5)])
        #expect(clock.now == Date(timeIntervalSince1970: 1020))
    }

    @Test func storeCountsItsSaves() throws {
        let store = InMemoryTokenStore()
        let session = Session(idToken: "id",
                              accessToken: "access",
                              refreshToken: "refresh",
                              accessTokenExpiresAt: Date(timeIntervalSince1970: 3600))

        try store.save(session)
        try store.save(session)

        #expect(store.saveCount == 2)
        #expect(try store.load() == session)
        try store.clear()
        #expect(try store.load() == nil)
    }

    @Test func fixtureLoadsFromTheBundle() throws {
        let body = try Fixture.json("device-authorization-200")

        #expect(body["verification_uri"] as? String == "https://id.npo.nl/koppel")
        #expect(body["expires_in"] as? Int == 300)
        #expect(body["interval"] as? Int == 5)
    }

    /// The fixtures record the shape; the fake generates one. They have to
    /// agree, or a client tested against the fake meets a different response in
    /// production than the one the decoder tests decoded.
    @Test func fakeMatchesTheCapturedShape() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let request = try FakeIdentityProvider.request(path: "/connect/deviceauthorization", form: [:])

        let generated = try jsonObject(in: try await provider.send(request))

        #expect(Set(generated.keys) == Set(try Fixture.json("device-authorization-200").keys))
    }

    @Test func fakeMatchesTheCapturedTokens() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let deviceCode = try await provider.startedDeviceCode()
        provider.approve()

        let generated = try jsonObject(in: try await provider.poll(deviceCode: deviceCode))

        #expect(Set(generated.keys) == Set(try Fixture.json("token-success-200").keys))
    }

    @Test func fakeMatchesTheCapturedPending() async throws {
        let provider = FakeIdentityProvider(clock: TestClock())
        let deviceCode = try await provider.startedDeviceCode()

        let generated = try jsonObject(in: try await provider.poll(deviceCode: deviceCode))

        #expect(Set(generated.keys) == Set(try Fixture.json("token-authorization-pending-400").keys))
    }
}
