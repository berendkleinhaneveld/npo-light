//
//  KeychainTokenStoreTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The real Keychain, under a service name of this run's own so that repeated
/// and parallel runs do not meet each other's items (ADR 0009).
///
/// What this cannot show is the half that only hardware can: that the item
/// survives a reboot, and is readable on a television nobody has touched.
struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(service: "com.bearduck.NPO-light.tests.\(UUID().uuidString)")

    private let session = Session(idToken: "id",
                                  accessToken: "access",
                                  refreshToken: "refresh",
                                  accessTokenExpiresAt: Date(timeIntervalSince1970: 3600),
                                  deviceIdentifier: "0:device:identifier")

    @Test("FR-AUTH-02: a session saved to the Keychain is read back as it was")
    func savedSessionIsReadBack() throws {
        defer { try? store.clear() }
        #expect(try store.load() == nil)

        try store.save(session)

        #expect(try store.load() == session)
    }

    @Test("FR-AUTH-02, FR-AUTH-07: saving again replaces the session instead of adding a second")
    func savingReplacesTheSession() throws {
        defer { try? store.clear() }
        let renewed = Session(idToken: "id-2",
                              accessToken: "access-2",
                              refreshToken: "refresh-2",
                              accessTokenExpiresAt: Date(timeIntervalSince1970: 7200),
                              deviceIdentifier: session.deviceIdentifier)

        try store.save(session)
        try store.save(renewed)

        #expect(try store.load() == renewed)
    }

    @Test("FR-AUTH-02, FR-AUTH-04: clearing leaves no item behind, and clearing twice is not an error")
    func clearingLeavesNothingBehind() throws {
        try store.save(session)

        try store.clear()
        try store.clear()

        #expect(try store.load() == nil)
    }
}
