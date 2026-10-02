//
//  SignInModel.swift
//  NPO light
//

import Foundation
import Observation

/// The sign-in screen's state: a code to show, a wait, and the ways it can end
/// (FR-AUTH-06).
@MainActor
@Observable
final class SignInModel {
    enum Problem: Equatable {
        /// Nobody approved the code in time. A fresh code is the remedy.
        case expired

        /// The pairing was rejected on the other device.
        case declined

        /// NPO could not be reached.
        case unreachable

        /// NPO answered with something the app cannot read.
        case unexpected
    }

    enum State: Equatable {
        /// Asking NPO for a code.
        case requesting

        /// The code is on screen and the app is polling for its approval.
        case waiting(DeviceCodeChallenge)

        case failed(Problem)
    }

    private(set) var state = State.requesting

    private let authenticator: any Authenticating
    private let clock: any Clocking
    private let onSignedIn: (Account) -> Void

    /// The code that was on screen when a problem interrupted the wait.
    private var interrupted: DeviceCodeChallenge?

    init(authenticator: any Authenticating,
         clock: any Clocking,
         onSignedIn: @escaping (Account) -> Void) {
        self.authenticator = authenticator
        self.clock = clock
        self.onSignedIn = onSignedIn
    }

    /// Asks for a fresh code, shows it, and waits for it to be approved on the
    /// other device. Nothing further is needed on the television.
    func signIn() async {
        interrupted = nil
        state = .requesting
        await run {
            let challenge = try await self.authenticator.startSignIn()
            return try await self.awaitApproval(of: challenge)
        }
    }

    /// The button on a problem: try again without leaving the screen.
    ///
    /// After a network problem the tokens may already be in the Keychain — the
    /// approval went through and only the subscription check was lost — and
    /// otherwise the code on screen may still be good. Both are tried before a
    /// new code makes the user start over on the phone.
    func retry() async {
        guard state == .failed(.unreachable) else {
            await signIn()
            return
        }
        let challenge = interrupted
        state = challenge.map { .waiting($0) } ?? .requesting
        await run {
            if let account = try await self.authenticator.restoredAccount() {
                return account
            }
            if let challenge, self.clock.now < challenge.expiresAt {
                return try await self.awaitApproval(of: challenge)
            }
            self.state = .requesting
            let fresh = try await self.authenticator.startSignIn()
            return try await self.awaitApproval(of: fresh)
        }
    }

    private func awaitApproval(of challenge: DeviceCodeChallenge) async throws -> Account {
        interrupted = challenge
        state = .waiting(challenge)
        return try await authenticator.awaitApproval(of: challenge)
    }

    private func run(_ attempt: () async throws -> Account) async {
        do {
            onSignedIn(try await attempt())
        } catch is CancellationError {
            // The screen went away. There is nobody to tell.
        } catch BackendError.signInExpired {
            state = .failed(.expired)
        } catch BackendError.signInDeclined {
            state = .failed(.declined)
        } catch BackendError.unreachable {
            state = .failed(.unreachable)
        } catch {
            state = .failed(.unexpected)
        }
    }
}
