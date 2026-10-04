//
//  NPOWire.swift
//  NPO light
//

import Foundation

/// The hosts, paths and borrowed identifiers of NPO's private API.
///
/// None of it is documented or promised (ADR 0008), so it is kept in one place:
/// when NPO moves something, this is the file that changes.
nonisolated enum NPOWire {
    static let identityHost = "id.npo.nl"

    /// The app backend. There is no television host of its own: the tokens of
    /// the tvOS client are accepted by the one the iOS app uses (ADR 0007).
    static let backendHost = "ios.bff.start.npox.nl"

    static let playerHost = "prod.npoplayer.nl"

    /// What NPO's app asks the player host for, as captured. The `ster` block
    /// is the app's description of itself; the same stream comes back for the
    /// website's different one, and whether it may be left out was never
    /// tested.
    static let streamLinkBody = """
    {"profileName":"hls","drmType":"fairplay",\
    "ster":{"player":"app","deviceType":4,"os":"ios","osVersion":"26.6.1",\
    "identifier":"npo-app-ios","site":"npo"}}
    """

    static let deviceAuthorizationPath = "/connect/deviceauthorization"
    static let tokenPath = "/connect/token"
    static let accountPath = "/account"
    static let profilesPath = "/profiles"
    static let searchPath = "/search"

    static func seriesPath(_ series: ItemID) -> String {
        "/series/page/\(series.rawValue)"
    }

    static func playerPath(_ episode: EpisodeID) -> String {
        "/programs/player/\(episode.rawValue)"
    }

    static func episodesPath(_ season: SeasonID) -> String {
        "/series/seasons/\(season.rawValue)/programs"
    }

    /// NPO's own client for televisions, and the only one enrolled for the
    /// device-code grant. A borrowed identifier — ADR 0007 says so plainly.
    static let clientID = "npostart-app-tvos-prod"
    static let scope = "openid offline_access npo-id.org-npo"
    static let deviceCodeGrant = "urn:ietf:params:oauth:grant-type:device_code"

    /// Sent by NPO's app on every backend call, and by the proof-of-concept
    /// that reached playback. Whether the backend insists on it was never
    /// tested, so it is kept as captured rather than dropped on a guess.
    static let appDetails = "NPO Start 11.12.0(2026.0806.1533) on iOS 26.6.1"

    static let acceptLanguage = "nl-NL,nl;q=0.9"

    /// The only subscription type that counts as NPO Plus (FR-AUTH-08).
    static let plusSubscriptionType = "premium"

    static func url(host: String, path: String, query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw BackendError.unexpectedResponse(status: nil)
        }
        return url
    }

    /// A form POST to the identity provider, which takes no JSON.
    static func identityRequest(path: String, form: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: try url(host: identityHost, path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.httpBody = Data(formEncoded(form).utf8)
        return request
    }

    /// A GET to the app backend on behalf of `session`.
    static func backendRequest(_ call: BackendCall, session: Session) throws -> URLRequest {
        var request = URLRequest(url: try url(host: backendHost, path: call.path, query: call.query))
        if let profile = call.profile {
            // The whole of the catalogue switch: the same address answers with
            // a different catalogue for a different profile (ADR 0014).
            request.setValue(profile, forHTTPHeaderField: "profile-guid")
        }
        // The id token, not the access token: with the access token `/account`
        // answers 401 while `/profiles` answers 200 (ADR 0007).
        request.setValue("Bearer \(session.idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue(appDetails, forHTTPHeaderField: "App-Details")
        // Required but not authenticated: leaving it out is answered with 400.
        request.setValue(escaped(session.deviceIdentifier), forHTTPHeaderField: "party-id")
        return request
    }

    /// The exchange of a player token for a stream, on NPO's player host.
    static func streamLinkRequest(playerToken: String) throws -> URLRequest {
        var request = URLRequest(url: try url(host: playerHost, path: "/stream-link"))
        request.httpMethod = "POST"
        // The raw token. With a `Bearer` prefix the player host answers 403.
        request.setValue(playerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.httpBody = Data(streamLinkBody.utf8)
        return request
    }

    /// The licence exchange: the request the operating system made for a key,
    /// sent raw to NPO's licence gateway.
    ///
    /// NPO answers with one of two gateways. One is authorised by a header,
    /// and NPO's app adds the asset to its address. The other comes with the
    /// authorisation signed into the address, which is then sent exactly as
    /// given: adding to a signed address is a way to break it.
    static func licenceRequest(keyRequest: Data, assetID: String, protection: StreamProtection) -> URLRequest {
        var request = URLRequest(url: protection.licenceURL)
        if let credential = protection.credential {
            var components = URLComponents(url: protection.licenceURL, resolvingAgainstBaseURL: false)
            // What NPO's app sends. The gateway answers without it too.
            components?.queryItems = [URLQueryItem(name: "assetId", value: assetID)]
            request = URLRequest(url: components?.url ?? protection.licenceURL)
            request.setValue(credential, forHTTPHeaderField: "X-Custom-Data")
        }
        request.httpMethod = "POST"
        request.httpBody = keyRequest
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// A fresh `party-id`, in the shape NPO's app sends: `0:<8>:<32>`.
    static func makeDeviceIdentifier() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        func random(_ count: Int) -> String {
            String((0..<count).compactMap { _ in alphabet.randomElement() })
        }
        return "0:\(random(8)):\(random(32))"
    }

    private static func formEncoded(_ form: [String: String]) -> String {
        form.keys.sorted()
            .map { "\(escaped($0))=\(escaped(form[$0] ?? ""))" }
            .joined(separator: "&")
    }

    private static func escaped(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// One GET to the app backend.
nonisolated struct BackendCall: Sendable, Equatable {
    let path: String
    var query: [URLQueryItem] = []
    /// The NPO profile to ask as. Account-level calls carry none.
    var profile: String?
}

// MARK: - response bodies

/// `POST /connect/deviceauthorization`, answered with 200.
nonisolated struct DeviceAuthorizationBody: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let completeVerificationURL: URL
    let expiresIn: Int
    /// Optional in the grant's specification, which then prescribes five seconds.
    let interval: Int?

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_uri"
        case completeVerificationURL = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

/// `POST /connect/token`, answered with 200. Only the four fields that were
/// observed are read; see the fixtures' README.
nonisolated struct TokenBody: Decodable {
    let accessToken: String
    let idToken: String?
    let refreshToken: String?
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// The identity provider's way of saying no: a 400 with an `error` code, which
/// for a poll that is merely early is a normal state rather than a failure.
nonisolated struct OAuthErrorBody: Decodable {
    let error: String
}

/// `GET /account` on the app backend.
nonisolated struct AccountBody: Decodable {
    let guid: String
    let subscriptionType: String?
}
