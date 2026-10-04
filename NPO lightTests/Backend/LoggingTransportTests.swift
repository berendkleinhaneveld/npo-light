//
//  LoggingTransportTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

struct LoggingTransportTests {
    private static let answer = HTTPResponse(status: 200,
                                             headers: ["set-cookie": "session=secret-cookie"],
                                             body: Data(#"{"access_token":"secret-token"}"#.utf8))

    /// A search as the app backend is asked for one, with a credential in a
    /// header and another in the body.
    private static func request() throws -> URLRequest {
        let url = try NPOWire.url(host: NPOWire.backendHost,
                                  path: NPOWire.searchPath,
                                  query: [URLQueryItem(name: "query", value: "freek")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer secret-bearer", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("refresh_token=secret-refresh".utf8)
        return request
    }

    private static func transport(_ detail: HTTPLogDetail,
                                  log: RecordingLog,
                                  archive: HTTPLogArchive? = nil,
                                  respond: @escaping @Sendable (URLRequest) async throws -> HTTPResponse = { _ in
                                      LoggingTransportTests.answer
                                  }) -> LoggingTransport {
        LoggingTransport(wrapping: StubTransport(respond: respond),
                         detail: detail,
                         log: log,
                         archive: archive,
                         clock: TestClock())
    }

    /// An archive in a directory of its own, so that parallel tests and
    /// repeated runs do not read each other's files.
    private static func archive() -> HTTPLogArchive {
        HTTPLogArchive(directory: FileManager.default.temporaryDirectory
            .appending(path: "http-log-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    private static func names(in archive: HTTPLogArchive) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: archive.directory.path()).sorted()
    }

    private static func document(_ name: String, in archive: HTTPLogArchive) throws -> NSDictionary {
        let data = try Data(contentsOf: archive.directory.appending(path: name))
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test("NFR-DIAG-02: the launch environment picks how much of each request is logged", arguments: [
        (nil, HTTPLogDetail.off),
        ("off", HTTPLogDetail.off),
        ("summary", HTTPLogDetail.summary),
        ("full", HTTPLogDetail.full),
        ("everything", HTTPLogDetail.off)
    ])
    func environmentPicksTheDetail(value: String?, expected: HTTPLogDetail) {
        var environment: [String: String] = [:]
        environment[HTTPLogDetail.environmentKey] = value

        #expect(HTTPLogDetail(environment: environment, allowsFull: true) == expected)
    }

    @Test("NFR-DIAG-03, NFR-PRIV-02: a build that may not log credentials gives a summary when asked for all of it")
    func fullIsRefusedOutsideDebug() {
        let environment = [HTTPLogDetail.environmentKey: "full"]

        #expect(HTTPLogDetail(environment: environment, allowsFull: false) == .summary)
    }

    @Test("NFR-DIAG-02: with logging off a request passes through untouched and unrecorded")
    func offLogsNothing() async throws {
        let log = RecordingLog()
        let archive = Self.archive()
        let stub = StubTransport { _ in Self.answer }
        let transport = LoggingTransport(wrapping: stub, detail: .off, log: log, archive: archive, clock: TestClock())
        let request = try Self.request()

        let response = try await transport.send(request)

        #expect(response == Self.answer)
        #expect(stub.sent == [request])
        #expect(log.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: archive.directory.path()))
    }

    @Test("NFR-DIAG-02, NFR-PRIV-02: a summary is one line, with no header and no body in it, and no file")
    func summaryIsOneLine() async throws {
        let log = RecordingLog()
        let archive = Self.archive()
        let clock = TestClock()
        let stub = StubTransport { _ in
            try await clock.wait(for: .milliseconds(87))
            return Self.answer
        }
        let transport = LoggingTransport(wrapping: stub, detail: .summary, log: log, archive: archive, clock: clock)

        _ = try await transport.send(try Self.request())

        let size = Self.answer.body.count
        #expect(log.entries == [
            RecordingLog.Entry(
                message: "POST https://ios.bff.start.npox.nl/search?query → 200, \(size) bytes, 87 ms",
                level: .info,
                category: .http
            )
        ])
        #expect(!FileManager.default.fileExists(atPath: archive.directory.path()))
    }

    @Test("NFR-DIAG-02, NFR-PRIV-02: an address that carries its own authorisation is logged without it")
    func signedAddressesAreLoggedBare() async throws {
        let log = RecordingLog()
        let signed = "https://drm.npoplayer.nl/proxyEngine.aspx?auth=secret-auth&sig=secret-sig"
        let address = try #require(URL(string: signed))

        _ = try await Self.transport(.full, log: log, archive: Self.archive()).send(URLRequest(url: address))

        let line = try #require(log.messages.first)
        #expect(line.hasPrefix("GET https://drm.npoplayer.nl/proxyEngine.aspx?auth&sig → 200, "))
        #expect(!line.contains("secret"))
    }

    @Test("NFR-DIAG-03: kept in full, both directions are in a file whole, credentials and all")
    func fullKeepsEverything() async throws {
        let log = RecordingLog()
        let archive = Self.archive()

        _ = try await Self.transport(.full, log: log, archive: archive).send(try Self.request())

        let name = try #require(try Self.names(in: archive).first)
        #expect(name == "1970-01-01T000000.000Z-0001-POST-search-200.json")
        #expect(log.messages.count == 1)
        #expect(log.messages.first?.hasSuffix("0 ms — \(name)") == true)

        let document = try Self.document(name, in: archive)
        let expected: NSDictionary = [
            "started": "1970-01-01T00:00:00.000Z",
            "elapsedMilliseconds": 0,
            "request": [
                "method": "POST",
                "url": "https://ios.bff.start.npox.nl/search?query=freek",
                "headers": ["Authorization": "Bearer secret-bearer"],
                "body": "refresh_token=secret-refresh"
            ],
            "response": [
                "status": 200,
                "headers": ["set-cookie": "session=secret-cookie"],
                "body": ["access_token": "secret-token"]
            ]
        ]
        #expect(document == expected)
    }

    @Test("NFR-DIAG-03: a body that is not text is kept as base64, and each exchange has a file of its own")
    func binaryBodiesAreKept() async throws {
        let archive = Self.archive()
        let licence = HTTPResponse(status: 200, body: Data([0xFF, 0xFE, 0xFD]))
        let transport = Self.transport(.full, log: RecordingLog(), archive: archive) { _ in licence }

        _ = try await transport.send(try Self.request())
        _ = try await transport.send(try Self.request())

        let names = try Self.names(in: archive)
        #expect(names.count == 2)
        let response = try #require(try Self.document(names[1], in: archive)["response"] as? NSDictionary)
        #expect(response["body"] as? NSDictionary == ["base64": "//79"])
    }

    @Test("NFR-DIAG-03: a request that got no answer is kept too, with why")
    func lostRequestsAreKept() async throws {
        let archive = Self.archive()
        let transport = Self.transport(.full, log: RecordingLog(), archive: archive) { _ in
            throw URLError(.timedOut)
        }

        await #expect(throws: URLError.self) {
            _ = try await transport.send(try Self.request())
        }

        let name = try #require(try Self.names(in: archive).first)
        #expect(name.hasSuffix("-POST-search-failed.json"))
        let reason = try #require(try Self.document(name, in: archive)["error"] as? String)
        #expect(reason.hasPrefix("NSURLErrorDomain -1001"))
    }

    @Test("NFR-DIAG-03: tidying leaves the newest files and removes the rest")
    func tidyingKeepsTheNewest() async throws {
        let archive = Self.archive()
        let transport = Self.transport(.full, log: RecordingLog(), archive: archive)
        for _ in 1...3 {
            _ = try await transport.send(try Self.request())
        }
        let before = try Self.names(in: archive)

        try archive.tidy(keeping: 2)

        #expect(try Self.names(in: archive) == Array(before.suffix(2)))
    }

    @Test("NFR-DIAG-01: a request that got no answer is logged with its cause, and without what was searched for")
    func lostRequestsAreAlwaysLogged() async throws {
        let log = RecordingLog()
        let transport = Self.transport(.off, log: log) { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: URLError.self) {
            _ = try await transport.send(try Self.request())
        }

        let entry = try #require(log.entries.first)
        #expect(log.entries.count == 1)
        #expect(entry.level == .error)
        #expect(entry.category == .http)
        #expect(entry.message.hasPrefix("POST ios.bff.start.npox.nl/search failed: NSURLErrorDomain -1009"))
        #expect(!entry.message.contains("freek"))
        #expect(!entry.message.contains("secret"))
    }

    @Test("NFR-DIAG-01: a request that was called off is not logged as a failure")
    func cancellationIsQuiet() async throws {
        let log = RecordingLog()
        let transport = Self.transport(.off, log: log) { _ in throw CancellationError() }

        await #expect(throws: CancellationError.self) {
            _ = try await transport.send(try Self.request())
        }

        #expect(log.entries.isEmpty)
    }
}
