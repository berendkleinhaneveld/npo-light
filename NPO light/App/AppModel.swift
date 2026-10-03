//
//  AppModel.swift
//  NPO light
//

import Foundation
import Observation

/// The one scope that belongs to no screen: whether there is a session, and
/// what `RootView` therefore shows (ADR 0011, FR-AUTH-01).
@MainActor
@Observable
final class AppModel {
    enum SessionState: Equatable {
        /// Launch, before the stored session has been looked at.
        case restoring

        /// No session: sign-in is the only screen.
        case signedOut

        case signedIn(Account)

        /// The account signed in but has no NPO Plus. The explanation stays
        /// until it is acknowledged, and only then is the account signed out
        /// (FR-AUTH-08).
        case plusRequired

        /// A session is stored, but NPO could not be asked about it. That is
        /// not evidence about the account, so nothing is signed out.
        case unreachable
    }

    private(set) var session = SessionState.restoring

    private let authenticator: any Authenticating

    init(authenticator: any Authenticating) {
        self.authenticator = authenticator
    }

    /// Looks at the stored session, at launch and again on a retry. The
    /// subscription is checked every time, not only at sign-in (FR-AUTH-08).
    func restore() async {
        session = .restoring
        do {
            guard let account = try await authenticator.restoredAccount() else {
                session = .signedOut
                return
            }
            admit(account)
        } catch BackendError.notSignedIn {
            session = .signedOut
        } catch {
            session = .unreachable
        }
    }

    /// The sign-in screen's last step: the account that was just approved.
    func admit(_ account: Account) {
        session = account.hasPlus ? .signedIn(account) : .plusRequired
    }

    /// The user has read why the account is turned away; now it is signed out.
    func acknowledgePlusRequired() {
        signOut()
    }

    /// Forgets the session on this television and returns to sign-in. Local
    /// data is not touched (FR-AUTH-04).
    func signOut() {
        do {
            try authenticator.signOut()
        } catch {
            // The Keychain refused to delete. Sign-in is still where the user
            // has to go: a fresh sign-in replaces whatever was left behind.
        }
        session = .signedOut
    }
}
