# Verder Kijker

![Verder Kijker app icon](docs/branding/verder-kijker-icon.png)

A Dutch-language Apple TV app for watching NPO with an NPO Plus account. 

Verder Kijker is built for deliberate watching: choosing what you want to see and keeping it within reach. It brings together pinned series, recently watched programmes, and films or episodes saved for later, with search, resuming playback, autoplay, and separate normal and kids modes. Small but meaningful quality-of-life and performance improvements make watching more comfortable, including responsive search that lets you keep typing while results load.

This is an independent project, not an official NPO app. An NPO Plus subscription is required.

## Run the app

You need macOS, Xcode with the tvOS 26.2 SDK or newer, and an Apple TV.

1. Open `NPO light.xcodeproj` in Xcode.
2. Select the shared **NPO light** scheme and a tvOS destination.
3. Select your own signing team in the app target.
4. Build and run. Follow the on-screen sign-in instructions with your NPO Plus account.

The Xcode project, scheme, source directories, and bundle identifier retain their original technical names. The installed app is called **Verder Kijker**.

Debug simulator builds use a generated test card for playback, with the real catalogue and local stores around it. Protected NPO playback and the FairPlay licence exchange require a physical Apple TV; see [ADR 0019](docs/adr/0019-play-a-generated-video-where-fairplay-cannot-run.md).

## Development

The app uses SwiftUI, SwiftData, and Swift 5 language mode. Screen models receive injected dependencies; the NPO backend sits behind a single boundary. Local lists and recent playback positions live in bounded UserDefaults storage, with additional positions in SwiftData under Caches.

Read [AGENTS.md](AGENTS.md) before changing the code. Behaviour is specified in the [requirements](docs/requirements/README.md), and architectural decisions are recorded in [ADRs](docs/adr/README.md).

Run the repository checks:

```sh
./scripts/lint.sh
./scripts/build.sh
./scripts/test.sh
./scripts/requirements-coverage.sh
```

Builds and tests require Xcode. SwiftLint is strict and compiler warnings are errors. Unit tests use Swift Testing; UI tests use XCTest. Tests name the requirement identifiers they cover.

## Interactive wireframe

The browser wireframe illustrates the requirements with example data:

```sh
./scripts/build-wireframe.sh
python3 -m http.server -d build/wireframe 8000
```

Open [localhost:8000](http://localhost:8000). See the [wireframe guide](wireframe/README.md) for remote-style controls and test scenarios.

## App icon

The orange-and-white binoculars mark connects the name's wordplay with NPO-inspired geometric broadcast styling. The [original artwork and generation prompt](docs/branding/README.md) are kept with the project. The production assets live in `NPO light/Assets.xcassets/App Icon & Top Shelf Image.brandassets`.
