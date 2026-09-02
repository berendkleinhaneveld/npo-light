//
//  StubTransport.swift
//  NPO lightTests
//

import Foundation
import Synchronization
@testable import NPO_light

/// An `HTTPTransport` that answers from a closure and remembers what it was
/// asked (ADR 0009).
///
/// There is no configuration API on purpose. A closure already expresses every
/// case a test can want — a fixed body, a sequence, a wait on the injected
/// clock, a throw, a call that never returns — without a vocabulary to learn,
/// and it keeps the interesting behaviour written where the test can see it.
nonisolated final class StubTransport: HTTPTransport {
    private let respond: @Sendable (URLRequest) async throws -> HTTPResponse
    private let received = Mutex<[URLRequest]>([])

    init(respond: @escaping @Sendable (URLRequest) async throws -> HTTPResponse) {
        self.respond = respond
    }

    /// Every request sent so far, oldest first. The outgoing request is half of
    /// what has to be checked at this seam: NPO's player host wants a raw JWT
    /// without the `Bearer` prefix that would make it fail (ADR 0008).
    var sent: [URLRequest] { received.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        received.withLock { $0.append(request) }
        return try await respond(request)
    }
}

extension HTTPResponse {
    /// A JSON body, in the shape NPO's hosts answer with.
    static func json(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["content-type": "application/json; charset=UTF-8"],
                     body: Data(body.utf8))
    }
}
