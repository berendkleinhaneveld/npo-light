//
//  LoggedPlayback.swift
//  NPO light
//

import AVFoundation
import Foundation

/// A `PlaybackStarting` that logs a playback that would not start, and then
/// keeps listening to the one that did (NFR-DIAG-01, NFR-DIAG-04).
///
/// The video is fetched by the system player and never passes the transport,
/// so what the player says about itself is the only account there is of a
/// manifest that would not load or a licence that was refused.
@MainActor
final class LoggedPlayback: PlaybackStarting {
    private let wrapped: any PlaybackStarting
    private let log: any Logging

    init(wrapping wrapped: any PlaybackStarting, log: any Logging) {
        self.wrapped = wrapped
        self.log = log
    }

    func playback(of playable: Playable, in mode: Mode) async throws -> Playback {
        let subject = "playback of \(playable.id.rawValue) in \(mode)"
        let playback = try await LoggedCall.run(subject, in: .playback, log: log) {
            try await wrapped.playback(of: playable, in: mode)
        }
        guard let item = playback.player.currentItem else { return playback }
        let watch = PlaybackWatch(item: item, subject: subject, log: log, keeping: playback.keys)
        return Playback(player: playback.player,
                        keys: watch,
                        duration: playback.duration,
                        position: playback.position)
    }
}

/// Listens to one player item for as long as its playback is held, and holds
/// what the playback was already holding.
nonisolated private final class PlaybackWatch {
    private let status: NSKeyValueObservation
    private let errors: any NSObjectProtocol
    private let kept: AnyObject?

    init(item: AVPlayerItem, subject: String, log: any Logging, keeping kept: AnyObject?) {
        self.kept = kept
        status = item.observe(\.status) { item, _ in
            guard item.status == .failed else { return }
            log.record(PlaybackLogFormat.failure(item.error, of: subject), level: .error, category: .playback)
        }
        // The player's own running account: a segment that would not load, a
        // key that was refused. Most of these it recovers from by itself.
        errors = NotificationCenter.default.addObserver(forName: AVPlayerItem.newErrorLogEntryNotification,
                                                        object: item,
                                                        queue: nil) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  let event = item.errorLog()?.events.last else { return }
            log.record(PlaybackLogFormat.event(event, of: subject), level: .error, category: .playback)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(errors)
    }
}

/// The lines `LoggedPlayback` writes.
nonisolated enum PlaybackLogFormat {
    static func failure(_ error: (any Error)?, of subject: String) -> String {
        "\(subject) stopped: \(error.map(ErrorDescription.of) ?? "no error given")"
    }

    /// The address is left as the host: the rest of it names a signed stream.
    static func event(_ event: AVPlayerItemErrorLogEvent, of subject: String) -> String {
        let host = event.uri.flatMap { URL(string: $0)?.host() } ?? "?"
        let comment = event.errorComment ?? "no comment"
        return "\(subject): \(event.errorDomain) \(event.errorStatusCode) from \(host): \(comment)"
    }
}
