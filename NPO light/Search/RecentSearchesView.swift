//
//  RecentSearchesView.swift
//  NPO light
//

import SwiftUI

/// What the search page shows while the field is empty: the recent terms,
/// each with what was picked for it (FR-SEARCH-04, FR-SEARCH-06).
struct RecentSearchesView: View {
    let model: SearchModel
    let open: (SearchPick) -> Void

    @State private var isConfirmingClear = false

    var body: some View {
        if model.recent.isEmpty {
            Text("Je hebt nog niet gezocht. Typ een paar letters; de resultaten verschijnen terwijl je typt.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 80)
                .accessibilityIdentifier("search-no-history")
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("Recente zoekopdrachten")
                    .font(.headline)
                    .padding(.horizontal, 80)
                ForEach(model.recent) { search in
                    RecentSearchRow(search: search,
                                    run: { model.run(search) },
                                    open: open,
                                    forget: { Task { await model.forget(search) } })
                }
                footer
            }
        }
        .confirmationDialog("Zoekgeschiedenis wissen?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Wissen", role: .destructive) {
                Task { await model.clearHistory() }
            }
            .accessibilityIdentifier("search-clear-confirm")
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Alle recente zoekopdrachten verdwijnen. De andere modus houdt zijn eigen geschiedenis.")
        }
    }

    private var footer: some View {
        HStack(spacing: 32) {
            Button("Zoekgeschiedenis wissen") { isConfirmingClear = true }
                .accessibilityIdentifier("search-clear-history")
            // The long press is not the only way to learn it exists.
            Text("Houd de selectieknop ingedrukt op een zoekterm om hem te verwijderen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 80)
        .padding(.top, 32)
        // The whole width takes focus, so that coming down from a tile far
        // to the right still lands on the button (NFR-A11Y-01).
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

/// One recent search: the term, which runs the search again, and beside it
/// what was picked for it, which opens without searching (FR-SEARCH-06).
struct RecentSearchRow: View {
    let search: RecentSearch
    let run: () -> Void
    let open: (SearchPick) -> Void
    let forget: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 32) {
                term
                if search.picks.isEmpty {
                    Text("Nog niets gekozen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    picks
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var term: some View {
        Button(action: run) {
            Label {
                Text(verbatim: search.term)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
            .frame(minWidth: 240, alignment: .leading)
        }
        .contextMenu {
            Button("Zoek naar “\(search.term)”", systemImage: "magnifyingglass", action: run)
            Button("Verwijderen", systemImage: "trash", role: .destructive, action: forget)
        }
        .accessibilityLabel("Zoek opnieuw naar \(search.term)")
        .accessibilityIdentifier("recent-term-\(search.term)")
    }

    private var picks: some View {
        ForEach(search.picks) { item in
            Button { open(item.pick) } label: {
                PickTile(item: item)
            }
            .buttonStyle(.card)
            .accessibilityLabel("\(item.title), direct openen")
            .accessibilityIdentifier("recent-pick-\(item.identifier)")
        }
    }
}

/// A picked item, small: its image with its title beside it.
struct PickTile: View {
    let item: PickedItem

    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(url: item.artwork)
                .frame(width: 128, height: 72)
            Text(verbatim: item.title)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(.trailing, 16)
    }
}

#if DEBUG
#Preview("Recent searches") {
    RecentSearchesView(model: SearchModel.scripted(history: .filled),
                       open: { _ in })
}

#Preview("Row") {
    RecentSearchRow(search: RecentSearch(term: "fr",
                                         picks: [PickedItem(.series(ScriptedCatalogue.results.series[0]))]),
                    run: {},
                    open: { _ in },
                    forget: {})
}

#Preview("Pick") {
    PickTile(item: PickedItem(.series(ScriptedCatalogue.results.series[0])))
}
#endif
