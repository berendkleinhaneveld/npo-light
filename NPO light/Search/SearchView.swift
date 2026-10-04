//
//  SearchView.swift
//  NPO light
//

import SwiftUI

/// What was chosen from a set of results.
enum SearchPick: Equatable {
    case series(SeriesSummary)
    case playable(Playable)
}

/// The search page: the system's search field, and what the catalogue has for
/// the text in it (FR-SEARCH-02).
struct SearchView: View {
    @Bindable var model: SearchModel
    let open: (SearchPick) -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .searchable(text: $model.query, prompt: "Zoek een serie, film of aflevering")
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            // Recent searches go here (FR-SEARCH-04) once there is a store to
            // keep them in.
            Color.clear
        case .searching:
            ProgressView()
                .padding(.top, 80)
        case .results(let results):
            SearchResultsView(results: results, open: open)
        case .noResults(let term):
            Text("Niets gevonden voor “\(term)”.")
                .font(.headline)
                .padding(.top, 80)
        case .failed:
            failure
        }
    }

    private var failure: some View {
        VStack(spacing: 32) {
            Text("Zoeken is niet gelukt.")
                .font(.headline)
            Text("Deze tv kan NPO nu niet bereiken. Controleer het netwerk en probeer het opnieuw.")
            Button("Opnieuw proberen") { model.retry() }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 80)
    }
}

/// Series and playable items, apart, as NPO answers them.
struct SearchResultsView: View {
    let results: SearchResults
    let open: (SearchPick) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 48) {
                if !results.series.isEmpty {
                    row("Series") {
                        ForEach(results.series) { series in
                            Button { open(.series(series)) } label: {
                                CatalogueTile(artwork: series.artwork, title: series.title, caption: nil)
                            }
                            .accessibilityLabel("\(series.title), serie")
                        }
                    }
                }
                if !results.playables.isEmpty {
                    row("Afleveringen en films") {
                        ForEach(results.playables) { playable in
                            Button { open(.playable(playable)) } label: {
                                CatalogueTile(artwork: playable.artwork,
                                              title: playable.title,
                                              caption: playable.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey,
                     @ViewBuilder tiles: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    tiles()
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
        .buttonStyle(.card)
    }
}

/// Artwork with a title under it, on the five-across grid the wireframe uses.
struct CatalogueTile: View {
    static let width: CGFloat = 320

    let artwork: URL?
    let title: String
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            image
                .frame(width: Self.width, height: Self.width * 9 / 16)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.caption)
                    .lineLimit(1)
                if let caption {
                    // Two lines: for a search hit the caption is where the
                    // episode's own title is.
                    Text(verbatim: caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: Self.width, alignment: .leading)
    }

    private var image: some View {
        ArtworkView(url: artwork)
    }
}

/// An image from NPO. It may be missing, or not have arrived: a placeholder
/// then, never an empty space (FR-CONTENT-01).
struct ArtworkView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "tv")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Results") {
    NavigationStack {
        SearchResultsView(results: ScriptedCatalogue.results, open: { _ in })
    }
}

#Preview("Search") {
    NavigationStack {
        SearchView(model: SearchModel(catalogue: ScriptedCatalogue(), clock: SystemClock(), mode: .normal),
                   open: { _ in })
    }
}

#Preview("Artwork") {
    ArtworkView(url: nil)
        .frame(width: 320, height: 180)
}

#Preview("Tile") {
    CatalogueTile(artwork: nil, title: "Freeks wilde wereld", caption: "Afl. 1 • 10m")
}
#endif
