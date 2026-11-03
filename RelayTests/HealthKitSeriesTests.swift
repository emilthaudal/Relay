//
//  HealthKitSeriesTests.swift
//  RelayTests
//

import Testing
import Foundation
import HealthKit
@testable import Relay

@Suite("HealthKitSeries")
struct HealthKitSeriesTests {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func series(sport: SportType, isTrainer: Bool = false, seconds: Int = 60,
                        configure: (inout ActivityStreams) -> Void) -> HealthKitSeries {
        var streams = ActivityStreams(startDate: start, time: Array(0..<seconds))
        configure(&streams)
        let workout = NormalizedWorkout(externalID: "i1", source: .intervals, startDate: start,
                                        duration: TimeInterval(seconds), sportType: sport, name: "Test",
                                        isTrainer: isTrainer)
        return HealthKitSeries(streams: streams, workout: workout,
                               workoutEnd: start.addingTimeInterval(TimeInterval(seconds)))
    }

    private func quantities(_ samples: [HKSample], _ id: HKQuantityTypeIdentifier, unit: HKUnit) -> [Double] {
        samples.compactMap { $0 as? HKQuantitySample }
            .filter { $0.quantityType == HKQuantityType(id) }
            .map { $0.quantity.doubleValue(for: unit) }
    }

    @Test("run cadence counts one foot, so a minute at 80 is 160 steps")
    func runSteps() {
        let s = series(sport: .run, seconds: 61) { $0.cadence = Array(repeating: 80, count: 61) }
        let steps = quantities(s.samples(), .stepCount, unit: .count())
        #expect(steps.reduce(0, +) == 160)
    }

    @Test("ride cadence writes no steps")
    func rideNoSteps() {
        let s = series(sport: .ride) { $0.cadence = Array(repeating: 90, count: 60) }
        #expect(quantities(s.samples(), .stepCount, unit: .count()).isEmpty)
        #expect(!quantities(s.samples(), .cyclingCadence, unit: .count().unitDivided(by: .minute())).isEmpty)
    }

    @Test("running form converts from Intervals.icu units and drops readings out of range")
    func runningForm() {
        let s = series(sport: .run, seconds: 3) {
            $0.groundContactTime = [258.2, nil, 9999]     // ms
            $0.verticalOscillation = [87.1, 106.9, nil]   // mm
            $0.stepLength = [911.2, 1240, 5]              // mm
        }
        let samples = s.samples()
        #expect(quantities(samples, .runningGroundContactTime, unit: .secondUnit(with: .milli)) == [258.2])
        #expect(quantities(samples, .runningVerticalOscillation, unit: .meterUnit(with: .centi)).map { ($0 * 100).rounded() / 100 } == [8.71, 10.69])
        #expect(quantities(samples, .runningStrideLength, unit: .meter()).map { ($0 * 1000).rounded() / 1000 } == [0.911, 1.24])
    }

    @Test("running form is never written for rides")
    func noRunningFormOnRides() {
        let s = series(sport: .ride, seconds: 2) { $0.groundContactTime = [250, 250] }
        #expect(quantities(s.samples(), .runningGroundContactTime, unit: .secondUnit(with: .milli)).isEmpty)
    }

    @Test("outdoor temperature becomes the weather temperature")
    func outdoorTemperature() throws {
        let s = series(sport: .ride, seconds: 3) { $0.temperature = [14, nil, 16] }
        let quantity = try #require(s.metadata()[HKMetadataKeyWeatherTemperature] as? HKQuantity)
        #expect(quantity.doubleValue(for: .degreeCelsius()) == 15)
    }

    @Test("indoor temperature is the room, not the weather")
    func indoorTemperature() {
        let s = series(sport: .virtualRide, isTrainer: true, seconds: 3) { $0.temperature = [20, 21, 22] }
        #expect(s.metadata()[HKMetadataKeyWeatherTemperature] == nil)
    }

    @Test("indoor rides get no route, even with coordinates")
    func indoorNoRoute() {
        let s = series(sport: .virtualRide, isTrainer: true, seconds: 2) {
            $0.latitude = [-11.6, -11.6]
            $0.longitude = [166.9, 166.9]
        }
        #expect(s.locations().isEmpty)
    }
}
