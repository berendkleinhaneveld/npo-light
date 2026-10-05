//
//  LoggedBoundary.swift
//  NPO light
//

import Foundation

/// Runs one call across the NPO boundary and, when it fails, writes down which
/// call it was and why before the error goes on to become a sentence on a
/// screen (NFR-DIAG-01).
///
/// `operation` names the call and nothing it was given: a search term or a
/// title does not belong in a log that is always on.
nonisolated enum LoggedCall {
    static func run<Value>(_ operation: String,
                           in category: LogCategory,
                           log: any Logging,
                           _ call: () async throws -> Value) async throws -> Value {
        do {
            return try await call()
        } catch {
            record(error, from: operation, in: category, log: log)
            throw error
        }
    }

    static func record(_ error: any Error, from operation: String, in category: LogCategory, log: any Logging) {
        // A call that was called off — the screen went away — did not fail.
        guard !(error is CancellationError) else { return }
        log.record("\(operation) failed: \(ErrorDescription.of(error))", level: .error, category: category)
    }
}

/// An `Authenticating` that logs every failure of the one it wraps (ADR 0016).
nonisolated struct LoggedAuthenticator: Authenticating {
    private let wrapped: any Authenticating
    private let log: any Logging

    init(wrapping wrapped: any Authenticating, log: any Logging) {
        self.wrapped = wrapped
        self.log = log
    }

    func startSignIn() async throws -> DeviceCodeChallenge {
        try await LoggedCall.run("startSignIn", in: .session, log: log) {
            try await wrapped.startSignIn()
        }
    }

    func awaitApproval(of challenge: DeviceCodeChallenge) async throws -> Account {
        try await LoggedCall.run("awaitApproval", in: .session, log: log) {
            try await wrapped.awaitApproval(of: challenge)
        }
    }

    func restoredAccount() async throws -> Account? {
        try await LoggedCall.run("restoredAccount", in: .session, log: log) {
            try await wrapped.restoredAccount()
        }
    }

    func signOut() throws {
        do {
            try wrapped.signOut()
        } catch {
            LoggedCall.record(error, from: "signOut", in: .session, log: log)
            throw error
        }
    }
}

/// A `Catalogue` that logs every failure of the one it wraps (ADR 0016).
nonisolated struct LoggedCatalogue: Catalogue {
    private let wrapped: any Catalogue
    private let log: any Logging

    init(wrapping wrapped: any Catalogue, log: any Logging) {
        self.wrapped = wrapped
        self.log = log
    }

    func availableModes() async throws -> Set<Mode> {
        try await LoggedCall.run("availableModes", in: .catalogue, log: log) {
            try await wrapped.availableModes()
        }
    }

    func search(for query: String, in mode: Mode) async throws -> SearchResults {
        try await LoggedCall.run("search in \(mode)", in: .catalogue, log: log) {
            try await wrapped.search(for: query, in: mode)
        }
    }

    func series(_ id: ItemID, in mode: Mode) async throws -> SeriesDetail {
        try await LoggedCall.run("series \(id.rawValue) in \(mode)", in: .catalogue, log: log) {
            try await wrapped.series(id, in: mode)
        }
    }

    func episodes(of season: SeasonID, in mode: Mode) async throws -> [Playable] {
        try await LoggedCall.run("episodes of \(season.rawValue) in \(mode)", in: .catalogue, log: log) {
            try await wrapped.episodes(of: season, in: mode)
        }
    }

    func programme(_ id: EpisodeID, in mode: Mode) async throws -> ProgrammeDetail {
        try await LoggedCall.run("programme \(id.rawValue) in \(mode)", in: .catalogue, log: log) {
            try await wrapped.programme(id, in: mode)
        }
    }

    func place(of episode: EpisodeID, in mode: Mode) async throws -> SeriesPlace? {
        try await LoggedCall.run("place of \(episode.rawValue) in \(mode)", in: .catalogue, log: log) {
            try await wrapped.place(of: episode, in: mode)
        }
    }
}
