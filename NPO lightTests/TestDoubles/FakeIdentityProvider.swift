//
//  FakeIdentityProvider.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// `id.npo.nl`'s device-code endpoints, as an `HTTPTransport`.
///
/// It answers the two calls the grant needs, in the shapes captured from the
/// real thing (`Fixtures/README.md`), and it models the three rules a canned
/// response cannot — each one a bug the app can really have, and a stub would
/// hide (ADR 0007, ADR 0009):
///
/// 1. **Approval takes time.** The poll answers `authorization_pending` until
///    ``approve()`` is called, so a client that never polls never signs in.
/// 2. **Refresh tokens rotate and are single-use.** Presenting a spent one
///    answers `invalid_grant`, exactly as NPO does. A stub that always hands
///    back fresh tokens passes an app that is dead on real hardware.
/// 3. **The code expires.** Past the window the poll answers `expired_token`
///    rather than staying pending for ever.
///
/// It is a fake *identity provider*, not a fake NPO. The catalogue has no state
/// worth modelling, so it gets stubs and fixtures.
nonisolated final class FakeIdentityProvider: HTTPTransport {
    /// NPO's own values, from the captured `200` response.
    static let windowInSeconds = 300
    static let pollIntervalInSeconds = 5
    static let accessTokenLifetimeInSeconds = 3600

    private static let deviceCodeGrant = "urn:ietf:params:oauth:grant-type:device_code"

    private struct State {
        var generation = 0
        var userCode = ""
        var deviceCode = ""
        var expiresAt = Date.distantPast
        var isApproved = false
        var isDeclined = false
        var isRedeemed = false
        var refreshToken: String?
        var issuedTokens = 0
        var pollCount = 0
        var refreshCount = 0
    }

    private let clock: any Clocking
    private let beforeResponse: @Sendable (URLRequest) async -> Void
    private let state = Mutex(State())

    /// - Parameters:
    ///   - clock: the same clock the client under test uses, so that the
    ///     expiry the provider enforces and the waits the client makes agree.
    ///   - beforeResponse: called before each response is produced. A test that
    ///     needs two requests to overlap — proving that concurrent callers cause
    ///     exactly one refresh — parks in here rather than racing a sleep.
    init(clock: any Clocking,
         beforeResponse: @escaping @Sendable (URLRequest) async -> Void = { _ in }) {
        self.clock = clock
        self.beforeResponse = beforeResponse
    }

    // MARK: what the test drives

    /// Approves the outstanding code, as the user would at `id.npo.nl/koppel`.
    func approve() {
        state.withLock { $0.isApproved = true }
    }

    /// Rejects the pairing on the other device.
    func decline() {
        state.withLock { $0.isDeclined = true }
    }

    /// How many times the token endpoint was polled for the device code.
    var pollCount: Int { state.withLock { $0.pollCount } }

    /// How many refresh exchanges were attempted, successful or not.
    var refreshCount: Int { state.withLock { $0.refreshCount } }

    /// The refresh token NPO would accept right now, if any.
    var currentRefreshToken: String? { state.withLock { $0.refreshToken } }

    /// The code currently on the television.
    var userCode: String { state.withLock { $0.userCode } }

    // MARK: the endpoints

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        await beforeResponse(request)
        switch request.url?.path {
        case "/connect/deviceauthorization":
            return deviceAuthorization()
        case "/connect/token":
            return token(form: Self.form(in: request))
        default:
            return .json(#"{"error":"not_found"}"#, status: 404)
        }
    }

    private func deviceAuthorization() -> HTTPResponse {
        let now = clock.now
        let (userCode, deviceCode) = state.withLock { state -> (String, String) in
            state.generation += 1
            state.userCode = "5141192\(state.generation)"
            state.deviceCode = "device-code-\(state.generation)"
            state.expiresAt = now.addingTimeInterval(TimeInterval(Self.windowInSeconds))
            state.isApproved = false
            state.isDeclined = false
            state.isRedeemed = false
            return (state.userCode, state.deviceCode)
        }
        return .json("""
        {"device_code":"\(deviceCode)",\
        "user_code":"\(userCode)",\
        "verification_uri":"https://id.npo.nl/koppel",\
        "verification_uri_complete":"https://id.npo.nl/koppel?userCode=\(userCode)",\
        "expires_in":\(Self.windowInSeconds),\
        "interval":\(Self.pollIntervalInSeconds)}
        """)
    }

    private func token(form: [String: String]) -> HTTPResponse {
        switch form["grant_type"] {
        case Self.deviceCodeGrant:
            return deviceCodeToken(presented: form["device_code"])
        case "refresh_token":
            return refreshedToken(presented: form["refresh_token"])
        default:
            return Self.oauthError("unsupported_grant_type")
        }
    }

    private func deviceCodeToken(presented: String?) -> HTTPResponse {
        let now = clock.now
        return state.withLock { state in
            state.pollCount += 1
            guard let presented, presented == state.deviceCode else {
                return Self.oauthError("invalid_grant")
            }
            guard !state.isDeclined else {
                return Self.oauthError("access_denied")
            }
            guard now < state.expiresAt else {
                return Self.oauthError("expired_token")
            }
            guard state.isApproved else {
                return Self.oauthError("authorization_pending")
            }
            // The grant is consumed by the first successful exchange; polling on
            // after that is a client bug, and NPO answers it as one.
            guard !state.isRedeemed else {
                return Self.oauthError("invalid_grant")
            }
            state.isRedeemed = true
            return Self.issueTokens(into: &state)
        }
    }

    private func refreshedToken(presented: String?) -> HTTPResponse {
        state.withLock { state in
            state.refreshCount += 1
            // Rotation is what makes this a refusal: the stored token is
            // replaced on every success, so a spent one no longer matches.
            guard let presented, presented == state.refreshToken else {
                return Self.oauthError("invalid_grant")
            }
            return Self.issueTokens(into: &state)
        }
    }

    private static func issueTokens(into state: inout State) -> HTTPResponse {
        state.issuedTokens += 1
        let generation = state.issuedTokens
        let refreshToken = "refresh-token-\(generation)"
        state.refreshToken = refreshToken
        return .json("""
        {"access_token":"access-token-\(generation)",\
        "id_token":"id-token-\(generation)",\
        "refresh_token":"\(refreshToken)",\
        "expires_in":\(accessTokenLifetimeInSeconds)}
        """)
    }

    /// The IdP answers a poll that is not ready with `400` and an `error` field;
    /// reading that body as a normal state, rather than as a failure, is the
    /// whole trick of the grant.
    private static func oauthError(_ code: String) -> HTTPResponse {
        .json(#"{"error":"\#(code)"}"#, status: 400)
    }

    /// The token endpoint takes a form body, not JSON.
    private static func form(in request: URLRequest) -> [String: String] {
        guard let body = request.httpBody, let encoded = String(data: body, encoding: .utf8) else {
            return [:]
        }
        var form: [String: String] = [:]
        for pair in encoded.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let name = parts.first, parts.count == 2, let value = parts.last else { continue }
            form[Self.formDecode(String(name))] = Self.formDecode(String(value))
        }
        return form
    }

    /// `application/x-www-form-urlencoded` spells a space `+`, which
    /// `removingPercentEncoding` does not know about.
    private static func formDecode(_ value: String) -> String {
        let spaced = value.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
