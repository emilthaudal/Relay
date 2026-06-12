//
//  ActivityStreams.swift
//  Relay
//
//  Time-series data fetched from Strava or Intervals.icu for a single activity.
//  Parallel arrays indexed by position; `time[i]` is seconds after `startDate`.
//

import Foundation

struct ActivityStreams {
    let startDate: Date
    let time: [Int]          // seconds offset from startDate
    let heartRate: [Int]?    // bpm
    let watts: [Int]?        // power in watts
    let cadence: [Int]?      // rpm
    let velocity: [Double]?  // m/s
    let altitude: [Double]?  // meters
}
