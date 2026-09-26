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
    var cadence: [Double?]? = nil     // rpm
    var velocity: [Double?]? = nil    // m/s
    var altitude: [Double?]? = nil    // meters
    var distance: [Double?]? = nil    // cumulative meters
    var latitude: [Double?]? = nil
    var longitude: [Double?]? = nil
    var laps: [Lap] = []
}
