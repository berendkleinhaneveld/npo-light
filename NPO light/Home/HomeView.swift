//
//  HomeView.swift
//  NPO light
//

import SwiftUI

/// Where the one navigation stack can go (ADR 0011).
enum Destination: Hashable {
    case search
    case series(SeriesSummary)
}

/// The home page's own state. For now that is only where the stack is.
@MainActor
@Observable
final class HomeModel {
    var path: [Destination] = []

    /// What is playing. The player is presented over the stack rather than
    /// pushed onto it (ADR 0011).
    var playing: Playable?

    func openSearch() {
        path.append(.search)
    }

    /// Something was chosen from search results.
    func open(_ pick: SearchPick) {
        switch pick {
        case .series(let series):
            path.append(.series(series))
        case .playable(let playable):
            // Straight to playing. A film's or an episode's own page waits
            // for Q-10: NPO's list does not say which of the two it is.
            play(playable)
        }
    }

    func play(_ playable: Playable) {
        playing = playable
    }
}

/// The root of the navigation stack.
///
/// The rows the home page is for — pinned, recently watched, watch later —
/// arrive with FR-HOME. What is here is the stack itself and the one action
/// that already has somewhere to go: search, without a menu first
/// (FR-SEARCH-01).
struct HomeView: View {
    @Bindable var model: HomeModel
    let search: SearchModel
    let seriesModel: (SeriesSummary) -> SeriesDetailModel
    let playerModel: (Playable) -> PlayerModel

    var body: some View {
        NavigationStack(path: $model.path) {
            VStack(spacing: 48) {
                // A proper noun, and no translation's job.
                Text(verbatim: "NPO light")
                    .font(.largeTitle)
                Button("Zoeken", systemImage: "magnifyingglass") { model.openSearch() }
                    .accessibilityIdentifier("home-search")
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .search:
                    SearchView(model: search) { model.open($0) }
                case .series(let series):
                    SeriesDetailScreen(series: series, makeModel: seriesModel) { model.play($0) }
                }
            }
        }
        .fullScreenCover(item: $model.playing) { playable in
            PlayerScreen(playable: playable, makeModel: playerModel)
        }
    }
}

/// Keeps one model for as long as the page is on the stack, so that a redraw
/// of the stack does not start the page over.
private struct SeriesDetailScreen: View {
    @State private var model: SeriesDetailModel
    private let play: (Playable) -> Void

    init(series: SeriesSummary,
         makeModel: (SeriesSummary) -> SeriesDetailModel,
         play: @escaping (Playable) -> Void) {
        _model = State(initialValue: makeModel(series))
        self.play = play
    }

    var body: some View {
        SeriesDetailView(model: model, play: play)
    }
}

/// Keeps one model for as long as the player is presented.
private struct PlayerScreen: View {
    @State private var model: PlayerModel

    init(playable: Playable, makeModel: (Playable) -> PlayerModel) {
        _model = State(initialValue: makeModel(playable))
    }

    var body: some View {
        PlayerView(model: model)
    }
}

#if DEBUG
#Preview {
    HomeView(model: HomeModel(),
             search: SearchModel.scripted(),
             seriesModel: { SeriesDetailModel(summary: $0, catalogue: ScriptedCatalogue(), mode: .normal) },
             playerModel: { PlayerModel(playable: $0, mode: .normal, starter: ScriptedPlayback()) })
}
#endif
