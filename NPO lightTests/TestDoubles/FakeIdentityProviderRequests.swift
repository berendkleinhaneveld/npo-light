//
//  FakeIdentityProviderRequests.swift
//  NPO lightTests
//

import Foundation
@testable import NPO_light

/// Hand-built calls to ``FakeIdentityProvider``, so that the tests of the
/// double itself read as the conversation they are checking.
///
/// The real client builds its own requests; these exist only to exercise the
/// fake, and a test of the client goes through the client instead.
extension FakeIdentityProvider {
    private static let deviceCodeGrant = "urn:ietf:params:oauth:grant-type:device_code"
    private static let clientID = "npostart-app-tvos-prod"

    /// Starts a sign-in and answers with the device code to poll with.
    func startedDeviceCode() async throws -> String {
        let response = try await send(try Self.request(path: "/connect/deviceauthorization", form: [
            "client_id": Self.clientID,
            "scope": "openid offline_access npo-id.org-npo"
        ]))
        return try field("device_code", in: response)
    }

    /// One poll of the token endpoint for the device-code grant.
    func poll(deviceCode: String) async throws -> HTTPResponse {
        try await send(try Self.request(path: "/connect/token", form: [
            "grant_type": Self.deviceCodeGrant,
            "device_code": deviceCode,
            "client_id": Self.clientID
        ]))
    }

    /// One refresh exchange.
    func refresh(refreshToken: String) async throws -> HTTPResponse {
        try await send(try Self.request(path: "/connect/token", form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID
        ]))
    }

    static func request(path: String, form: [String: String]) throws -> URLRequest {
        guard let url = URL(string: "https://id.npo.nl" + path) else {
            throw TestRequestError.malformedPath(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(form).utf8)
        return request
    }

    private static func formEncoded(_ form: [String: String]) -> String {
        form.keys.sorted()
            .map { "\(escaped($0))=\(escaped(form[$0] ?? ""))" }
            .joined(separator: "&")
    }

    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}

enum TestRequestError: Error, Equatable {
    case malformedPath(String)
    case notAJSONObject
    case missingField(String)
}

/// The JSON object in a response body.
func jsonObject(in response: HTTPResponse) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: response.body)
    guard let dictionary = object as? [String: Any] else {
        throw TestRequestError.notAJSONObject
    }
    return dictionary
}

/// One string field out of a response body.
func field(_ name: String, in response: HTTPResponse) throws -> String {
    guard let value = try jsonObject(in: response)[name] as? String else {
        throw TestRequestError.missingField(name)
    }
    return value
}

/// The OAuth `error` code the identity provider answered with.
func oauthError(in response: HTTPResponse) throws -> String {
    try field("error", in: response)
}
