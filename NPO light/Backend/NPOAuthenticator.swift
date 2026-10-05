//
//  NPOAuthenticator.swift
//  NPO light
//

import Foundation
import Synchronization

/// Signing in at NPO and staying signed in: the device-code grant, the polling,
/// the token rotation and the subscription check (ADR 0007).
///
/// The session is read from the ``TokenStore`` every time rather than held
/// here, so there is one copy of a token that must never be used twice.
///
/// Its entrances are `@concurrent`: a screen model calls them from the main
/// actor, and without it the requests and their decoding would stay there
/// (NFR-PERF-05).
nonisolated final class NPOAuthenticator: Authenticating {
    /// A token this close to its expiry is renewed before it is used, so that a
    /// request does not have to fail first (FR-AUTH-07).
    static let renewalMargin: TimeInterval = 60

    /// What the grant's specification adds to the interval on `slow_down`, and
    /// the interval it prescribes when the response names none.
    private static let pollIntervalStep = Duration.seconds(5)

    private struct Renewal {
        var task: Task<Session, any Error>?
        /// Moves on at every sign-out, so that a renewal which was already
        /// under way cannot put a session back after the user removed it.
        var epoch = 0
    }

    private let transport: any HTTPTransport
    private let tokenStore: any TokenStore
    private let clock: any Clocking
    private let renewal = Mutex(Renewal())
    private let endings = AsyncStream.makeStream(of: Void.self)

    var endedSessions: AsyncStream<Void> { endings.stream }

    init(transport: any HTTPTransport, tokenStore: any TokenStore, clock: any Clocking) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.clock = clock
    }

    // MARK: Authenticating

    @concurrent
    func startSignIn() async throws -> DeviceCodeChallenge {
        let response = try await send(NPOWire.identityRequest(
            path: NPOWire.deviceAuthorizationPath,
            form: ["client_id": NPOWire.clientID, "scope": NPOWire.scope]
        ))
        guard response.status == 200 else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        let body = try Self.decoded(DeviceAuthorizationBody.self, from: response)
        return DeviceCodeChallenge(
            userCode: body.userCode,
            verificationURL: body.verificationURL,
            completeVerificationURL: body.completeVerificationURL,
            pollInterval: body.interval.map { .seconds($0) } ?? Self.pollIntervalStep,
            expiresAt: clock.now.addingTimeInterval(TimeInterval(body.expiresIn)),
            deviceCode: body.deviceCode
        )
    }

    @concurrent
    func awaitApproval(of challenge: DeviceCodeChallenge) async throws -> Account {
        var interval = challenge.pollInterval
        while clock.now < challenge.expiresAt {
            try await clock.wait(for: interval)
            let response = try await send(NPOWire.identityRequest(path: NPOWire.tokenPath, form: [
                "grant_type": NPOWire.deviceCodeGrant,
                "device_code": challenge.deviceCode,
                "client_id": NPOWire.clientID
            ]))
            if response.status == 200 {
                let session = try session(from: response, renewing: nil)
                try tokenStore.save(session)
                return try await account()
            }
            switch Self.oauthError(in: response) {
            case "authorization_pending": continue
            case "slow_down": interval += Self.pollIntervalStep
            case "expired_token": throw BackendError.signInExpired
            case "access_denied": throw BackendError.signInDeclined
            default: throw BackendError.unexpectedResponse(status: response.status)
            }
        }
        throw BackendError.signInExpired
    }

    @concurrent
    func restoredAccount() async throws -> Account? {
        guard try tokenStore.load() != nil else { return nil }
        return try await account()
    }

    func signOut() throws {
        try renewal.withLock { state in
            state.epoch += 1
            try tokenStore.clear()
        }
    }

    // MARK: the app backend

    /// One GET to the app backend with the stored session.
    ///
    /// A 401 is read as a lapsed session: it is renewed once and the request is
    /// repeated once (FR-AUTH-03). A second 401 is not a lapsed session any
    /// more, and is handed back to the caller rather than retried in a loop.
    @concurrent
    func backendResponse(to call: BackendCall) async throws -> HTTPResponse {
        let session = try await currentSession()
        let response = try await send(NPOWire.backendRequest(call, session: session))
        guard response.status == 401 else { return response }
        let renewed = try await renewedSession(replacing: session)
        return try await send(NPOWire.backendRequest(call, session: renewed))
    }

    /// Names the current sign-in without being a credential: it is made at
    /// sign-in and kept across renewals, so anything remembered about one
    /// account can be told apart from the next.
    func signInMarker() throws -> String {
        guard let stored = try tokenStore.load() else { throw BackendError.notSignedIn }
        return stored.deviceIdentifier
    }

    private func account() async throws -> Account {
        let response = try await backendResponse(to: BackendCall(path: NPOWire.accountPath))
        guard response.status == 200 else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        let body = try Self.decoded(AccountBody.self, from: response)
        // Admits what it recognises: an unfamiliar value never lets an account
        // through (FR-AUTH-08).
        return Account(identifier: body.guid,
                       hasPlus: body.subscriptionType == NPOWire.plusSubscriptionType)
    }

    // MARK: the session

    private func currentSession() async throws -> Session {
        guard let stored = try tokenStore.load() else { throw BackendError.notSignedIn }
        let renewFrom = stored.accessTokenExpiresAt.addingTimeInterval(-Self.renewalMargin)
        guard clock.now >= renewFrom else { return stored }
        return try await renewedSession(replacing: stored)
    }

    /// Renews `spent`, or joins the renewal already under way.
    ///
    /// NPO's refresh tokens are single-use, so two callers each presenting the
    /// same one would leave the second — and then the session — dead. The task
    /// is unstructured on purpose: a caller that is cancelled must not take the
    /// renewal with it between NPO rotating the token and this app storing it.
    private func renewedSession(replacing spent: Session) async throws -> Session {
        let task = renewal.withLock { state -> Task<Session, any Error> in
            if let task = state.task { return task }
            let epoch = state.epoch
            let task = Task {
                defer { self.renewal.withLock { $0.task = nil } }
                return try await self.renew(spent, epoch: epoch)
            }
            state.task = task
            return task
        }
        return try await task.value
    }

    private func renew(_ spent: Session, epoch: Int) async throws -> Session {
        guard let stored = try tokenStore.load() else { throw BackendError.notSignedIn }
        // Somebody else already renewed it between the caller reading the
        // session and getting here.
        guard stored.refreshToken == spent.refreshToken else { return stored }

        let response = try await send(NPOWire.identityRequest(path: NPOWire.tokenPath, form: [
            "grant_type": "refresh_token",
            "refresh_token": stored.refreshToken,
            "client_id": NPOWire.clientID
        ]))
        if response.status == 200 {
            let renewed = try session(from: response, renewing: stored)
            // Stored before anything can use it: the old token is spent now.
            try renewal.withLock { state in
                guard state.epoch == epoch else { throw BackendError.notSignedIn }
                try tokenStore.save(renewed)
            }
            return renewed
        }
        guard Self.oauthError(in: response) == "invalid_grant" else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        // NPO no longer recognises the session. Keeping the token would only
        // repeat this answer at every launch.
        try renewal.withLock { state in
            guard state.epoch == epoch else { return }
            try tokenStore.clear()
        }
        // Whichever page asked gets its error; the app has to hear it too.
        endings.continuation.yield()
        throw BackendError.notSignedIn
    }

    private func session(from response: HTTPResponse, renewing previous: Session?) throws -> Session {
        let body = try Self.decoded(TokenBody.self, from: response)
        // A renewal may answer without either; then what was there still holds.
        guard let idToken = body.idToken ?? previous?.idToken,
              let refreshToken = body.refreshToken ?? previous?.refreshToken else {
            throw BackendError.unexpectedResponse(status: response.status)
        }
        return Session(
            idToken: idToken,
            accessToken: body.accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: clock.now.addingTimeInterval(TimeInterval(body.expiresIn)),
            deviceIdentifier: previous?.deviceIdentifier ?? NPOWire.makeDeviceIdentifier()
        )
    }

    // MARK: the wire

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await transport.reaching(request)
    }

    private static func decoded<Body: Decodable>(_ type: Body.Type,
                                                 from response: HTTPResponse) throws -> Body {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw BackendError.unexpectedResponse(status: response.status)
        }
    }

    private static func oauthError(in response: HTTPResponse) -> String? {
        (try? JSONDecoder().decode(OAuthErrorBody.self, from: response.body))?.error
    }
}
