//
//  HomeView.swift
//  NPO light
//

import SwiftUI

/// The root of the navigation stack: search, and the rows.
///
/// The three rows the home page is for: pinned, recently watched, and watch
/// later while something is saved (FR-HOME-01).
struct HomeView: View {
    @Bindable var model: HomeModel
    let search: SearchModel
    let modes: ModeModel
    let settings: SettingsModel
    let seriesModel: (SeriesSummary) -> SeriesDetailModel
    let playerModel: (PlayRequest) -> PlayerModel

    var body: some View {
        NavigationStack(path: $model.path) {
            VStack(alignment: .leading, spacing: 48) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        HomeRow(kind: .pinned,
                                tiles: model.pinned,
                                select: { model.select($0) },
                                open: { model.open($0) },
                                remove: { tile in Task { await model.unpin(tile.id) } },
                                search: { model.openSearch() })
                        HomeRow(kind: .continuing,
                                tiles: model.continuing,
                                select: { model.select($0) },
                                open: { model.open($0) },
                                remove: { tile in Task { await model.remove(tile.id) } },
                                search: { model.openSearch() },
                                saved: model.saved,
                                toggleSave: { tile in Task { await model.toggleSave(tile) } })
                        // Absent, heading and all, while nothing is saved
                        // (FR-LATER-05).
                        if !model.later.isEmpty {
                            HomeRow(kind: .later,
                                    tiles: model.later,
                                    select: { model.select($0) },
                                    open: { model.open($0) },
                                    remove: { tile in Task { await model.removeSaved(tile) } },
                                    search: { model.openSearch() })
                        }
                    }
                }
            }
            .task { await model.refresh() }
            .onChange(of: model.path.isEmpty) { _, isHome in
                // Back from a page where something may have been pinned.
                guard isHome else { return }
                Task { await model.refresh() }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .settings:
                    SettingsView(model: settings)
                case .search:
                    SearchView(model: search, open: { model.open($0) }, actions: playableActions)
                case .series(let series):
                    SeriesDetailScreen(series: series,
                                       playbacksEnded: model.playbacksEnded,
                                       makeModel: seriesModel) { model.play($0) }
                }
            }
        }
        // On every page of the stack, and not on the player: which mode this
        // is, in a symbol and in words (FR-MODE-03).
        .overlay(alignment: .bottomTrailing) {
            if model.mode == .kids {
                KidsModeBadge()
                    .padding(40)
            }
        }
        .fullScreenCover(item: $model.playing) { request in
            PlayerScreen(request: request, makeModel: playerModel) {
                Task { await model.playbackEnded() }
            }
        }
    }

    private var playableActions: PlayableActions {
        PlayableActions(isSaved: { model.saved.contains($0) },
                        toggleSave: { playable, origin in Task { await model.toggleSave(playable, origin: origin) } },
                        openSeries: { episode in Task { await model.openSeries(of: episode) } })
    }

    /// Search without a menu first (FR-SEARCH-01).
    private var header: some View {
        HStack {
            // A proper noun, and no translation's job.
            Text(verbatim: "NPO light")
                .font(.title3)
            Spacer()
            // Search first: it is what the page opens on (FR-SEARCH-01).
            Button("Zoeken", systemImage: "magnifyingglass") { model.openSearch() }
                .accessibilityIdentifier("home-search")
            ModeSwitch(modes: modes)
            // No way in from kids mode (FR-MODE-06).
            if model.mode == .normal {
                Button("Instellingen", systemImage: "gearshape") { model.openSettings() }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("home-settings")
            }
        }
        .padding(.horizontal, 80)
        .focusSection()
    }
}

/// Keeps one model for as long as the page is on the stack, so that a redraw
/// of the stack does not start the page over.
private struct SeriesDetailScreen: View {
    @State private var model: SeriesDetailModel
    private let playbacksEnded: Int
    private let play: (PlayRequest) -> Void

    init(series: SeriesSummary,
         playbacksEnded: Int,
         makeModel: (SeriesSummary) -> SeriesDetailModel,
         play: @escaping (PlayRequest) -> Void) {
        _model = State(initialValue: makeModel(series))
        self.playbacksEnded = playbacksEnded
        self.play = play
    }

    var body: some View {
        SeriesDetailView(model: model, play: play)
            .onChange(of: playbacksEnded) {
                // Back from the player: what was watched has changed.
                Task { await model.readWatched() }
            }
    }
}

/// Keeps one model for as long as the player is presented.
private struct PlayerScreen: View {
    @State private var model: PlayerModel
    private let closed: () -> Void

    init(request: PlayRequest, makeModel: (PlayRequest) -> PlayerModel, closed: @escaping () -> Void) {
        _model = State(initialValue: makeModel(request))
        self.closed = closed
    }

    var body: some View {
        PlayerView(model: model, closed: closed)
    }
}

#if DEBUG
#Preview("Home") {
    HomeView(model: .scripted(pinned: ScriptedCatalogue.results.series),
             search: .scripted(),
             modes: .scripted(),
             settings: .scripted(),
             seriesModel: { .scripted($0) },
             playerModel: { .scripted($0.playable) })
}

#endif
