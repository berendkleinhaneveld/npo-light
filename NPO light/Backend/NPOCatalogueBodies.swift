//
//  NPOCatalogueBodies.swift
//  NPO light
//

import Foundation

/// One of the account's NPO profiles, from `GET /profiles`.
nonisolated struct ProfileBody: Decodable {
    static let generalType = "GENERAL"
    static let kidsType = "KIDS"

    let guid: String
    let type: String?
}

/// An image as NPO lists it. `role` tells a header image (`default`) from a
/// transparent title logo (`title`).
nonisolated struct ImageBody: Decodable {
    static let artworkRole = "default"

    let url: String?
    let role: String?
}

/// An item in a collection or a season. A collection mixes types, and only the
/// fields every type shares are certain; the rest is there for some of them.
nonisolated struct CatalogueItemBody: Decodable {
    static let seriesType = "series"
    static let programType = "program"

    /// What NPO's app opens for a programme that belongs to no series: a
    /// page of its own. An episode of a series has `player` here (Q-10).
    static let singleProgrammeTarget = "detail"

    let guid: String
    /// Absent in a season's list, where everything is a programme.
    let type: String?
    let title: String?
    let subtitle: String?
    let synopsis: String?
    let durationInSeconds: Int?
    /// Only in a collection. A season's list has none.
    let target: String?
    let images: [ImageBody]?

    var artwork: URL? {
        images?.first { $0.role == ImageBody.artworkRole }?.url.flatMap(URL.init(string:))
    }

    var seriesSummary: SeriesSummary? {
        guard let title else { return nil }
        return SeriesSummary(id: ItemID(rawValue: guid), title: title, artwork: artwork)
    }

    var playable: Playable? {
        guard let title else { return nil }
        return Playable(id: EpisodeID(rawValue: guid),
                        title: title,
                        caption: subtitle,
                        synopsis: synopsis,
                        duration: durationInSeconds.map { .seconds($0) },
                        artwork: artwork)
    }
}

/// `GET /search`: the page envelope, with one collection of series and one of
/// programmes.
nonisolated struct SearchBody: Decodable {
    struct Collection: Decodable {
        let items: [CatalogueItemBody]?
    }

    let collections: [Collection]

    /// Sorted by each item's own type rather than by the collection it came
    /// in, so a collection NPO adds or renames does not lose results.
    ///
    /// NPO lists single programmes among the episodes. They are told apart by
    /// where NPO's app would go for them, and a programme that does not say is
    /// taken for an episode, which is what nearly all of them are.
    var results: SearchResults {
        let items = collections.flatMap { $0.items ?? [] }
        let programmes = items.filter { $0.type == CatalogueItemBody.programType }
        let singles = programmes.filter { $0.target == CatalogueItemBody.singleProgrammeTarget }
        let episodes = programmes.filter { $0.target != CatalogueItemBody.singleProgrammeTarget }
        return SearchResults(
            series: items.filter { $0.type == CatalogueItemBody.seriesType }.compactMap(\.seriesSummary),
            singleProgrammes: singles.compactMap(\.playable),
            episodes: episodes.compactMap(\.playable)
        )
    }
}

/// `GET /series/page/{guid}`: the whole series screen in one answer.
nonisolated struct SeriesPageBody: Decodable {
    struct Header: Decodable {
        let title: String
        /// NPO puts the synopsis in the header's subtitle.
        let subtitle: String?
        let images: [ImageBody]?
    }

    struct Tab: Decodable {
        static let seasonsType = "seasons"

        /// What ``programSort`` says for a programme that is followed as it
        /// is broadcast — a daily one, with a season for each year. NPO then
        /// lists the latest season first, as well as the latest episode.
        static let newestFirst = "desc"

        let type: String?
        let programSort: String?
        let seasons: [SeasonBody]?
    }

    struct SeasonBody: Decodable {
        let guid: String
        let title: String
    }

    let guid: String
    let header: Header
    let tabs: [Tab]?

    var detail: SeriesDetail {
        let tab = tabs?.first { $0.type == Tab.seasonsType }
        let seasons = tab?.seasons ?? []
        let artwork = header.images?
            .first { $0.role == ImageBody.artworkRole }?.url
            .flatMap(URL.init(string:))
        return SeriesDetail(
            id: ItemID(rawValue: guid),
            title: header.title,
            synopsis: header.subtitle,
            artwork: artwork,
            seasons: seasons.map { Season(id: SeasonID(rawValue: $0.guid), title: $0.title) },
            listsNewestFirst: tab?.programSort == Tab.newestFirst
        )
    }
}
