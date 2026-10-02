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

    static let deviceAuthorizationPath = "/connect/deviceauthorization"
    static let tokenPath = "/connect/token"
    static let accountPath = "/account"

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

    static func url(host: String, path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
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
    static func backendRequest(path: String, session: Session) throws -> URLRequest {
        var request = URLRequest(url: try url(host: backendHost, path: path))
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
