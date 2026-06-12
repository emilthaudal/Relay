//
//  IntervalsAdapter.swift
//  Relay
//
//  Adapter for Intervals.icu. HTTP Basic auth using athlete ID + API key.
//  Credentials stored in Keychain.
//

import Foundation

private let kIntervalsAthleteID = "relay.intervals.athleteID"
private let kIntervalsAPIKey    = "relay.intervals.apiKey"

actor IntervalsAdapter: ConnectionAdapter {

    let connectionType: ConnectionType = .intervals

    private let baseURL = URL(string: "https://intervals.icu/api/v1")!

    private var athleteID: String? {
        KeychainHelper.get(forKey: kIntervalsAthleteID)
    }
    private var apiKey: String? {
        KeychainHelper.get(forKey: kIntervalsAPIKey)
    }

    var isConnected: Bool {
        get async {
            KeychainHelper.get(forKey: kIntervalsAthleteID) != nil &&
            KeychainHelper.get(forKey: kIntervalsAPIKey) != nil
        }
    }

    // MARK: - Credential management

    func setCredentials(athleteID: String, apiKey: String) {
        KeychainHelper.set(athleteID, forKey: kIntervalsAthleteID)
        KeychainHelper.set(apiKey, forKey: kIntervalsAPIKey)
    }

    // MARK: - Auth

    /// Validates stored credentials against the API.
    func authenticate() async throws {
        guard let id = athleteID else { throw AdapterError.authFailed("No athlete ID set") }
        let request = makeRequest(path: "athlete/\(id)")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AdapterError.authFailed("Intervals.icu credentials invalid")
        }
    }

    func disconnect() async {
        KeychainHelper.delete(forKey: kIntervalsAthleteID)
        KeychainHelper.delete(forKey: kIntervalsAPIKey)
    }

    // MARK: - Fetch

    func fetchWorkouts(since date: Date) async throws -> [NormalizedWorkout] {
        guard let id = athleteID else { throw AdapterError.authFailed("Not authenticated") }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let oldest = formatter.string(from: date)

        var components = URLComponents(url: baseURL.appendingPathComponent("athlete/\(id)/activities"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "oldest", value: oldest)
        ]

        var request = makeRequest(path: "athlete/\(id)/activities")
        request.url = components.url

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let activities = try JSONDecoder().decode([IntervalsActivity].self, from: data)
        return activities.map { $0.toNormalized() }
    }

    // MARK: - Upload (stub)

    func upload(_ workout: NormalizedWorkout) async throws -> String {
        throw AdapterError.uploadFailed("Intervals.icu upload not yet implemented")
    }

    // MARK: - Activity streams (per-second time-series)

    func fetchStreams(activityID: String, startDate: Date) async throws -> ActivityStreams {
        // Note: streams endpoint uses /activity/{id}/streams (no athlete prefix)
        let request = makeRequest(path: "activity/\(activityID)/streams")

        print("[IntervalsAdapter] Fetching streams for activity \(activityID)")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[IntervalsAdapter] Streams network error: \(error)")
            throw error
        }
        do {
            try validateResponse(response)
        } catch {
            print("[IntervalsAdapter] Streams HTTP error: \(error)")
            throw error
        }

        let items: [IntervalsStreamItem]
        do {
            items = try JSONDecoder().decode([IntervalsStreamItem].self, from: data)
        } catch {
            print("[IntervalsAdapter] Streams decode error: \(error)")
            throw error
        }

        // Build a lookup by stream type; skip streams marked allNull
        var streamMap: [String: [Double]] = [:]
        for item in items where !(item.allNull ?? false) {
            if let values = item.data {
                streamMap[item.type] = values
            }
        }

        let time = (streamMap["time"] ?? []).map { Int($0) }
        print("[IntervalsAdapter] Streams loaded: keys=\(streamMap.keys.sorted()), samples=\(time.count)")

        return ActivityStreams(
            startDate: startDate,
            time:      time,
            heartRate: streamMap["heartrate"].map { $0.map { Int($0) } },
            watts:     streamMap["watts"].map { $0.map { Int($0) } },
            cadence:   streamMap["cadence"].map { $0.map { Int($0) } },
            velocity:  streamMap["velocity_smooth"],
            altitude:  streamMap["altitude"]
        )
    }

    // MARK: - Helpers

    private func makeRequest(path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        let key = apiKey ?? ""
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

// Each element in the /activity/{id}/streams response array.
// `data` uses `try?` decoding so multi-dimensional streams (e.g. latlng) don't break parsing.
private struct IntervalsStreamItem: Decodable {
    let type: String
    let data: [Double]?
    let allNull: Bool?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.allNull = try c.decodeIfPresent(Bool.self, forKey: .allNull)
        self.data = try? c.decodeIfPresent([Double].self, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey { case type, data, allNull }
}

private struct IntervalsActivity: Decodable {
    let id: String
    let name: String?
    let type: String
    let start_date_local: String
    let elapsed_time: Int
    let distance: Double?
    let total_elevation_gain: Double?
    let average_heartrate: Double?
    let max_heartrate: Double?
    let average_watts: Double?
    let max_watts: Double?
    let normalized_power: Double?       // Intervals.icu NP field
    let average_cadence: Double?
    let average_speed: Double?
    let max_speed: Double?
    let trainer: Bool?
    let calories: Int?

    func toNormalized() -> NormalizedWorkout {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: start_date_local) ?? Date()

        return NormalizedWorkout(
            externalID: id,
            source: .intervals,
            startDate: start,
            duration: TimeInterval(elapsed_time),
            sportType: SportType(stravaType: type),
            name: name ?? SportType(stravaType: type).displayName,
            isTrainer: trainer ?? false,
            distance: distance,
            calories: calories,
            avgHeartRate: average_heartrate,
            maxHeartRate: max_heartrate,
            avgPower: average_watts,
            maxPower: max_watts,
            normalizedPower: normalized_power,
            avgCadence: average_cadence,
            avgSpeed: average_speed,
            maxSpeed: max_speed,
            elevationGain: total_elevation_gain
        )
    }
}
