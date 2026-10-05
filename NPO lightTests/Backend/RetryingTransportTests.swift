//
//  RetryingTransportTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// Trying again, and knowing when not to (NFR-REL-03).
struct RetryingTransportTests {
    private static let address = URL(filePath: "/series")

    private static func request(_ method: String = "GET") -> URLRequest {
        var request = URLRequest(url: address)
        request.httpMethod = method
        return request
    }

    /// A transport that answers with each outcome in turn, and a clock that
    /// writes down how long it was asked to wait.
    private struct Rig {
        let stub: StubTransport
        let clock = TestClock()
        let transport: RetryingTransport

        init(_ outcomes: [Result<HTTPResponse, URLError>]) {
            let attempts = Counter()
            let stub = StubTransport { _ in
                let index = attempts.increment() - 1
                return try outcomes[min(index, outcomes.count - 1)].get()
            }
            self.stub = stub
            transport = RetryingTransport(wrapping: stub, clock: clock)
        }
    }

    private static let lost = Result<HTTPResponse, URLError>.failure(URLError(.networkConnectionLost))
    private static let fine = Result<HTTPResponse, URLError>.success(HTTPResponse(status: 200))

    @Test("NFR-REL-03: a request that failed in passing is tried again, after a wait")
    func passingFailureIsRetried() async throws {
        let rig = Rig([Self.lost, Self.fine])

        let response = try await rig.transport.send(Self.request())

        #expect(response.status == 200)
        #expect(rig.stub.sent.count == 2)
        #expect(rig.clock.waits == [RetryingTransport.delays[0]])
    }

    @Test("NFR-REL-03: each further attempt waits longer, and there is a last one")
    func attemptsAreBounded() async {
        let rig = Rig([Self.lost])

        await #expect(throws: URLError.self) {
            _ = try await rig.transport.send(Self.request())
        }

        #expect(rig.stub.sent.count == RetryingTransport.delays.count + 1)
        #expect(rig.clock.waits == RetryingTransport.delays)
        #expect(zip(rig.clock.waits, rig.clock.waits.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("NFR-REL-03: a gateway that could not reach NPO is asked again", arguments: [502, 503, 504])
    func gatewayErrorIsRetried(status: Int) async throws {
        let rig = Rig([.success(HTTPResponse(status: status)), Self.fine])

        let response = try await rig.transport.send(Self.request())

        #expect(response.status == 200)
        #expect(rig.stub.sent.count == 2)
    }

    @Test("NFR-REL-03: a gateway that stays down answers in the end, instead of throwing")
    func lastAnswerIsHandedOn() async throws {
        let rig = Rig([.success(HTTPResponse(status: 503))])

        let response = try await rig.transport.send(Self.request())

        #expect(response.status == 503)
    }

    @Test("NFR-REL-03: an answer that says the request is wrong is not asked for again",
          arguments: [400, 401, 403, 404, 500])
    func refusalIsNotRetried(status: Int) async throws {
        let rig = Rig([.success(HTTPResponse(status: status))])

        let response = try await rig.transport.send(Self.request())

        #expect(response.status == status)
        #expect(rig.stub.sent.count == 1)
        #expect(rig.clock.waits.isEmpty)
    }

    @Test("NFR-REL-03: a request that timed out, or has no network to go over, is not sent again",
          arguments: [URLError.Code.timedOut, .notConnectedToInternet])
    func lastingFailureIsNotRetried(code: URLError.Code) async {
        let rig = Rig([.failure(URLError(code))])

        await #expect(throws: URLError.self) {
            _ = try await rig.transport.send(Self.request())
        }

        #expect(rig.stub.sent.count == 1)
    }

    @Test("NFR-REL-03, FR-AUTH-07: a request that changes something is sent once, so a token is never spent twice")
    func postIsSentOnce() async {
        let rig = Rig([Self.lost, Self.fine])

        await #expect(throws: URLError.self) {
            _ = try await rig.transport.send(Self.request("POST"))
        }

        #expect(rig.stub.sent.count == 1)
    }

    @Test("NFR-REL-03: a request to NPO has a timeout, so it fails rather than hangs")
    func requestsTimeOut() {
        let configuration = RequestPolicy.configuration

        #expect(configuration.timeoutIntervalForRequest == RequestPolicy.timeout)
        #expect(RequestPolicy.timeout > 0)
        #expect(RequestPolicy.timeout < 60)
    }
}
