//
//  OfflineNotice.swift
//  NPO light
//

import SwiftUI

/// Says that NPO cannot be reached, and what that means for what is on
/// screen (NFR-REL-01). It goes away by itself when NPO answers again.
struct OfflineNotice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 8) {
                Text("Deze tv kan NPO nu niet bereiken.")
                    .font(.body.bold())
                Text("Je ziet wat eerder is opgehaald. Afspelen en zoeken kan weer als er verbinding is.")
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "wifi.slash")
        }
        .padding(.horizontal, 80)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-notice")
    }
}

#Preview {
    OfflineNotice()
}
