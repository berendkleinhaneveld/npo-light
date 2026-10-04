//
//  HomeView.swift
//  NPO light
//

import SwiftUI

/// The root of the navigation stack: search, and the rows.
///
/// Of the three rows the home page is for, the pinned one is here
/// (FR-HOME-02). Recently watched and watch later arrive with the stores
/// that keep them (FR-HOME-01).
struct HomeView: View {
    @Bindable var model: HomeModel
    let search: SearchModel
    let seriesModel: (SeriesSummary) -> SeriesDetailModel
    let playerModel: (PlayRequest) -> PlayerModel

    var body: some View {
        NavigationStack(path: $model.path) {
            VStack(alignment: .leading, spacing: 48) {
                header
                ScrollView {
                    PinnedRow(pinned: model.pinned,
                              open: { model.open($0) },
                              unpin: { series in Task { await model.unpin(series) } },
                              search: { model.openSearch() })
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
                case .search:
                    SearchView(model: search) { model.open($0) }
                case .series(let series):
                    SeriesDetailScreen(series: series,
                                       playbacksEnded: model.playbacksEnded,
                                       makeModel: seriesModel) { model.play($0) }
                }
            }
        }
        .fullScreenCover(item: $model.playing) { request in
            PlayerScreen(request: request, makeModel: playerModel) { model.playbackEnded() }
        }
    }

    /// Search without a menu first (FR-SEARCH-01).
    private var header: some View {
        HStack {
            // A proper noun, and no translation's job.
            Text(verbatim: "NPO light")
                .font(.title3)
            Spacer()
            Button("Zoeken", systemImage: "magnifyingglass") { model.openSearch() }
                .accessibilityIdentifier("home-search")
        }
        .padding(.horizontal, 80)
        .focusSection()
    }
}

/// The pinned series, most recently pinned first, or what to do to get one
/// (FR-HOME-02, FR-HOME-09).
///
/// A tile opens its series. It is meant to play the next unwatched episode
/// (FR-HOME-04), which waits for something that records what was watched.
struct PinnedRow: View {
    let pinned: [SeriesSummary]
    let open: (SeriesSummary) -> Void
    let unpin: (SeriesSummary) -> Void
    let search: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vastgezet")
                .font(.headline)
                .padding(.horizontal, 80)
            if pinned.isEmpty {
                empty
            } else {
                tiles
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var empty: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nog niets vastgezet.")
                    .font(.body.bold())
                Text("Zoek een serie en zet hem vast. Dan staat hij hier, met de volgende aflevering klaar.")
                    .foregroundStyle(.secondary)
            }
            Button("Zoeken", systemImage: "magnifyingglass", action: search)
                .accessibilityIdentifier("pinned-empty-search")
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 24)
    }

    private var tiles: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 40) {
                ForEach(pinned) { series in
                    Button { open(series) } label: {
                        CatalogueTile(artwork: series.artwork, title: series.title, caption: nil)
                    }
                    .contextMenu {
                        Button("Losmaken", systemImage: "pin.slash") { unpin(series) }
                    }
                    .accessibilityLabel("\(series.title), serie")
                    .accessibilityIdentifier("pinned-\(series.id.rawValue)")
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .buttonStyle(.card)
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
             seriesModel: { .scripted($0) },
             playerModel: { .scripted($0.playable) })
}

#Preview("Nothing pinned") {
    PinnedRow(pinned: [], open: { _ in }, unpin: { _ in }, search: {})
}
#endif
