//
//  ArtworkView.swift
//  NPO light
//

import SwiftUI

extension EnvironmentValues {
    /// Where views get NPO's images. Set once, in `NPOLightApp` (ADR 0017).
    @Entry var artwork: any ArtworkProviding = NoArtwork()
}

/// An image from NPO, filling whatever frame it is given. It may be missing,
/// or not have arrived: a placeholder then, never an empty space
/// (FR-CONTENT-01).
struct ArtworkView: View {
    let url: URL?
    var size = ArtworkSize.tile

    /// How the image sits in a frame that is not its shape.
    var placement = Placement.filling

    enum Placement {
        /// Fills the frame, cut where it does not fit: a tile.
        case filling

        /// Whole, as large as the frame allows, against its trailing edge,
        /// with its leading edge fading out. For an image behind text, whose
        /// shape is not known beforehand: NPO's are anything from square to
        /// a wide banner.
        case wholeAtTrailingEdge
    }

    @Environment(\.artwork) private var artwork
    @State private var loaded: Loaded?

    /// An image and the address it belongs to, so that a view reused for
    /// another item never shows the previous one's picture.
    private struct Loaded {
        let url: URL
        let image: CGImage
    }

    var body: some View {
        // The frame decides the size and the image fills it: an overlay takes
        // the size it is offered, where the image alone would take its own.
        Color.clear
            .overlay(alignment: placement == .filling ? .center : .trailing) { content }
            .clipped()
            .task(id: url) { await load() }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let image, placement == .wholeAtTrailingEdge {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.4)],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                }
        } else if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else if placement == .filling {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "tv")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What is in memory is drawn in the first frame, without a task.
    private var image: CGImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return artwork.cached(url, size: size)
    }

    private func load() async {
        guard let url, image == nil else { return }
        // A failure leaves the placeholder, and the loader has logged it.
        guard let image = try? await artwork.image(at: url, size: size), !Task.isCancelled else { return }
        loaded = Loaded(url: url, image: image)
    }
}

#if DEBUG
#Preview("Artwork") {
    ArtworkView(url: nil)
        .frame(width: 320, height: 180)
}
#endif
