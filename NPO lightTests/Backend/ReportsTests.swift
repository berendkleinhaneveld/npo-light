//
//  ReportsTests.swift
//  NPO lightTests
//

import Foundation
import Testing
@testable import NPO_light

/// The reports of playback, held to what NPO's own app was seen to send and
/// to what NPO was seen to take (Q-13, ADR 0028).
struct ReportsTests {
    private static let episode = EpisodeID(rawValue: "7c41b9e2-4bee-4003-8450-a59bee7c6830")
    private static let host = "topspin.npo.nl"

    private struct Setup {
        let reports: NPOReports
        let harness: SignInHarness
        let products: NPOProducts

        /// What went to NPO's reports host, oldest first.
        var sent: [URLRequest] {
            harness.transport.sent.filter { $0.url?.host == ReportsTests.host }
        }

        /// The body of the report at `index`, as NPO reads it.
        func body(_ index: Int = 0) throws -> [String: Any] {
            let data = try #require(sent[index].httpBody)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        func part(_ name: String, of index: Int = 0) throws -> [String: Any] {
            let parameters = try #require(try body(index)["parameters"] as? [String: Any])
            return try #require(parameters[name] as? [String: Any])
        }
    }

    private static func setup(taking status: Int = 204) async throws -> Setup {
        let profiles = try Fixture.data("profiles-200")
        let player = try Fixture.data("player-progress-200")
        let harness = SignInHarness(backend: { request in
            switch (request.url?.host, request.url?.path) {
            case (Self.host, _): HTTPResponse(status: status)
            case (_, "/profiles"): HTTPResponse(status: 200, body: profiles)
            case (_, "/account"): .json(SignInHarness.premiumAccount)
            default: HTTPResponse(status: 200, body: player)
            }
        })
        try await harness.signIn()
        let products = NPOProducts()
        let reports = NPOReports(authenticator: harness.authenticator,
                                 profiles: NPOProfiles(authenticator: harness.authenticator),
                                 products: products,
                                 transport: harness.transport,
                                 clock: harness.clock)
        return Setup(reports: reports, harness: harness, products: products)
    }

    private static func event(_ kind: PlaybackEvent.Kind, at position: TimeInterval = 90) -> PlaybackEvent {
        PlaybackEvent(kind: kind, episode: episode, position: position, duration: 2886.159)
    }

    @Test("FR-PLAY-12: a report goes to NPO's own reports host, as one event, with no credential on it")
    func reportIsPostedToNPO() async throws {
        let setup = try await Self.setup()

        try await setup.reports.report(Self.event(.waypoint), in: .normal)

        let request = try #require(setup.sent.first)
        #expect(setup.sent.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/mob-event")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // Nothing authorises a report. The token stays where it is needed.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let device = try setup.harness.authenticator.signInMarker()
        #expect(request.url?.query()?.removingPercentEncoding == "p=\(device)")
        #expect(try setup.body()["party_id"] as? String == device)
        #expect(try setup.body()["event_type"] as? String == "streamWaypoint")
    }

    @Test("FR-PLAY-12: a report names the programme as NPO names it, the position and the length")
    func reportCarriesThePosition() async throws {
        let setup = try await Self.setup()

        try await setup.reports.report(Self.event(.paused, at: 123.5), in: .normal)

        let stream = try setup.part("stream")
        #expect(stream["id"] as? String == "AT_300024566")
        #expect(stream["position"] as? Double == 123.5)
        #expect(stream["length"] as? Double == 2886.159)
        #expect(stream["isLiveStream"] as? Bool == false)
        #expect(stream["seekFrom"] == nil)
    }

    @Test("FR-PLAY-12, FR-MODE-05: a report names the account and the NPO profile of the mode it was played in")
    func reportNamesTheModesProfile() async throws {
        let setup = try await Self.setup()

        try await setup.reports.report(Self.event(.started), in: .normal)
        try await setup.reports.report(Self.event(.started), in: .kids)

        #expect(try setup.part("npo", of: 0)["userId"] as? String == "account-1")
        #expect(try setup.part("npo", of: 0)["profileId"] as? String == "00000000-0000-0000-0000-000000000011")
        #expect(try setup.part("npo", of: 1)["profileId"] as? String == "00000000-0000-0000-0000-000000000012")
        #expect(try setup.part("npo", of: 0)["subscription"] as? String == "premium")
        // The account is asked for once, not for every report.
        #expect(setup.harness.backendRequests.filter { $0.url?.path == "/account" }.count == 2)
    }

    @Test("FR-PLAY-12, NFR-PRIV-01: a report says what NPO refuses one without, and nothing about a page or a screen")
    func reportSaysNoMoreThanNeeded() async throws {
        let setup = try await Self.setup()

        try await setup.reports.report(Self.event(.waypoint), in: .normal)

        let parameters = try #require(try setup.body()["parameters"] as? [String: Any])
        #expect(Set(parameters.keys) == ["npo", "topspin", "stream"])
        // The two fields NPO was seen to refuse a report without.
        #expect(try setup.part("topspin")["brand"] as? String == "npostart")
        #expect(try setup.part("topspin")["platformType"] as? String == "app")
        #expect(try setup.part("topspin")["chapters"] == nil)
        #expect(try setup.part("stream")["mediaUrl"] == nil)
    }

