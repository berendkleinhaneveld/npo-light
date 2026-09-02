//
//  TokenStore.swift
//  NPO light
//

import Foundation

/// The credential material for a signed-in account.
///
/// It lives *below* the NPO boundary. Nothing above the boundary sees a token
/// (ADR 0008): a screen is given an ``Account``.
nonisolated struct Session: Sendable, Equatable {
    /// The bearer for the app backend. Counter-intuitively this is the
    /// `id_token` and not the ``accessToken``: with the access token
    /// `/profiles` answers 200 while `/account` answers 401, a half-accepted
    /// credential that reads like a header problem. See ADR 0007.
    let idToken: String

    /// The OAuth access token, as issued.
    let accessToken: String

    /// Single-use. NPO rotates it on every refresh, so a copy used twice leaves
    /// the session dead (FR-AUTH-07, ADR 0007).
    let refreshToken: String

    /// When ``accessToken`` lapses. Known up front, so the session is renewed
    /// before a request has to fail first (FR-AUTH-07).
    let accessTokenExpiresAt: Date
}

/// Where the session is kept between launches.
///
/// On a television the only implementation that can work is the Keychain —
/// `Documents` and `Application Support` are read-only on real hardware, so a
/// token written there is a session that silently ends (FR-AUTH-02, ADR 0007).
/// That is the implementation's problem; this protocol is what lets the rest of
/// the suite run without going near it (ADR 0009).
nonisolated protocol TokenStore: Sendable {
    /// The stored session, or `nil` when there is none.
    func load() throws -> Session?

    /// Replaces whatever is stored. Called on every refresh, because the
    /// rotated token has to land before it is needed again (FR-AUTH-07).
    func save(_ session: Session) throws

    /// Forgets the session. Sign-out is local only (FR-AUTH-04).
    func clear() throws
}
