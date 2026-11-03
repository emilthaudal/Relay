//
//  ActivityStreams.swift
//  Relay
//
//  Time-series data fetched from Intervals.icu for a single activity.
//  Parallel arrays indexed by position; `time[i]` is seconds after `startDate`.
//  Elements are nil where the recording device dropped a reading.
//

import Foundation

struct ActivityStreams {
    struct Lap {
        let start: Int      // seconds offset from startDate
        let end: Int
    }

    let startDate: Date
    let time: [Int]
    var heartRate: [Double?]? = nil   // bpm
    var watts: [Double?]? = nil       // watts
    var cadence: [Double?]? = nil     // rpm; for runs and walks, steps of one foot per minute
    var velocity: [Double?]? = nil    // m/s
    var altitude: [Double?]? = nil    // meters
    var distance: [Double?]? = nil    // cumulative meters
    var latitude: [Double?]? = nil
    var longitude: [Double?]? = nil
    var temperature: [Double?]? = nil          // °C, from the recording device
    var groundContactTime: [Double?]? = nil    // ms (Intervals.icu `stance_time`)
    var verticalOscillation: [Double?]? = nil  // mm
    var stepLength: [Double?]? = nil           // mm
    var laps: [Lap] = []
}
