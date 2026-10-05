//
//  RetryingTransport.swift
//  NPO light
//

import Foundation

/// An `HTTPTransport` that tries a request again when it failed in a way
/// that may pass by itself (NFR-REL-03, ADR 0026).
///
/// Only a request that asks and changes nothing is tried again. A request
/// that renews the session carries a token NPO accepts once: sent twice, the
/// second finds it spent and the session is dead (ADR 0007).
nonisolated struct RetryingTransport: HTTPTransport {
    /// How long to wait before each further attempt. Its length is how many
    /// further attempts there are.
    static let delays: [Duration] = [.milliseconds(500), .milliseconds(1500)]

    /// The answers that say NPO is having a moment, not that the request is
    /// wrong: a gateway that could not reach what is behind it.
    private static let passingStatuses: Set<Int> = [502, 503, 504]

    /// The failures that may be over a moment later. A request that timed
    /// out has had its wait already, and a television that knows it has no
    /// network gains nothing from asking twice more.
    private static let passingFailures: Set<URLError.Code> = [
        .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed
    ]

    private let wrapped: any HTTPTransport
    private let clock: any Clocking

    init(wrapping wrapped: any HTTPTransport, clock: any Clocking) {
        self.wrapped = wrapped
        self.clock = clock
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard request.httpMethod == nil || request.httpMethod == "GET" else {
            return try await wrapped.send(request)
        }
        for delay in Self.delays {
            if let response = try await attempt(request) { return response }
            try await clock.wait(for: delay)
        }
        // The last attempt's answer is the answer, whatever it is.
        return try await wrapped.send(request)
    }

    /// One attempt. `nil` when it failed in a way worth another.
    private func attempt(_ request: URLRequest) async throws -> HTTPResponse? {
        do {
            let response = try await wrapped.send(request)
            return Self.passingStatuses.contains(response.status) ? nil : response
        } catch let error as URLError where Self.passingFailures.contains(error.code) {
            // `URLSession` reports a cancelled task as a failed request.
            try Task.checkCancellation()
            return nil
        }
    }
}

/// How requests to NPO are sent: with a timeout, so that no screen waits for
/// ever on a backend that went quiet (NFR-REL-03).
nonisolated enum RequestPolicy {
    /// How long a request may stay unanswered before it fails.
    static let timeout: TimeInterval = 15

    /// Nothing is written to disk: no cache, no cookies and no credentials
    /// outside the Keychain (NFR-PRIV-02).
    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        return configuration
    }
}
