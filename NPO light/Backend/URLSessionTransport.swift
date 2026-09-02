//
//  URLSessionTransport.swift
//  NPO light
//

import Foundation

/// The production `HTTPTransport`.
///
/// Deliberately thin: it converts, it does not decide. Timeouts and the retry
/// policy belong to the session it is given, which keeps them assertable as
/// configuration rather than as behaviour hidden in here.
nonisolated struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.unexpectedResponse(status: nil)
        }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            headers[name.lowercased()] = value
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: body)
    }
}
