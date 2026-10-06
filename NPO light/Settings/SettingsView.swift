//
//  SettingsView.swift
//  NPO light
//

import SwiftUI

/// Settings: the three timings, signing out, and erasing what is kept on
/// this television (FR-SET-01 to FR-SET-04). Normal mode only (FR-MODE-06).
struct SettingsView: View {
    private enum Question: Identifiable {
        case signOut
        case erase(Set<Mode>)

        var id: String {
            switch self {
            case .signOut: "sign-out"
            case .erase(let modes): "erase-" + modes.map(\.rawValue).sorted().joined(separator: "-")
            }
        }
    }

    let model: SettingsModel

    @State private var question: Question?

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 60) {
                playback
                    // The choices decide how wide this column is.
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 48) {
                    account
                    localData
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .navigationTitle("Instellingen")
        .confirmationDialog(title, isPresented: isAsking, titleVisibility: .visible, presenting: question) { asked in
            switch asked {
            case .signOut:
                Button("Afmelden", role: .destructive) { model.signOut() }
                    .accessibilityIdentifier("settings-sign-out-confirm")
            case .erase(let modes):
                Button("Wissen", role: .destructive) {
                    Task { await model.erase(modes) }
                }
                .accessibilityIdentifier("settings-erase-confirm")
            }
            Button("Annuleren", role: .cancel) {}
        } message: { asked in
            explanation(of: asked)
        }
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { question != nil }, set: { if !$0 { question = nil } })
    }

    // MARK: Playback

    private var playback: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Afspelen")
                .font(.headline)
            TimingChoices(label: "Pauze tussen afleveringen in kindermodus", setting: .kidsPause, model: model)
            TimingChoices(label: "“Kijk je nog?” in kindermodus, na", setting: .kidsStillWatching, model: model)
            TimingChoices(label: "“Kijk je nog?” in gewone modus, na", setting: .normalStillWatching, model: model)
        }
    }

    // MARK: Account

    private var account: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.headline)
            Text("Afmelden gebeurt alleen op deze Apple TV.")
                .foregroundStyle(.secondary)
            Button("Afmelden") { question = .signOut }
                .accessibilityIdentifier("settings-sign-out")
        }
        .focusSection()
    }

    // MARK: Local data

    private var localData: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gegevens op deze Apple TV")
                .font(.headline)
            Text("Wat je vastzet, bewaart en zoekt staat alleen hier. Hoe ver je iets hebt gekeken weet NPO ook.")
                .foregroundStyle(.secondary)
            Button("Wis gewone modus") { question = .erase([.normal]) }
                .accessibilityIdentifier("settings-erase-normal")
            Button("Wis kindermodus") { question = .erase([.kids]) }
                .accessibilityIdentifier("settings-erase-kids")
            Button("Wis beide modi") { question = .erase([.normal, .kids]) }
                .accessibilityIdentifier("settings-erase-both")
            if model.erased != nil {
                Label("Gegevens gewist", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("settings-erased")
            }
        }
        .focusSection()
    }

    // MARK: What is asked

    private var title: LocalizedStringKey {
        switch question {
        case .erase(let modes) where modes.count > 1: "Gegevens van beide modi wissen?"
        case .erase(let modes) where modes.contains(.kids): "Gegevens van kindermodus wissen?"
        case .erase: "Gegevens van gewone modus wissen?"
        case .signOut, nil: "Afmelden?"
        }
    }

    /// Names what goes and what stays (FR-SET-04, FR-AUTH-04).
    private func explanation(of asked: Question) -> Text {
        switch asked {
        case .signOut:
            Self.sentences(["Deze Apple TV vergeet je inlog.",
                            "Hij blijft wel gekoppeld aan je NPO-account, tot je hem daar verwijdert.",
                            "Wat je hebt vastgezet, bekeken, bewaard en gezocht blijft op deze Apple TV staan."])
        case .erase(let modes) where modes.count > 1:
            Self.sentences([Self.erasing, Self.erasingAtNPO, "Dat geldt voor beide modi.", "Je blijft ingelogd."])
        case .erase:
            Self.sentences([Self.erasing,
                            Self.erasingAtNPO,
                            "De andere modus blijft zoals hij is.",
                            "Je blijft ingelogd."])
        }
    }

    private static let erasing: LocalizedStringKey =
        "Dit verwijdert van deze Apple TV wat is vastgezet, bekeken en bewaard, de kijkposities en de zoekgeschiedenis."

    /// What erasing does and does not reach at NPO (FR-SET-05).
    private static let erasingAtNPO: LocalizedStringKey =
        "Bij NPO gaat het uit ‘Kijk verder’, maar NPO onthoudt hoe ver je iets hebt gekeken."

    private static func sentences(_ keys: [LocalizedStringKey]) -> Text {
        keys.reduce(Text(verbatim: "")) { text, key in Text("\(text)\(Text(key)) ") }
    }
}

/// One timing: its name, and its choices side by side. The one in use is
/// marked with a symbol, not a colour alone (NFR-A11Y-04).
struct TimingChoices: View {
    let label: LocalizedStringKey
    let setting: Timings.Setting
    let model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
            HStack(spacing: 12) {
                ForEach(setting.choices, id: \.self) { value in
                    Button { model.choose(value, for: setting) } label: {
                        Label {
                            // Whole, on one line: a value cut in two is not
                            // a value.
                            Text(Self.words(for: value))
                                .fixedSize()
                        } icon: {
                            Image(systemName: "checkmark")
                                .opacity(model.timings[setting] == value ? 1 : 0)
                        }
                    }
                    .accessibilityAddTraits(model.timings[setting] == value ? .isSelected : [])
                    .accessibilityIdentifier("setting-\(setting.rawValue)-\(value)")
                }
            }
        }
        .focusSection()
    }

    /// A duration as the screen says it: none, seconds, minutes or hours.
    static func words(for seconds: Int) -> LocalizedStringKey {
        if seconds == 0 { return "Geen" }
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(Double(seconds) / 3600, format: .number.precision(.fractionLength(0...1))) uur"
    }
}

#if DEBUG
#Preview("Settings") {
    NavigationStack {
        SettingsView(model: .scripted())
    }
}

#Preview("Timing") {
    TimingChoices(label: "Pauze tussen afleveringen in kindermodus", setting: .kidsPause, model: .scripted())
}
#endif
