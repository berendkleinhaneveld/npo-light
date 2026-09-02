//
//  BackendError.swift
//  NPO light
//

import Foundation

/// What can go wrong behind the NPO boundary, in the app's own terms.
///
/// The endpoints, status codes and OAuth error strings stay inside the boundary
/// (ADR 0008); a caller gets a case it can put a sentence and a retry against,
/// which is what NFR-REL-02 asks for.
nonisolated enum BackendError: Error, Equatable {
    /// Nothing is stored, or NPO no longer recognises what is.
    case notSignedIn

    /// The sign-in code lapsed before anybody approved it. A fresh one is the
    /// remedy, not a retry of the same one.
    case signInExpired

    /// The pairing was rejected on the other device.
    case signInDeclined

    /// The request never reached NPO, or the reply never arrived. Distinct from
    /// every other case because it is the one that must not be read as evidence
    /// about the account.
    case unreachable

    /// NPO answered with something this app cannot read. `status` is `nil` when
    /// the reply was not even HTTP.
    case unexpectedResponse(status: Int?)
}
