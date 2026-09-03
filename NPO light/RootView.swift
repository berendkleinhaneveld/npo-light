//
//  RootView.swift
//  NPO light
//

import SwiftUI

/// The app's only screen until there is one.
///
/// ADR 0010 makes this the point where the session decides between sign-in and
/// home (FR-AUTH-01). Neither exists yet, so this is scaffolding: the first
/// feature pull request replaces the body outright rather than building on it.
///
/// The one string on screen is a proper noun, which no language translates.
/// That is deliberate while the String Catalog NFR-I18N-01 asks for does not
/// exist yet — a placeholder sentence here would be the first entry in a
/// catalogue nobody wants.
struct RootView: View {
    var body: some View {
        Text(verbatim: "NPO light")
            .font(.largeTitle)
    }
}

#Preview {
    RootView()
}