    @Test("FR-PLAY-12: each thing the player does goes by the name NPO's player gives it", arguments: [
        (PlaybackEvent.Kind.loaded, "streamLoadComplete"),
        (.started, "streamStart"),
        (.waypoint, "streamWaypoint"),
        (.paused, "streamPause"),
        (.resumed, "streamResume"),
        (.sought(from: 10), "streamSeek"),
        (.completed, "streamComplete"),
        (.stopped, "streamStop")
    ])
    func eventsAreNamedAsNPONamesThem(kind: PlaybackEvent.Kind, name: String) {
        #expect(ReportBody.name(of: kind) == name)
    }

    @Test("FR-PLAY-12: moving to another point says where from")
    func seekSaysWhereFrom() async throws {
        let setup = try await Self.setup()

        try await setup.reports.report(Self.event(.sought(from: 100), at: 2600), in: .normal)

        #expect(try setup.part("stream")["seekFrom"] as? Double == 100)
        #expect(try setup.part("stream")["position"] as? Double == 2600)
    }

    @Test("FR-PLAY-12: every report is an event of its own in one sitting, and only the first opens it")
    func reportsShareOneSitting() async throws {
        let setup = try await Self.setup()

        try await setup.reports.report(Self.event(.started), in: .normal)
        try await setup.reports.report(Self.event(.waypoint), in: .normal)

        #expect(try setup.body(0)["session_id"] as? String == setup.body(1)["session_id"] as? String)
        #expect(try setup.body(0)["event_id"] as? String != setup.body(1)["event_id"] as? String)
        #expect(try setup.body(0)["is_new_session"] as? Bool == true)
        #expect(try setup.body(1)["is_new_session"] as? Bool == false)
        // The time it happened, to the millisecond, as NPO's app writes it.
        let stamp = try #require(try setup.body(0)["client_timestamp_iso"] as? String)
        #expect(stamp.wholeMatch(of: /\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z/) != nil)
    }

    @Test("FR-PLAY-12: NPO's name for a programme that was not asked to play here is asked of NPO, once")
    func productIsAskedForOnce() async throws {
        let setup = try await Self.setup()
        let path = "/programs/player/\(Self.episode.rawValue)"

        try await setup.reports.report(Self.event(.started), in: .normal)
        try await setup.reports.report(Self.event(.waypoint), in: .normal)

        #expect(setup.harness.backendRequests.filter { $0.url?.path == path }.count == 1)
        #expect(setup.products.product(for: Self.episode) == "AT_300024566")
    }

    @Test("FR-PLAY-12: a programme whose stream was asked for needs no question about its name")
    func knownProductIsNotAskedFor() async throws {
        let setup = try await Self.setup()
        setup.products.note("KN_1736788", for: Self.episode)

        try await setup.reports.report(Self.event(.started), in: .normal)

        #expect(try setup.part("stream")["id"] as? String == "KN_1736788")
        #expect(!setup.harness.backendRequests.contains { $0.url?.path.hasPrefix("/programs/player") == true })
    }

    @Test("FR-PLAY-12: a report NPO refuses is an error for whoever sent it, to be written down")
    func refusedReportThrows() async throws {
        let setup = try await Self.setup(taking: 406)

        await #expect(throws: BackendError.unexpectedResponse(status: 406)) {
            try await setup.reports.report(Self.event(.waypoint), in: .normal)
        }
    }

    @Test("FR-PLAY-12: the account is named as its token names it, when the token does")
    func subjectIsReadFromTheToken() {
        // {"sub":"3c0fbcc0-0c9e","iss":"https://id.npo.nl"}, as the middle of a token.
        let claims = Data(#"{"sub":"3c0fbcc0-0c9e","iss":"https://id.npo.nl"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        #expect(NPOWire.subject(of: "header.\(claims).signature") == "3c0fbcc0-0c9e")
        #expect(NPOWire.subject(of: "id-token-1") == nil)
        #expect(NPOWire.subject(of: "a.not-base64!.c") == nil)
    }

    @Test("NFR-DIAG-01: a report NPO did not take is logged where it left the boundary, without what it said")
    func failedReportIsLogged() async {
        let log = RecordingLog()
        let reports = LoggedReports(wrapping: RecordingReports(failingWith: .unreachable), log: log)

        await #expect(throws: BackendError.unreachable) {
            try await reports.report(Self.event(.waypoint), in: .kids)
        }

        #expect(log.entries.count == 1)
        #expect(log.entries.first?.message.contains(Self.episode.rawValue) == true)
        #expect(log.entries.first?.category == .playback)
    }
}
