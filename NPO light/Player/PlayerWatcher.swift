//
//  PlayerWatcher.swift
//  NPO light
//

import AVFoundation
import Foundation

/// What the system player tells the app while something plays, as five
/// events on the main actor. It holds the observations, so that the model
/// holds none.
@MainActor
final class PlayerWatcher {
    struct Events {
        /// The stream stopped being playable: a licence that could not be
        /// obtained, a manifest that would not load.
        let failed: () -> Void

        /// Playback paused, whoever paused it.
        let paused: () -> Void

        /// The interval at which the position is written came round
        /// (FR-PLAY-03).
        let tick: () -> Void

        /// What plays reached its end.
        let ended: () -> Void

        /// Somebody paused, resumed or scrubbed — or the app did: the two
        /// look the same here, and are told apart by when they happen
        /// (FR-PLAY-08).
        let interacted: () -> Void
    }

    private var itemStatus: NSKeyValueObservation?
    private var pauses: NSKeyValueObservation?
    private var ticks: (player: AVPlayer, token: Any)?
    private var notifications: [any NSObjectProtocol] = []

    /// Watches `player`, in place of whatever was watched before.
    func watch(_ player: AVPlayer, telling events: Events) {
        stop()
        itemStatus = player.currentItem?.observe(\.status) { item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in events.failed() }
        }
        pauses = player.observe(\.timeControlStatus) { player, _ in
            guard player.timeControlStatus == .paused else { return }
            Task { @MainActor in events.paused() }
        }
        let interval = CMTime(seconds: PlaybackCoordinator.interval, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            Task { @MainActor in events.tick() }
        }
        ticks = (player, token)

        let center = NotificationCenter.default
        notifications = [
            center.addObserver(forName: AVPlayer.rateDidChangeNotification,
                               object: player,
                               queue: .main) { note in
                let reason = note.userInfo?[AVPlayer.rateDidChangeReasonKey] as? AVPlayer.RateDidChangeReason
                guard reason == .setRateCalled else { return }
                Task { @MainActor in events.interacted() }
            }
        ]
        // Only for this player's own item: asked without one, the centre
        // would report every item in the process.
        guard let item = player.currentItem else { return }
        notifications += [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                               object: item,
                               queue: .main) { _ in
                Task { @MainActor in events.ended() }
            },
            center.addObserver(forName: AVPlayerItem.timeJumpedNotification,
                               object: item,
                               queue: .main) { _ in
                Task { @MainActor in events.interacted() }
            }
        ]
    }

    func stop() {
        itemStatus = nil
        pauses = nil
        if let ticks {
            ticks.player.removeTimeObserver(ticks.token)
        }
        ticks = nil
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications = []
    }
}
