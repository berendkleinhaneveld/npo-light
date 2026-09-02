//
//  HTTPTransport.swift
//  NPO light
//

import Foundation

/// One HTTP request out, one response back.
///
/// This is the seam underneath the NPO boundary (ADR 0008) and the point where
/// tests substitute canned bytes for a network (ADR 0009). `URLSession` is
/// deliberately not the seam itself: stubbing it means registering a
/// `URLProtocol` subclass, which is process-global mutable state and does not
/// survive Swift Testing running its suites in parallel.
nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// What came back.
///
/// A value type rather than `HTTPURLResponse`, whose initialiser is failable —
/// building one in a test would need a force unwrap, and `force_unwrapping` is
/// enforced in test code too.
nonisolated struct HTTPResponse: Sendable, Equatable {
    let status: Int
    /// Header names lowercased, because HTTP header names are case-insensitive
    /// and a caller should not have to guess how NPO capitalised one.
    let headers: [String: String]
    let body: Data

    init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}
