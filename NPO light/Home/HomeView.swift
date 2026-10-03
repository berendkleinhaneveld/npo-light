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

    func openSearch() {
        path.append(.search)
    }

    /// Something was chosen from search results.
    func open(_ pick: SearchPick) {
        switch pick {
        case .series(let series):
            path.append(.series(series))
        case .playable:
            // A film's or an episode's own page waits for Q-10: NPO's list
            // does not say which of the two it is.
            break
        }
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
                    SeriesDetailScreen(series: series, makeModel: seriesModel)
                }
            }
        }
    }
}

/// Keeps one model for as long as the page is on the stack, so that a redraw
/// of the stack does not start the page over.
private struct SeriesDetailScreen: View {
    @State private var model: SeriesDetailModel

    init(series: SeriesSummary, makeModel: (SeriesSummary) -> SeriesDetailModel) {
        _model = State(initialValue: makeModel(series))
    }

    var body: some View {
        SeriesDetailView(model: model)
    }
}

#if DEBUG
#Preview {
    HomeView(model: HomeModel(),
             search: SearchModel(catalogue: ScriptedCatalogue(), clock: SystemClock(), mode: .normal),
             seriesModel: { SeriesDetailModel(summary: $0, catalogue: ScriptedCatalogue(), mode: .normal) })
}
#endif
