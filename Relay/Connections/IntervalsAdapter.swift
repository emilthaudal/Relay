//
//  IntervalsAdapter.swift
//  Relay
//
//  Adapter for Intervals.icu. HTTP Basic auth using athlete ID + API key.
//  Credentials stored in UserDefaults (placeholder — migrate to Keychain before shipping).
//

import Foundation

// MARK: - Placeholder credentials
private let INTERVALS_ATHLETE_ID_PLACEHOLDER = "INTERVALS_ATHLETE_ID_PLACEHOLDER"
private let INTERVALS_API_KEY_PLACEHOLDER    = "INTERVALS_API_KEY_PLACEHOLDER"

private let kIntervalsAthleteID = "relay.intervals.athleteID"
private let kIntervalsAPIKey    = "relay.intervals.apiKey"

actor IntervalsAdapter: ConnectionAdapter {

    let connectionType: ConnectionType = .intervals

    private let baseURL = URL(string: "https://intervals.icu/api/v1")!

    private var athleteID: String {
        get { UserDefaults.standard.string(forKey: kIntervalsAthleteID) ?? INTERVALS_ATHLETE_ID_PLACEHOLDER }
        set { UserDefaults.standard.set(newValue, forKey: kIntervalsAthleteID) }
    }
    private var apiKey: String {
        get { UserDefaults.standard.string(forKey: kIntervalsAPIKey) ?? INTERVALS_API_KEY_PLACEHOLDER }
        set { UserDefaults.standard.set(newValue, forKey: kIntervalsAPIKey) }
    }

    var isConnected: Bool {
        get async {
            let id  = UserDefaults.standard.string(forKey: kIntervalsAthleteID)
            let key = UserDefaults.standard.string(forKey: kIntervalsAPIKey)
            return id != nil && key != nil
        }
    }

    // MARK: - Auth

    /// Intervals uses HTTP Basic auth — "authenticating" just validates the credentials against the API.
    func authenticate() async throws {
        let request = makeRequest(path: "athlete/\(athleteID)")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AdapterError.authFailed("Intervals.icu credentials invalid")
        }
    }

    func disconnect() async {
        UserDefaults.standard.removeObject(forKey: kIntervalsAthleteID)
        UserDefaults.standard.removeObject(forKey: kIntervalsAPIKey)
    }

    // MARK: - Fetch

    func fetchWorkouts(since date: Date) async throws -> [NormalizedWorkout] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let oldest = formatter.string(from: date)

        var components = URLComponents(url: baseURL.appendingPathComponent("athlete/\(athleteID)/activities"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "oldest", value: oldest)
        ]

        var request = makeRequest(path: "athlete/\(athleteID)/activities")
        request.url = components.url

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let activities = try JSONDecoder().decode([IntervalsActivity].self, from: data)
        return activities.map { $0.toNormalized() }
    }

    // MARK: - Upload (stub)

    func upload(_ workout: NormalizedWorkout) async throws -> String {
        // TODO: Implement multipart FIT/TCX upload to POST /athlete/{id}/activities
        throw AdapterError.uploadFailed("Intervals.icu upload not yet implemented")
    }

    // MARK: - Helpers

    private func makeRequest(path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        let credentials = "API_KEY:\(apiKey)"
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
    let average_cadence: Double?
    let average_speed: Double?
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
            avgCadence: average_cadence,
            avgSpeed: average_speed,
            elevationGain: total_elevation_gain
        )
    }
}
