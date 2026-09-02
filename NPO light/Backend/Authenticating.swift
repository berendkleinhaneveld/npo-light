//
//  Authenticating.swift
//  NPO light
//

import Foundation

/// What the sign-in screen puts in front of the user (FR-AUTH-06).
nonisolated struct DeviceCodeChallenge: Sendable, Equatable {
    /// The eight-digit code, shown large enough to read from a sofa.
    let userCode: String

    /// The short address, shown as text because it is short enough to type.
    let verificationURL: URL

    /// The same address with the code already in its query string. This is what
    /// the QR code encodes, and it is used exactly as NPO returned it rather
    /// than rebuilt by appending the code to ``verificationURL``.
    let completeVerificationURL: URL

    /// How long to leave between asking whether it has been approved yet. NPO
    /// advertises it; it is not a constant this app chooses.
    let pollInterval: Duration

    /// When the code lapses and a fresh one has to be offered.
    let expiresAt: Date

    /// Opaque: the value the app polls with. Never displayed, never logged.
    ///
    /// It rides along here because the grant is two calls rather than one. A
    /// real module boundary would keep it out of a caller's reach; a
    /// single-module app cannot, so this comment does the work instead.
    let deviceCode: String
}

/// The signed-in account, as the app above the boundary understands it.
nonisolated struct Account: Sendable, Equatable {
    /// NPO's identifier for the account.
    let identifier: String

    /// Whether the account carries NPO Plus. Only the exact subscription type
    /// `premium` sets this; every other value, and a missing field, reads as a
    /// free account and is turned away (FR-AUTH-08).
    let hasPlus: Bool
}

/// Signing in, and staying signed in.
///
/// The device-code grant, the polling, the token rotation and the Keychain all
/// live behind this (ADR 0007, ADR 0008). A caller sees a code to show, a wait,
/// and an account.
nonisolated protocol Authenticating: Sendable {
    /// Asks NPO for a code and returns what the screen shows (FR-AUTH-06).
    func startSignIn() async throws -> DeviceCodeChallenge

    /// Polls until the challenge is approved on the other device, stores the
    /// session, and answers with the account that signed in.
    ///
    /// Throws ``BackendError/signInExpired`` when the code lapses first, and
    /// ``BackendError/signInDeclined`` when it is rejected — the two are
    /// distinguishable on screen, and each offers a way to try again.
    func awaitApproval(of challenge: DeviceCodeChallenge) async throws -> Account

    /// The account for a stored session, renewing the session first if it has
    /// lapsed (FR-AUTH-03, FR-AUTH-07).
    ///
    /// `nil` when nothing is stored, which is the launch that shows sign-in
    /// (FR-AUTH-01). Throws ``BackendError/unreachable`` rather than answering
    /// `nil` when the network is the problem: an unreachable backend is not
    /// evidence about the account (FR-AUTH-08).
    func restoredAccount() async throws -> Account?

    /// Forgets the session on this television.
    ///
    /// Local only: a public client cannot revoke its own grant at NPO, and the
    /// screen says so rather than implying otherwise (FR-AUTH-04, ADR 0007).
    func signOut() throws
}
