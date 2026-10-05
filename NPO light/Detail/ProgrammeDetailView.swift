//
//  ProgrammeDetailView.swift
//  NPO light
//

import SwiftUI

/// A single programme: its own image across the page, what it is, and the
/// actions on it — playing or resuming, and saving for later
/// (FR-CONTENT-03, FR-CONTENT-08). There is no pin: only a series is pinned
/// (FR-HOME-03).
struct ProgrammeDetailView: View {
    let model: ProgrammeDetailModel
    let play: (PlayRequest) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(url: detail?.playable.artwork ?? model.summary.artwork, size: .full)
            shade
            info
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .task { await model.load() }
    }

    private var detail: ProgrammeDetail? {
        if case .loaded(let detail) = model.page { return detail }
        return nil
    }

    /// Dark where the text is, the image itself to the right.
    private var shade: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black.opacity(0.85), location: 0.45),
                                   .init(color: .black.opacity(0.15), location: 0.85)],
                           startPoint: .leading,
                           endPoint: .trailing)
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .clear, location: 0.5)],
                           startPoint: .bottom,
                           endPoint: .top)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: detail?.playable.title ?? model.summary.title)
                .font(.title.bold())
                .lineLimit(2)
            if let caption = detail?.playable.caption ?? model.summary.caption {
                Text(verbatim: caption)
                    .foregroundStyle(.secondary)
            }
            if model.isWatched {
                Label("Gezien", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .accessibilityIdentifier("programme-watched")
            }
            if let synopsis = detail?.playable.synopsis ?? model.summary.synopsis {
                Text(verbatim: synopsis)
                    .font(.body)
                    .lineLimit(8)
            }
            state
                .padding(.top, 12)
        }
        .frame(maxWidth: 1100, alignment: .leading)
        .padding(.horizontal, 80)
        .padding(.bottom, 100)
    }

    @ViewBuilder private var state: some View {
        switch model.page {
        case .loading:
            ProgressView()
        case .loaded(let detail):
            if detail.isPlayable {
                actions
            } else {
                // No stream is asked for something NPO says cannot be played
                // (FR-CONTENT-06).
                Text("Dit is niet meer beschikbaar bij NPO.")
                    .font(.headline)
                save
            }
        case .unavailable:
            Text("Dit is niet meer beschikbaar bij NPO.")
                .font(.headline)
        case .failed:
            Text("Deze tv kan NPO nu niet bereiken. Controleer het netwerk en probeer het opnieuw.")
            Button("Opnieuw proberen") {
                Task { await model.load() }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 24) {
            Button(model.resumes ? Self.resume : Self.start, systemImage: "play.fill") {
                if let request = model.request { play(request) }
            }
            .accessibilityIdentifier(model.resumes ? "programme-resume" : "programme-play")
            save
        }
    }

    /// The words say which of the two it does (FR-LATER-03).
    @ViewBuilder private var save: some View {
        if model.isSaved {
            Button("Verwijderen uit Later kijken", systemImage: "bookmark.slash") {
                Task { await model.toggleSave() }
            }
            .accessibilityIdentifier("programme-unsave")
        } else {
            Button("Later kijken", systemImage: "bookmark") {
                Task { await model.toggleSave() }
            }
            .accessibilityIdentifier("programme-save")
        }
    }

    private static let start: LocalizedStringKey = "Afspelen"
    private static let resume: LocalizedStringKey = "Verder kijken"
}

#if DEBUG
#Preview("Programme") {
    ProgrammeDetailView(model: .scripted(ScriptedCatalogue.results.singleProgrammes[0]), play: { _ in })
}
#endif
