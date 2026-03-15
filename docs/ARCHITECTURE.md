# Architecture

## Overview

Relay is built around a simple pipeline: **fetch → match → merge → sync**. Each integration is a self-contained `ConnectionAdapter`. A central `SyncEngine` orchestrates the pipeline using those adapters.

```
┌──────────────────────────────────────────────────────┐
│                      SyncEngine                      │
│                                                      │
│  ┌──────────┐  fetch   ┌──────────────────────────┐ │
│  │ Adapters │ ──────→  │     WorkoutMatcher       │ │
│  │  HK      │          │  group overlapping sets  │ │
│  │  Strava  │          └────────────┬─────────────┘ │
│  │  Intervals│                      │ clusters       │
│  └──────────┘          ┌────────────▼─────────────┐ │
│                        │     WorkoutMerger        │ │
│                        │  merge fields + priority │ │
│                        └────────────┬─────────────┘ │
│                                     │ NormalizedWorkout│
│                        ┌────────────▼─────────────┐ │
│                        │     Upsert to SwiftData  │ │
│                        │  WorkoutRecord + SyncRecords│ │
│                        └──────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## ConnectionAdapter Protocol

Every integration implements this protocol (`Relay/Connections/ConnectionAdapter.swift`):

```swift
protocol ConnectionAdapter {
    var connectionType: ConnectionType { get }
    func isConnected() async -> Bool
    func fetchWorkouts(since: Date) async throws -> [NormalizedWorkout]
    func uploadWorkout(_ workout: NormalizedWorkout) async throws
}
```

To add a new connection:
1. Add a case to `ConnectionType` enum.
2. Create `Relay/Connections/YourAdapter.swift` implementing `ConnectionAdapter`.
3. Register the adapter in `SyncEngine.adapters`.
4. Add UI in `ConnectionsSettingsView` and `OnboardingAddConnectionsView`.

### AdapterError

All adapters throw `AdapterError` (defined in `Relay/Connections/AdapterError.swift`):

```swift
enum AdapterError: Error {
    case notConnected
    case authFailed
    case networkError(Error)
    case decodingError(Error)
    case uploadFailed
}
```

---

## Workout Matching

`WorkoutMatcher` (`Relay/Engine/WorkoutMatcher.swift`) clusters workouts from multiple sources that represent the same real-world activity.

**Match criteria (all must be true):**

| Field | Tolerance |
|---|---|
| Start timestamp | ± 60 seconds |
| Duration | ± 2 minutes (120 seconds) |
| Sport type | Compatible (same type, or mapped equivalents) |

The matcher uses a greedy single-pass algorithm: it iterates over workouts sorted by start date and merges any workout within tolerance into the current cluster. Workouts that don't match any existing cluster start a new one.

**Sport type compatibility** is defined in `SportType.isCompatible(with:)` and covers common equivalences (e.g. `.virtualRide` ↔ `.ride`).

---

## Workout Merging

`WorkoutMerger` (`Relay/Engine/WorkoutMerger.swift`) takes a cluster (group of matching workouts from different sources) and produces a single `NormalizedWorkout`.

**Merge strategy:**

1. For each field (name, distance, heartRate, calories, etc.), collect all non-nil values from the cluster.
2. Use `SourcePriority` to rank which source should win on conflict.
3. The highest-priority source's value is used; lower-priority values fill in nil fields.

**Source priority** is configured per sport type in `AppState` and defaults to the values defined in `SourcePriority.swift`:

```swift
.virtualRide:  [.strava, .healthKit, .intervals]
.ride:         [.strava, .healthKit, .intervals]
.run:          [.healthKit, .strava, .intervals]
.walk, .hike:  [.healthKit, .strava]
.swim:         [.healthKit, .strava, .intervals]
.workout:      [.healthKit, .strava]
```

---

## SwiftData Models

All models are in `Relay/Models/` and decorated with `@Model`.

### AppState

Singleton. Persisted across launches.

| Property | Type | Description |
|---|---|---|
| `hasCompletedOnboarding` | `Bool` | Whether the wizard has been dismissed |
| `lastSyncDate` | `Date?` | Timestamp of most recent successful sync |
| `sourcePriorities` | `[String: [String]]` | Per-sport source priority (serialised as raw strings) |
| `connectedTypes` | `[String]` | Raw values of connected `ConnectionType`s |

### WorkoutRecord

One row per unique workout after deduplication.

| Property | Type | Description |
|---|---|---|
| `id` | `UUID` | Stable local ID |
| `startDate` | `Date` | Workout start |
| `duration` | `TimeInterval` | Seconds |
| `sportType` | `String` | `SportType` raw value |
| `name` | `String` | Display name |
| `syncRecords` | `[SyncRecord]` | One per connection |

### SyncRecord

Tracks the state of one workout on one connection.

| Property | Type | Description |
|---|---|---|
| `connectionType` | `String` | `ConnectionType` raw value |
| `externalID` | `String` | Platform-native workout ID |
| `state` | `String` | `SyncState` raw value |
| `isPrimarySource` | `Bool` | True if this connection originated the workout |

### SyncState

```swift
enum SyncState: String {
    case pending   // not yet synced to this connection
    case synced    // successfully uploaded
    case failed    // last upload attempt failed
    case uploading // in progress
}
```

---

## SyncEngine

`SyncEngine` (`Relay/Engine/SyncEngine.swift`) is a stateless actor. Call `sync(appState:)` to trigger a full sync cycle.

```swift
func sync(appState: AppState) async
```

**Flow:**

1. Build the list of active adapters from `appState.connectedTypes`.
2. Determine `since` date (last sync or 30 days ago as fallback).
3. Fetch from all adapters concurrently (`async let` / `TaskGroup`).
4. Pass all fetched workouts to `WorkoutMatcher.cluster(_:)`.
5. For each cluster, call `WorkoutMerger.merge(_:priorities:)`.
6. Upsert merged workouts into SwiftData via `upsert(cluster:appState:into:)`.
7. For each connection missing a workout, call `adapter.uploadWorkout(_:)`.
8. Update `appState.lastSyncDate`.

> **Known gap:** Step 6 (upsert) requires a `ModelContext` which is only available in a view or a background task that has one explicitly. The current `performSync()` call path does not pass a context. This is tracked as a known limitation.

---

## Background Sync

`BackgroundSyncTask` (`Relay/Background/BackgroundSyncTask.swift`, iOS only) registers two sync triggers:

| Trigger | Frequency | Notes |
|---|---|---|
| `BGAppRefreshTask` | ~15–30 min | System-scheduled, identifier `com.relay.backgroundSync` |
| `HKObserverQuery` | Near-realtime | Fires when HealthKit records a new workout |

Both triggers call `SyncEngine.sync(appState:)`.

**Setup:** `BackgroundSyncTask.register()` must be called at app launch (done in `RelayApp.swift`). The `BGTaskSchedulerPermittedIdentifiers` key must list `com.relay.backgroundSync` in `Info.plist` (already present).

---

## Onboarding Flow

5-step wizard, shown once on first launch (gated by `AppState.hasCompletedOnboarding`):

```
OnboardingWelcomeView
    → OnboardingHealthKitView      (requests HK permissions)
    → OnboardingAddConnectionsView (connect Strava / Intervals)
    → OnboardingSourcePriorityView (reorder per-sport priorities, skippable)
    → OnboardingDoneView           (sets hasCompletedOnboarding = true)
```

All steps are re-accessible from **Settings → Connections** and **Settings → Source Priority**.

---

## Adding a New Adapter — Checklist

- [ ] Add case to `ConnectionType` enum (`Relay/Models/ConnectionType.swift`)
- [ ] Add sport type mappings if needed (`Relay/Models/SportType.swift`)
- [ ] Create `Relay/Connections/YourServiceAdapter.swift` implementing `ConnectionAdapter`
- [ ] Add credential storage (use Keychain, not UserDefaults)
- [ ] Register adapter in `SyncEngine` (`adapters` computed property)
- [ ] Add connection card to `OnboardingAddConnectionsView`
- [ ] Add connection row to `ConnectionsSettingsView`
- [ ] Add source priority defaults to `SourcePriority.swift`
- [ ] Add a Beads task for the integration work (`bd create`)
