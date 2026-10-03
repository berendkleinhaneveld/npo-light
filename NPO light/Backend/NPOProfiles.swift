//
//  NPOProfiles.swift
//  NPO light
//

import Foundation
import Synchronization

/// Which of the account's NPO profiles each mode asks as (ADR 0014).
///
/// Shared by everything behind the boundary that makes a profile-scoped call,
/// so that the catalogue and playback agree and ask NPO once.
nonisolated final class NPOProfiles: Sendable {
    private struct Known {
        /// The sign-in these profiles belong to. Another account has others.
        let marker: String
        let byMode: [Mode: String]
    }

    private let authenticator: NPOAuthenticator
    private let known = Mutex<Known?>(nil)

    init(authenticator: NPOAuthenticator) {
        self.authenticator = authenticator
    }

    /// The modes the account can use, asked of NPO afresh: a kids profile made
    /// on a phone a minute ago should be found without signing in again.
    func refreshedModes() async throws -> Set<Mode> {
        Set(try await fetch().keys)
    }

    /// The profile to send for `mode`.
    func profile(for mode: Mode) async throws -> String {
        let marker = try authenticator.signInMarker()
        let remembered = known.withLock { $0?.marker == marker ? $0?.byMode : nil }
        let profiles: [Mode: String]
        if let remembered {
            profiles = remembered
        } else {
            profiles = try await fetch()
        }
        guard let profile = profiles[mode] else {
            // Normal mode without a general profile is not a state NPO has
            // ever shown; kids mode without a kids profile is an ordinary one.
            throw mode == .kids ? BackendError.kidsProfileMissing : BackendError.unexpectedResponse(status: nil)
        }
        return profile
    }

    /// The first general profile and the first kids profile, in NPO's order.
    private func fetch() async throws -> [Mode: String] {
        let marker = try authenticator.signInMarker()
        let profiles = try await authenticator.backendBody([ProfileBody].self,
                                                           from: BackendCall(path: NPOWire.profilesPath))
        var byMode: [Mode: String] = [:]
        byMode[.normal] = profiles.first { $0.type == ProfileBody.generalType }?.guid
        byMode[.kids] = profiles.first { $0.type == ProfileBody.kidsType }?.guid
        known.withLock { $0 = Known(marker: marker, byMode: byMode) }
        return byMode
    }
}

extension NPOAuthenticator {
    /// One GET to the app backend, decoded. A 404 is read as the item being
    /// gone, which is HTTP's meaning and has not been observed.
    nonisolated func backendBody<Body: Decodable>(_ type: Body.Type, from call: BackendCall) async throws -> Body {
        let response = try await backendResponse(to: call)
        switch response.status {
        case 200:
            do {
                return try JSONDecoder().decode(type, from: response.body)
            } catch {
                throw BackendError.unexpectedResponse(status: response.status)
            }
        case 404:
            throw BackendError.itemUnavailable
        default:
            throw BackendError.unexpectedResponse(status: response.status)
        }
    }
}
