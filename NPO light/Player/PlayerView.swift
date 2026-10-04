//
//  PlayerView.swift
//  NPO light
//

import AVKit
import SwiftUI

/// The system player, and nothing drawn over its controls (FR-PLAY-01).
struct PlayerView: View {
    let model: PlayerModel

    /// The player went away, after its last position was written.
    var closed: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .task { await model.start() }
            .onDisappear {
                Task {
                    await model.close()
                    closed()
                }
            }
            .onChange(of: model.isOver) { _, isOver in
                // The last episode ended, or going on was stopped: back to
                // where playback was started from (FR-PLAY-05, FR-PLAY-07).
                if isOver { dismiss() }
            }
            .onChange(of: scenePhase) { _, phase in
                // The television went to its home screen, or to sleep.
                if phase != .active { model.rest() }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .preparing:
            ProgressView()
        case .playing(let playback):
            SystemPlayer(player: playback.player, action: stopAction)
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    if let announced = model.announced {
                        NextEpisodeNotice(episode: announced)
                            .padding(80)
                            .transition(.opacity)
                    }
                }
                .animation(.default, value: model.announced)
        case .failed(let problem):
            PlayerProblemView(title: model.playable.title, problem: problem) {
                Task { await model.start() }
            }
        }
    }
}

extension PlayerView {
    /// While the player says that an episode started by itself, it offers
    /// to stop (FR-PLAY-05).
    private var stopAction: (title: String, run: () -> Void)? {
        guard model.announced != nil else { return nil }
        return (String(localized: "Stoppen"), { model.stopGoingOn() })
    }
}

/// Why nothing is playing, and a way forward. The Menu button leaves, as
/// everywhere.
struct PlayerProblemView: View {
    let title: String
    let problem: PlayerModel.Problem
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text(verbatim: title)
                .font(.title3.bold())
            Text(explanation)
                .font(.headline)
                .multilineTextAlignment(.center)
            // An item that is gone will not come back by asking again.
            if problem != .unavailable {
                Button("Opnieuw proberen", action: retry)
            }
        }
        .frame(maxWidth: 1200)
        .padding(80)
    }

    private var explanation: LocalizedStringKey {
        switch problem {
        case .unavailable:
            "Dit is niet meer beschikbaar bij NPO."
        case .unreachable:
            "Deze tv kan NPO nu niet bereiken. Controleer het netwerk en probeer het opnieuw."
        case .failed:
            "Afspelen is niet gelukt. Probeer het opnieuw."
        }
    }
}

#if DEBUG
#Preview("Player") {
    PlayerView(model: .scripted(ScriptedCatalogue.results.episodes[0]))
}

#Preview("Unavailable") {
    PlayerProblemView(title: "Freeks wilde wereld", problem: .unavailable, retry: {})
}

#Preview("Failed") {
    PlayerProblemView(title: "Freeks wilde wereld", problem: .failed, retry: {})
}
#endif
