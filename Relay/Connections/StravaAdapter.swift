//
//  StravaAdapter.swift
//  Relay
//
//  OAuth2 adapter for Strava. Uses ASWebAuthenticationSession for the auth flow.
//  Tokens stored in UserDefaults (placeholder — migrate to Keychain before shipping).
//  Polling only (no webhook backend). Rate limit: 200/15min, 2000/day.
//

import Foundation
#if os(iOS)
import AuthenticationServices
#endif

// MARK: - Placeholder credentials (register at https://www.strava.com/settings/api)
private let STRAVA_CLIENT_ID_PLACEHOLDER     = "STRAVA_CLIENT_ID_PLACEHOLDER"
private let STRAVA_CLIENT_SECRET_PLACEHOLDER = "STRAVA_CLIENT_SECRET_PLACEHOLDER"

private let kStravaAccessToken  = "relay.strava.accessToken"
private let kStravaRefreshToken = "relay.strava.refreshToken"
private let kStravaTokenExpiry  = "relay.strava.tokenExpiry"

actor StravaAdapter: ConnectionAdapter {

    let connectionType: ConnectionType = .strava

    private let baseURL = URL(string: "https://www.strava.com/api/v3")!
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: kStravaAccessToken) }
        set { UserDefaults.standard.set(newValue, forKey: kStravaAccessToken) }
    }
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: kStravaRefreshToken) }
        set { UserDefaults.standard.set(newValue, forKey: kStravaRefreshToken) }
    }
    private var tokenExpiry: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: kStravaTokenExpiry)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: kStravaTokenExpiry) }
    }

    // MARK: - Auth state

    var isConnected: Bool {
        get async { accessToken != nil }
    }

    func authenticate() async throws {
        #if os(iOS)
        let authCode = try await presentOAuthWebView()
        try await exchangeCodeForToken(authCode)
        #else
        throw AdapterError.unavailable("Strava OAuth is only available on iOS")
        #endif
    }

    func disconnect() async {
        UserDefaults.standard.removeObject(forKey: kStravaAccessToken)
        UserDefaults.standard.removeObject(forKey: kStravaRefreshToken)
        UserDefaults.standard.removeObject(forKey: kStravaTokenExpiry)
    }

    // MARK: - Fetch

    func fetchWorkouts(since date: Date) async throws -> [NormalizedWorkout] {
        try await refreshIfNeeded()
        guard let token = accessToken else { throw AdapterError.authFailed("Not authenticated") }

        let after = Int(date.timeIntervalSince1970)
        var components = URLComponents(url: baseURL.appendingPathComponent("athlete/activities"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "after", value: "\(after)"),
            URLQueryItem(name: "per_page", value: "100")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let activities = try JSONDecoder().decode([StravaActivity].self, from: data)
        return activities.map { $0.toNormalized() }
    }

    // MARK: - Upload (stub — full GPX/FIT upload is complex; returns placeholder)

    func upload(_ workout: NormalizedWorkout) async throws -> String {
        // TODO: Implement multipart GPX upload via POST /uploads
        throw AdapterError.uploadFailed("Strava upload not yet implemented")
    }

    // MARK: - OAuth helpers

    #if os(iOS)
    private func presentOAuthWebView() async throws -> String {
        let redirectURI = "relay://strava-callback"
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id",     value: STRAVA_CLIENT_ID_PLACEHOLDER),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope",         value: "activity:read_all,activity:write")
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "relay"
            ) { callbackURL, error in
                if let error { continuation.resume(throwing: error); return }
                guard
                    let url = callbackURL,
                    let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: AdapterError.authFailed("No auth code in callback"))
                    return
                }
                continuation.resume(returning: code)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
    #endif

    private func exchangeCodeForToken(_ code: String) async throws {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id":     STRAVA_CLIENT_ID_PLACEHOLDER,
            "client_secret": STRAVA_CLIENT_SECRET_PLACEHOLDER,
            "code":          code,
            "grant_type":    "authorization_code"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        accessToken  = tokenResponse.access_token
        refreshToken = tokenResponse.refresh_token
        tokenExpiry  = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expires_at))
    }

    private func refreshIfNeeded() async throws {
        guard let expiry = tokenExpiry, expiry < Date().addingTimeInterval(60) else { return }
        guard let refresh = refreshToken else { throw AdapterError.authFailed("No refresh token") }

        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id":     STRAVA_CLIENT_ID_PLACEHOLDER,
            "client_secret": STRAVA_CLIENT_SECRET_PLACEHOLDER,
            "refresh_token": refresh,
            "grant_type":    "refresh_token"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        accessToken  = tokenResponse.access_token
        refreshToken = tokenResponse.refresh_token
        tokenExpiry  = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expires_at))
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AdapterError.networkError("Unexpected HTTP response: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
    }
}

// MARK: - Strava API models

private struct StravaTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int
}

private struct StravaActivity: Decodable {
    let id: Int
    let name: String
    let type: String
    let start_date: String
    let elapsed_time: Int           // seconds
    let distance: Double?
    let total_elevation_gain: Double?
    let average_heartrate: Double?
    let max_heartrate: Double?
    let average_watts: Double?
    let max_watts: Double?
    let weighted_average_watts: Double?   // Normalized Power
    let average_cadence: Double?
    let average_speed: Double?
    let max_speed: Double?
    let trainer: Bool?
    let kilojoules: Double?

    func toNormalized() -> NormalizedWorkout {
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: start_date) ?? Date()
        let calories = kilojoules.map { Int($0 / 4.184) }

        return NormalizedWorkout(
            externalID: "\(id)",
            source: .strava,
            startDate: start,
            duration: TimeInterval(elapsed_time),
            sportType: SportType(stravaType: type),
            name: name,
            isTrainer: trainer ?? false,
            distance: distance,
            calories: calories,
            avgHeartRate: average_heartrate,
            maxHeartRate: max_heartrate,
            avgPower: average_watts,
            maxPower: max_watts,
            normalizedPower: weighted_average_watts,
            avgCadence: average_cadence,
            avgSpeed: average_speed,
            maxSpeed: max_speed,
            elevationGain: total_elevation_gain
        )
    }
}
