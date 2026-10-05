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

    /// How long to leave between asking NPO again while it cannot be reached.
    static let reconnectInterval = Duration.seconds(30)

    private(set) var session = SessionState.restoring

    /// The app is signed in on what NPO last said about the account, because
    /// NPO cannot be asked now (NFR-REL-01).
    private(set) var isOffline = false

    private let authenticator: any Authenticating
    private let clock: any Clocking
    private let keep: (Account?) -> Void

    /// The account NPO last admitted, for a launch that cannot ask.
    private var remembered: Account?

    /// - Parameters:
    ///   - remembered: the account NPO admitted before this launch.
    ///   - keep: writes the admitted account down for the next launch, and
    ///     forgets it when handed `nil`.
    init(authenticator: any Authenticating,
         clock: any Clocking,
         remembered: Account? = nil,
         keep: @escaping (Account?) -> Void = { _ in }) {
        self.authenticator = authenticator
        self.clock = clock
        self.remembered = remembered
        self.keep = keep
    }

    /// Looks at the stored session, at launch and again on a retry. The
    /// subscription is checked every time, not only at sign-in (FR-AUTH-08).
    func restore() async {
        session = .restoring
        guard await !ask() else { return }
        // NPO could not be asked. With an account it admitted before, the
        // app goes on with what it knows and says so (NFR-REL-01); without
        // one there is nothing to go on.
        if let remembered {
            session = .signedIn(remembered)
            isOffline = true
        } else {
            session = .unreachable
        }
    }

    /// Asks NPO again, for as long as it cannot be reached, so that coming
    /// back online needs no relaunch (NFR-REL-01). Ends when the task it
    /// runs in is cancelled.
    func reconnect() async {
        while isOffline {
            do {
                try await clock.wait(for: Self.reconnectInterval)
            } catch {
                return
            }
            await ask()
        }
    }

    /// Asks NPO about the stored session and acts on the answer. `false`
    /// when there was none, which changes nothing.
    @discardableResult
    private func ask() async -> Bool {
        do {
            guard let account = try await authenticator.restoredAccount() else {
                leave()
                return true
            }
            admit(account)
        } catch BackendError.notSignedIn {
            leave()
        } catch {
            return false
        }
        return true
    }

    /// The sign-in screen's last step: the account that was just approved.
    func admit(_ account: Account) {
        isOffline = false
        remember(account.hasPlus ? account : nil)
        let admitted = account.hasPlus ? SessionState.signedIn(account) : .plusRequired
        // Answered as before: nothing on screen has to be made again.
        guard session != admitted else { return }
        session = admitted
    }

    /// There is no session any more.
    private func leave() {
        isOffline = false
        remember(nil)
        session = .signedOut
    }

    private func remember(_ account: Account?) {
        guard account != remembered else { return }
        remembered = account
        keep(account)
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
        leave()
    }
}

/// The account NPO last admitted, kept where a relaunch finds it, so that a
/// launch without a network still has an answer (NFR-REL-01). It is no
/// credential: the session itself stays in the Keychain (NFR-PRIV-02).
nonisolated struct StoredAccount: Sendable {
    private static let key = "account.admitted"

    /// Names the defaults to keep it in; `nil` is the app's own. A test names
    /// a suite of its own.
    let suite: String?

    init(suite: String? = nil) {
        self.suite = suite
    }

    /// Only an account with NPO Plus is ever kept, so that is what one read
    /// back has (FR-AUTH-08).
    var account: Account? {
        get { defaults.string(forKey: Self.key).map { Account(identifier: $0, hasPlus: true) } }
        nonmutating set {
            guard let newValue, newValue.hasPlus else {
                defaults.removeObject(forKey: Self.key)
                return
            }
            defaults.set(newValue.identifier, forKey: Self.key)
        }
    }

    private var defaults: UserDefaults {
        suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
