//
//  PlusRequiredView.swift
//  NPO light
//

import SwiftUI

/// Why an account without NPO Plus is turned away (FR-AUTH-08).
///
/// It says three things — that NPO light needs NPO Plus, that this account has
/// none, and that it is being signed out — and it stays until it is
/// acknowledged. Signing out follows the button rather than racing it.
struct PlusRequiredView: View {
    let acknowledge: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text("NPO light werkt alleen met NPO Plus")
                .font(.title2)
            Text("Het account waarmee je bent ingelogd heeft geen NPO Plus.")
            Text("We melden het daarom weer af. Log in met een account dat NPO Plus heeft, of neem NPO Plus op npo.nl.")
            Button("OK, afmelden", action: acknowledge)
        }
        .font(.headline)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 1200)
        .padding(80)
    }
}

#Preview {
    PlusRequiredView(acknowledge: {})
}
