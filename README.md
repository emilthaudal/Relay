# Relay

Relay is a native iOS workout sync hub. It fetches workouts from multiple fitness platforms, deduplicates overlapping entries, and syncs any missing workouts to connections that don't have them yet.

## Connections

| Platform | Auth | Status |
|---|---|---|
| Apple HealthKit | HealthKit permissions | Available |
| Strava | OAuth2 | Available (placeholder credentials) |
| Intervals.icu | API key | Available (placeholder credentials) |
| Hammerhead Karoo | Via Strava | Indirect — see below |
| Zwift | Via Strava | Indirect |

**Hammerhead note:** Karoo natively syncs rides to Strava. If you have the Strava connection enabled in Relay, Karoo workouts will be covered automatically. A direct Hammerhead API integration is under investigation (see [Relay-rnr](https://github.com/emilthaudal/Relay/issues)).

## Requirements

- iOS 17.0+
- Xcode 26.0+ (the project targets iOS 26.2 and requires the Xcode 26 toolchain)
- An Apple Developer account (free tier works for local device builds)

## Getting Started

```sh
git clone https://github.com/emilthaudal/Relay.git
cd Relay
open Relay.xcodeproj
```

Select any iPhone simulator, press **Cmd+R**. The app will launch into the onboarding wizard.

### Strava setup

Strava credentials are placeholders. To enable real Strava sync:

1. Go to [strava.com/settings/api](https://www.strava.com/settings/api) and register a new API application.
2. Open `Relay/Connections/StravaAdapter.swift`.
3. Replace `STRAVA_CLIENT_ID_PLACEHOLDER` and `STRAVA_CLIENT_SECRET_PLACEHOLDER` with your real values.

> Credentials are currently stored in `UserDefaults`. Migration to Keychain is tracked in [Relay-omv](https://github.com/emilthaudal/Relay/issues).

### Intervals.icu setup

1. Log in at [intervals.icu](https://intervals.icu) and go to Settings → Developer → API Key.
2. Open `Relay/Connections/IntervalsAdapter.swift`.
3. Replace `INTERVALS_ATHLETE_ID_PLACEHOLDER` and `INTERVALS_API_KEY_PLACEHOLDER`.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a full technical walkthrough.

**Quick overview:**

```
ConnectionAdapter (protocol)
    ├── HealthKitAdapter
    ├── StravaAdapter
    └── IntervalsAdapter

SyncEngine
    ├── WorkoutMatcher   — clusters overlapping workouts across sources
    ├── WorkoutMerger    — merges fields using source priority rules
    └── SourcePriority   — per-sport-type priority ordering

SwiftData models
    ├── AppState         — singleton, onboarding flag, source priorities
    ├── WorkoutRecord    — persisted canonical workout
    └── SyncRecord       — sync state per connection per workout
```

## Project Structure

```
Relay/
├── Models/              SwiftData models (AppState, WorkoutRecord, SyncRecord, …)
├── Connections/         ConnectionAdapter protocol + one file per platform
├── Engine/              SyncEngine, WorkoutMatcher, WorkoutMerger, SourcePriority
├── Background/          BGAppRefreshTask wrapper (iOS only)
└── Views/
    ├── Main/            WorkoutListView, WorkoutDetailView, MainTabView
    ├── Onboarding/      5-step onboarding wizard
    └── Settings/        SettingsView, ConnectionsSettingsView, SourcePrioritySettingsView
```

## CI / CD

A GitHub Actions workflow runs on every push and pull request to `main`. It builds the project for testing against the iOS simulator.

> **Note:** The project targets iOS 26.2 and requires Xcode 26. GitHub-hosted macOS runners currently ship Xcode 16.x and will not compile this project until Xcode 26 reaches General Availability (expected WWDC 2026). The workflow is set up correctly and will go green automatically once the runner image is updated. To build and test today, run locally with Xcode 26.

To run tests locally:

```sh
xcodebuild test \
  -project Relay.xcodeproj \
  -scheme Relay \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Known Limitations

- Strava and Intervals upload (`uploadWorkout`) are stubs — they throw `AdapterError.uploadFailed`. Fetching works; writing back is future work.
- Credentials are stored in `UserDefaults`, not Keychain.
- `SyncEngine` does not yet persist merged workout clusters to SwiftData (upsert call is missing a `ModelContext`).

## Issue Tracking

This project uses [bd (beads)](https://github.com/anomalyco/beads) for issue tracking. The `.beads/` directory is committed to the repo.

```sh
bd ready    # see available work
bd show <id>
```
