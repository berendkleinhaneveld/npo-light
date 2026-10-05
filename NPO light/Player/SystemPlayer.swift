//
//  SystemPlayer.swift
//  NPO light
//

import AVKit
import SwiftUI

/// The system's own player (FR-PLAY-01), as a view.
///
/// Not SwiftUI's `VideoPlayer`: that one has no way to put a button on the
/// video that the remote can reach, and the player holds focus while it
/// plays. The system player's contextual action is that way (ADR 0021).
struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    /// A button the player shows over the video for as long as it is given,
    /// and what selecting it does.
    let action: (title: String, run: () -> Void)?

    /// Somebody touched the remote: the transport bar came up (FR-PLAY-08).
    var interacted: () -> Void = {}

    /// Hears from the player when its transport bar comes and goes.
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var interacted: () -> Void = {}

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willTransitionToVisibilityOfTransportBar visible: Bool,
                                  with coordinator: any AVPlayerViewControllerAnimationCoordinator) {
            if visible { interacted() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.interacted = interacted
        if controller.player !== player {
            controller.player = player
        }
        if let action {
            controller.contextualActions = [UIAction(title: action.title) { _ in action.run() }]
        } else if !controller.contextualActions.isEmpty {
            controller.contextualActions = []
        }
    }
}

/// Says that an episode started by itself, and which (FR-PLAY-05). The way
/// to stop it is the player's own button beside it.
struct NextEpisodeNotice: View {
    let episode: Playable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volgende aflevering speelt")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: [episode.title, episode.caption].compactMap(\.self).joined(separator: " · "))
                .font(.headline)
                .lineLimit(2)
        }
        .padding(32)
        .frame(maxWidth: 800, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("next-episode-notice")
    }
}

/// The pause before the next episode in kids mode: which episode is coming,
/// the seconds left as a number a child can read, and a way to stop
/// (FR-PLAY-06).
struct NextEpisodeCountdown: View {
    let episode: Playable
    let remaining: Int
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text("Zo meteen:")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(verbatim: episode.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(verbatim: "\(remaining)")
                .font(.system(size: 220, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: remaining)
                .accessibilityIdentifier("next-episode-countdown")
            Button("Stoppen", systemImage: "stop.fill", action: stop)
                .accessibilityIdentifier("next-episode-stop")
        }
        .frame(maxWidth: 1200)
        .padding(80)
    }
}

/// Asks whether anyone is still watching, and says what happens without an
/// answer (FR-PLAY-08).
struct StillWatchingPrompt: View {
    /// How long it has played, in seconds.
    let played: Int
    let remaining: Int
    let keepWatching: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text("Kijk je nog?")
                .font(.title2.bold())
            Text("Er is \(Text(TimingChoices.words(for: played))) achter elkaar gekeken.")
                .font(.headline)
            Text("Zonder antwoord stopt het afspelen over \(remaining) seconden.")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("still-watching-remaining")
            HStack(spacing: 32) {
                Button("Doorkijken", systemImage: "play.fill", action: keepWatching)
                    .accessibilityIdentifier("still-watching-continue")
                Button("Stoppen", systemImage: "stop.fill", action: stop)
                    .accessibilityIdentifier("still-watching-stop")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 1200)
        .padding(80)
    }
}

#if DEBUG
#Preview("Still watching") {
    StillWatchingPrompt(played: 3600, remaining: 30, keepWatching: {}, stop: {})
}

#Preview("Countdown") {
    NextEpisodeCountdown(episode: ScriptedCatalogue.results.episodes[0], remaining: 5, stop: {})
}

#Preview("Next episode") {
    NextEpisodeNotice(episode: ScriptedCatalogue.results.episodes[0])
}
#endif
