# Relay

Relay is an iPhone app that copies your Intervals.icu workouts into Apple Health with their full detail: per-second heart rate, power, cadence and speed, distance, active energy, laps and the GPS route. It skips workouts Health already has, whichever app wrote them.

## Connections

| Platform | Auth | Direction |
|---|---|---|
| Intervals.icu | Athlete ID + API key, stored in the Keychain | Read |
| Apple Health | HealthKit permissions | Read (to avoid duplicates) and write |

Karoo and Zwift rides reach Relay through Intervals.icu. Connect them to Intervals.icu directly: activities Intervals.icu imported from Strava are withheld by its API, and Relay skips them and says how many it skipped.

## Requirements

- iPhone on iOS 26.2+
- Xcode 26+
- An Apple Developer account (the free tier works for device builds; TestFlight needs the paid program)

## Getting Started

```sh
git clone https://github.com/emilthaudal/Relay.git
cd Relay
open Relay.xcodeproj
```

Select any iPhone simulator, press **Cmd+R**. The app will launch into the onboarding wizard.

### Intervals.icu setup

In the app: Settings → Manage Connections → Intervals.icu, then enter your athlete ID and API key (intervals.icu → Settings → Developer).

For Debug builds you can skip that: copy `Relay/Secrets.xcconfig.template` to `Relay/Secrets.xcconfig` and fill it in. Debug builds seed the Keychain from it on launch. Release builds never contain it.

### Comparing with RunGap or another app

Debug builds have Settings → Developer → Health Inspector. Pick a day, select the copies of one activity written by different apps (for example Relay and RunGap), and compare what Health holds for each:
- points, spacing, sum or mean, and min–max per data type,
- laps, route points, metadata and workout statistics.
Values that differ are highlighted. **Export JSON** shares the full report.

Use a test device, or delete one copy between runs: Relay skips a workout that's already in Health.

### Background sync

Relay syncs when opened (if the last sync is more than 15 minutes old) and in the background through `BGAppRefreshTask` (`emtb.Relay.refresh`, declared in `Config/Relay-Info.plist`). iOS decides when background refresh runs.

**Sync Historical Workouts** runs as a `BGContinuedProcessingTask` (`emtb.Relay.historical.<uuid>`, permitted as `emtb.Relay.historical.*`). It keeps running after you leave the app, and iOS shows its progress as a Live Activity. If iOS won't start the task right away, the sync runs in the app instead. To trigger it from the debugger, pause the app and run:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"emtb.Relay.refresh"]
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a full technical walkthrough.

**Quick overview:**

```
ConnectionAdapter (protocol)
    ├── HealthKitAdapter — reads Health workouts; writes workouts with HealthKitSeries
    └── IntervalsAdapter — reads activities and per-second streams

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
├── Background/          BGAppRefreshTask registration and handler
├── Debug/               Health Inspector (Debug builds only)
└── Views/
    ├── Main/            WorkoutListView, WorkoutDetailView, MainTabView
    ├── Onboarding/      5-step onboarding wizard
    └── Settings/        SettingsView, ConnectionsSettingsView, SourcePrioritySettingsView
```

## CI / CD

A GitHub Actions workflow runs on every push and pull request to `main`. It builds the project for testing against the iOS simulator.

To run tests locally:

```sh
xcodebuild test \
  -project Relay.xcodeproj \
  -scheme Relay \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:RelayTests
```

`RelayUITests` has no tests yet, and its empty bundle fails to load, hence `-only-testing`.

## Known Limitations

- Relay writes only to Apple Health. Intervals.icu is read-only.
- Running cadence, running dynamics (stride, oscillation, ground contact), swim strokes and weather aren't written yet. Compare with the Health Inspector to see what other apps write.

## Issue Tracking

Issues are tracked in Linear under the **Relay V1** initiative.
