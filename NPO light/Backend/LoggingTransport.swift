//
//  LoggingTransport.swift
//  NPO light
//

import Foundation

/// How much of each request to NPO is kept (NFR-DIAG-02).
nonisolated enum HTTPLogDetail: String, Sendable, Equatable {
    /// Only a request that got no answer at all.
    case off

    /// One line per request: what was asked, the status, the size, the time.
    case summary

    /// The summary, and both directions whole in a file of their own:
    /// headers and bodies, credentials included. Debug builds only
    /// (NFR-DIAG-03).
    case full

    /// The environment variable that picks one, set in the Xcode scheme.
    static let environmentKey = "NPO_LIGHT_HTTP_LOG"

    /// What this launch asks for. Nothing, or a value nobody defined, is
    /// `off`; and `full` is only honoured where `allowsFull` says it may be,
    /// which a release build never does.
    init(environment: [String: String], allowsFull: Bool) {
        let asked = environment[Self.environmentKey].flatMap(Self.init(rawValue:)) ?? .off
        self = asked == .full && !allowsFull ? .summary : asked
    }
}

/// An `HTTPTransport` that keeps a record of what passes through it, and
/// changes none of it (ADR 0016).
///
/// It sits at the seam every request to NPO already goes through (ADR 0009),
/// so no caller knows it is there. The video itself does not pass here: the
/// system player fetches that on its own.
nonisolated struct LoggingTransport: HTTPTransport {
    private let wrapped: any HTTPTransport
    private let detail: HTTPLogDetail
    private let log: any Logging
    private let archive: HTTPLogArchive?
    private let clock: any Clocking

    /// `archive` is where `full` keeps its files. Without one, `full` is a
    /// summary.
    init(wrapping wrapped: any HTTPTransport,
         detail: HTTPLogDetail,
         log: any Logging,
         archive: HTTPLogArchive?,
         clock: any Clocking) {
        self.wrapped = wrapped
        self.detail = detail
        self.log = log
        self.archive = archive
        self.clock = clock
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let started = clock.now
        do {
            let response = try await wrapped.send(request)
            keep(HTTPExchange(request: request,
                              outcome: .answered(response),
                              started: started,
                              elapsed: clock.now.timeIntervalSince(started)))
            return response
        } catch {
            // A request that was called off is not a failure, and `URLSession`
            // reports one as an error of its own.
            if !(error is CancellationError), !Task.isCancelled {
                keep(HTTPExchange(request: request,
                                  outcome: .lost(ErrorDescription.of(error)),
                                  started: started,
                                  elapsed: clock.now.timeIntervalSince(started)))
            }
            throw error
        }
    }

    private func keep(_ exchange: HTTPExchange) {
        var line: String
        let level: LogLevel
        switch exchange.outcome {
        case .answered:
            guard detail != .off else { return }
            line = exchange.summary
            level = .info
        case .lost:
            // Written whatever the setting (NFR-DIAG-01).
            line = exchange.failure
            level = .error
        }
        if detail == .full, let archive {
            do {
                line += " — \(try archive.keep(exchange))"
            } catch {
                line += " — not kept: \(ErrorDescription.of(error))"
            }
        }
        log.record(line, level: level, category: .http)
    }
}

/// One request and what became of it.
nonisolated struct HTTPExchange: Sendable {
    enum Outcome: Sendable {
        case answered(HTTPResponse)

        /// No answer at all, and why.
        case lost(String)
    }

    let request: URLRequest
    let outcome: Outcome
    let started: Date
    let elapsed: TimeInterval

    /// One line for a request that was answered. It is written to the system
    /// log, so it carries nothing from a header, a body or a query value.
    var summary: String {
        guard case .answered(let response) = outcome else { return failure }
        return "\(method) \(address) → \(response.status), "
            + "\(response.body.count) bytes, \(milliseconds) ms"
    }

    /// One line for a request that got no answer. Always written, so it
    /// carries the host and the path and not the query: a search term is in
    /// there (NFR-DIAG-01).
    var failure: String {
        guard case .lost(let reason) = outcome else { return summary }
        return "\(method) \(request.url?.host() ?? "?")\(request.url?.path() ?? "") failed: \(reason)"
    }

    /// The whole exchange as a JSON document a person can read: a body that
    /// is JSON is nested as it is, one that is other text is a string, and
    /// one that is not text — a key request, a licence — is base64.
    func document() throws -> Data {
        var document: [String: Any] = [
            "started": started.formatted(Self.timestamp),
            "elapsedMilliseconds": milliseconds,
            "request": [
                "method": method,
                "url": request.url?.absoluteString ?? "",
                "headers": request.allHTTPHeaderFields ?? [:],
                "body": Self.readable(request.httpBody ?? Data())
            ]
        ]
        switch outcome {
        case .answered(let response):
            document["response"] = [
                "status": response.status,
                "headers": response.headers,
                "body": Self.readable(response.body)
            ]
        case .lost(let reason):
            document["error"] = reason
        }
        return try JSONSerialization.data(withJSONObject: document,
                                          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// A name that sorts by time and says what the file holds:
    /// `<when>-<number>-<method>-<end of the path>-<status>.json`.
    func fileName(numbered number: Int) -> String {
        let when = started.formatted(Self.timestamp).replacingOccurrences(of: ":", with: "")
        let subject = request.url?.lastPathComponent.filter { $0.isLetter || $0.isNumber || $0 == "-" } ?? ""
        let ending: String
        switch outcome {
        case .answered(let response): ending = String(response.status)
        case .lost: ending = "failed"
        }
        let padded = String(repeating: "0", count: max(0, 4 - String(number).count)) + String(number)
        return "\(when)-\(padded)-\(method)-\(subject)-\(ending).json"
    }

    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// The address for a log line: with the names of what was asked and not
    /// the values. NPO signs a licence address by putting the authorisation in
    /// its query, and a line in the system log is no place for that.
    private var address: String {
        guard let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "?" }
        let names = components.queryItems?.map(\.name) ?? []
        components.query = nil
        let bare = components.string ?? "?"
        return names.isEmpty ? bare : "\(bare)?\(names.joined(separator: "&"))"
    }

    private var method: String {
        request.httpMethod ?? "GET"
    }

    private var milliseconds: Int {
        Int((elapsed * 1000).rounded())
    }

    private static func readable(_ body: Data) -> Any {
        if body.isEmpty {
            return ""
        }
        if let json = try? JSONSerialization.jsonObject(with: body) {
            return json
        }
        if let text = String(data: body, encoding: .utf8) {
            return text
        }
        return ["base64": body.base64EncodedString()]
    }
}
