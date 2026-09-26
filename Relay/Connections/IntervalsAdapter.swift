//
//  IntervalsAdapter.swift
//  Relay
//
//  Adapter for Intervals.icu. HTTP Basic auth using athlete ID + API key.
//  Credentials stored in Keychain.
//

@preconcurrency import Foundation

private enum K {
    static let athleteID = "relay.intervals.athleteID"
    static let apiKey    = "relay.intervals.apiKey"
}

actor IntervalsAdapter: ConnectionAdapter {

    let connectionType: ConnectionType = .intervals

    private let baseURL = URL(string: "https://intervals.icu/api/v1")!

    private var athleteID: String? {
        get async { await MainActor.run { KeychainHelper.get(forKey: K.athleteID) } }
    }
    private var apiKey: String? {
        get async { await MainActor.run { KeychainHelper.get(forKey: K.apiKey) } }
    }

    var isConnected: Bool {
        get async {
            await MainActor.run {
                KeychainHelper.get(forKey: K.athleteID) != nil &&
                KeychainHelper.get(forKey: K.apiKey) != nil
            }
        }
    }

    // MARK: - Credential management

    func setCredentials(athleteID: String, apiKey: String) async {
        await MainActor.run {
            KeychainHelper.set(athleteID, forKey: K.athleteID)
            KeychainHelper.set(apiKey, forKey: K.apiKey)
        }
    }

    #if DEBUG
    /// Seeds the Keychain from the Secrets.xcconfig values baked into Debug builds.
    @MainActor
    static func seedCredentialsFromBundleIfNeeded() {
        guard KeychainHelper.get(forKey: K.apiKey) == nil,
              let id = Bundle.main.object(forInfoDictionaryKey: "IntervalsAthleteID") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "IntervalsAPIKey") as? String,
              !id.isEmpty, !key.isEmpty
        else { return }
        KeychainHelper.set(id, forKey: K.athleteID)
        KeychainHelper.set(key, forKey: K.apiKey)
    }
    #endif

    // MARK: - Auth

    /// Validates stored credentials against the API.
    func authenticate() async throws {
        guard let id = await athleteID else { throw AdapterError.authFailed("No athlete ID set") }
        let request = await makeRequest(path: "athlete/\(id)")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AdapterError.authFailed("Intervals.icu credentials invalid")
        }
    }

    func disconnect() async {
        await MainActor.run {
            KeychainHelper.delete(forKey: K.athleteID)
            KeychainHelper.delete(forKey: K.apiKey)
        }
    }

    // MARK: - Fetch

    func fetchWorkouts(since date: Date) async throws -> [NormalizedWorkout] {
        guard let id = await athleteID else { throw AdapterError.authFailed("Not authenticated") }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var request = await makeRequest(path: "athlete/\(id)/activities")
        request.url = request.url?.appending(queryItems: [
            URLQueryItem(name: "oldest", value: formatter.string(from: date))
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let activities = try JSONDecoder().decode([IntervalsActivity].self, from: data)
        let athleteTimeZone = await fetchAthleteTimeZone(athleteID: id)
        return activities.compactMap { $0.toNormalized(athleteTimeZone: athleteTimeZone) }
    }

    private func fetchAthleteTimeZone(athleteID: String) async -> TimeZone? {
        let request = await makeRequest(path: "athlete/\(athleteID)")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (try? validateResponse(response)) != nil,
              let athlete = try? JSONDecoder().decode(IntervalsAthlete.self, from: data),
              let identifier = athlete.timezone
        else { return nil }
        return TimeZone(identifier: identifier)
    }

    // MARK: - Upload

    func upload(_ workout: NormalizedWorkout) async throws -> String {
        throw AdapterError.uploadFailed("Intervals.icu upload not yet implemented")
    }

    // MARK: - Activity streams (per-second time-series)

    func fetchStreams(activityID: String, startDate: Date) async throws -> ActivityStreams {
        var request = await makeRequest(path: "activity/\(activityID)/streams")
        request.url = request.url?.appending(queryItems: [
            URLQueryItem(name: "types", value: "time,heartrate,watts,cadence,velocity_smooth,altitude,distance,latlng")
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        var streams = try Self.parseStreams(data, startDate: startDate)
        streams.laps = (try? await fetchLaps(activityID: activityID)) ?? []
        print("[IntervalsAdapter] Streams for \(activityID): \(streams.time.count) samples, \(streams.laps.count) laps")
        return streams
    }

    private func fetchLaps(activityID: String) async throws -> [ActivityStreams.Lap] {
        var request = await makeRequest(path: "activity/\(activityID)")
        request.url = request.url?.appending(queryItems: [URLQueryItem(name: "intervals", value: "true")])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        return try JSONDecoder().decode(IntervalsActivityDetail.self, from: data).laps
    }

    nonisolated static func parseStreams(_ data: Data, startDate: Date) throws -> ActivityStreams {
        let items = try JSONDecoder().decode([IntervalsStreamItem].self, from: data)
        var streamMap: [String: IntervalsStreamItem] = [:]
        for item in items where !(item.allNull ?? false) {
            streamMap[item.type] = item
        }

        let time = (streamMap["time"]?.data ?? []).map { Int($0 ?? 0) }
        return ActivityStreams(
            startDate: startDate,
            time:      time,
            heartRate: streamMap["heartrate"]?.data,
            watts:     streamMap["watts"]?.data,
            cadence:   streamMap["cadence"]?.data,
            velocity:  streamMap["velocity_smooth"]?.data,
            altitude:  streamMap["altitude"]?.data,
            distance:  streamMap["distance"]?.data,
            latitude:  streamMap["latlng"]?.data,
            longitude: streamMap["latlng"]?.data2
        )
    }

    // MARK: - Helpers

    private func makeRequest(path: String) async -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        let key = await apiKey ?? ""
        let credentials = "API_KEY:\(key)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AdapterError.networkError("HTTP \(code)")
        }
    }
}

// MARK: - Intervals.icu API models

nonisolated private struct IntervalsAthlete: Decodable {
    let timezone: String?
}

// `latlng` carries latitudes in `data` and longitudes in `data2`.
nonisolated private struct IntervalsStreamItem: Decodable {
    let type: String
    let data: [Double?]?
    let data2: [Double?]?
    let allNull: Bool?
}

nonisolated struct IntervalsActivityDetail: Decodable {
    struct Interval: Decodable {
        let start_time: Int?
        let end_time: Int?
    }

    let icu_intervals: [Interval]?
    let icu_lap_count: Int?

    /// Intervals only mirror device laps when their count matches the recorded lap count;
    /// otherwise they are auto-detected efforts.
    var laps: [ActivityStreams.Lap] {
        guard let intervals = icu_intervals, intervals.count > 1, intervals.count == icu_lap_count else { return [] }
        return intervals.compactMap { interval in
            guard let start = interval.start_time, let end = interval.end_time, end > start else { return nil }
            return ActivityStreams.Lap(start: start, end: end)
        }
    }
}

nonisolated struct IntervalsActivity: Decodable {
    let id: String
    let name: String?
    let type: String?
    let source: String?
    let device_name: String?
    let start_date: String?
    let start_date_local: String?
    let elapsed_time: Int?
    let distance: Double?
    let total_elevation_gain: Double?
    let average_heartrate: Double?
    let max_heartrate: Double?
    let icu_average_watts: Double?
    let max_watts: Double?
    let icu_weighted_avg_watts: Double?
    let average_cadence: Double?
    let average_speed: Double?
    let max_speed: Double?
    let trainer: Bool?
    let calories: Double?
    let icu_joules: Double?
    let _note: String?

    /// Returns nil for activities that can't or shouldn't be imported: Strava-sourced stubs
    /// (the API withholds their data) and Apple Watch recordings that already live in Health.
    nonisolated func toNormalized(athleteTimeZone: TimeZone?) -> NormalizedWorkout? {
        guard _note == nil, source != "STRAVA",
              let type, let elapsed_time, let start_date,
              let start = ISO8601DateFormatter().date(from: start_date)
        else { return nil }
        if let device_name, device_name.hasPrefix("Watch") { return nil }

        // Prefer Intervals.icu's own calorie estimate; fall back to mechanical kJ→dietary kcal
        // (~23% metabolic efficiency: joules / 4184 / 0.23 ≈ joules / 962)
        let kcal: Int? = calories.map { Int($0) } ?? icu_joules.map { Int($0 / 962) }
        let sport = SportType(intervalsType: type)

        return NormalizedWorkout(
            externalID: id,
            source: .intervals,
            startDate: start,
            duration: TimeInterval(elapsed_time),
            sportType: sport,
            name: name ?? sport.displayName,
            isTrainer: trainer ?? (sport == .virtualRide || sport == .virtualRun),
            timeZone: timeZone(start: start, athleteTimeZone: athleteTimeZone),
            deviceName: device_name,
            distance: distance,
            calories: kcal,
            avgHeartRate: average_heartrate,
            maxHeartRate: max_heartrate,
            avgPower: icu_average_watts,
            maxPower: max_watts,
            normalizedPower: icu_weighted_avg_watts,
            avgCadence: average_cadence,
            avgSpeed: average_speed,
            maxSpeed: max_speed,
            elevationGain: total_elevation_gain
        )
    }

    /// The local offset is `start_date_local - start_date`; the athlete's named zone is used
    /// when it agrees with that offset so DST-aware names end up in Health.
    private nonisolated func timeZone(start: Date, athleteTimeZone: TimeZone?) -> TimeZone? {
        guard let start_date_local else { return athleteTimeZone }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let localAsUTC = df.date(from: start_date_local) else { return athleteTimeZone }
        let offset = Int(localAsUTC.timeIntervalSince(start).rounded())
        if let athleteTimeZone, athleteTimeZone.secondsFromGMT(for: start) == offset {
            return athleteTimeZone
        }
        return TimeZone(secondsFromGMT: offset)
    }
}
