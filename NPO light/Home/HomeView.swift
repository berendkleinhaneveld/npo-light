//
//  HomeView.swift
//  NPO light
//

import SwiftUI

/// Where the one navigation stack can go (ADR 0011).
enum Destination: Hashable {
    case search
}

/// The home page's own state. For now that is only where the stack is.
@MainActor
@Observable
final class HomeModel {
    var path: [Destination] = []

    func openSearch() {
        path.append(.search)
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
                    // Opening an item waits for its detail page (FR-CONTENT-03).
                    SearchView(model: search, open: { _ in })
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    HomeView(model: HomeModel(),
             search: SearchModel(catalogue: ScriptedCatalogue(), clock: SystemClock(), mode: .normal))
}
#endif
