//
//  IntervalsActivityTests.swift
//  RelayTests
//

import Testing
import Foundation
@testable import Relay

@Suite("IntervalsActivity")
struct IntervalsActivityTests {

    private func decode(_ json: String) throws -> IntervalsActivity {
        try JSONDecoder().decode(IntervalsActivity.self, from: Data(json.utf8))
    }

    @Test("a Strava-imported stub is skipped and counted as one")
    func stravaStub() throws {
        // Shape of what the API returns for an activity Strava imported.
        let activity = try decode("""
        {"id": "i1", "source": "STRAVA", "type": null, "elapsed_time": null,
         "start_date": "2026-10-01T06:00:00Z",
         "_note": "STRAVA activities are not available via the API"}
        """)
        #expect(activity.isStravaStub)
        #expect(activity.toNormalized(athleteTimeZone: nil) == nil)
    }

    @Test("a note alone marks a stub, even without a source")
    func noteOnly() throws {
        let activity = try decode("""
        {"id": "i2", "_note": "not available via the API"}
        """)
        #expect(activity.isStravaStub)
    }

    @Test("a device upload is imported and not counted as a stub")
    func deviceUpload() throws {
        let activity = try decode("""
        {"id": "i3", "source": "GARMIN_CONNECT", "type": "Ride", "elapsed_time": 3600,
         "start_date": "2026-10-01T06:00:00Z", "start_date_local": "2026-10-01T08:00:00",
         "device_name": "Karoo 3", "distance": 30000}
        """)
        #expect(!activity.isStravaStub)
        let workout = try #require(activity.toNormalized(athleteTimeZone: nil))
        #expect(workout.externalID == "i3")
        #expect(workout.duration == 3600)
        #expect(workout.timeZone?.secondsFromGMT() == 7200)
    }

    @Test("an Apple Watch recording is skipped because it already lives in Health, but isn't a Strava stub")
    func appleWatch() throws {
        let activity = try decode("""
        {"id": "i4", "source": "OAUTH_CLIENT", "type": "Run", "elapsed_time": 1800,
         "start_date": "2026-10-01T06:00:00Z", "device_name": "Watch7,1"}
        """)
        #expect(!activity.isStravaStub)
        #expect(activity.toNormalized(athleteTimeZone: nil) == nil)
    }
}
