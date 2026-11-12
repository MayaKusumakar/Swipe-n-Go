import Foundation
import CryptoKit

/// Talks to the Flask backend (backend/ in this repo). See docs/API.md.
/// Every /api request carries the signed-in @ucdavis.edu user's token (see Auth.swift).
enum EventServer {
    /// Returns the token for `Authorization: Bearer …`, or nil when signed out. Set by AppStore.
    nonisolated(unsafe) static var tokenProvider: (@Sendable () async throws -> String?)?

    struct ServerEvent: Codable {
        var id: String
        var title: String
        var description: String
        var startTime: Date
        var endTime: Date?
        /// nil in the public list when the location is private.
        var locationName: String?
        var latitude: Double?
        var longitude: Double?
        var category: String
        var imageUrl: String?
        /// Account id of the host. Matches Auth.account.id when you posted it, even from another phone.
        var hostId: String?
        var hostName: String?
        var address: String?
        var capacity: Int?
        var attendeeCount: Int?
        var cost: String?
        var tags: [String]?
        var level: String?
        var requiresApproval: Bool?
        var locationPrivate: Bool?
        var summary: String?
    }

    struct Attendee: Decodable {
        var id: String
        var name: String
        var status: String
        var isApproved: Bool { status == "approved" }
    }

    struct Location: Decodable {
        var locationName: String
        var address: String?
        var latitude: Double?
        var longitude: Double?
    }

    /// Body for POST /api/events. The server takes the host's name from their account.
    struct NewEvent: Encodable {
        var id: String
        var title: String
        var description: String
        var startTime: Date
        var endTime: Date
        var locationName: String
        var latitude: Double
        var longitude: Double
        var category: String
        var address: String
        var capacity: Int
        var cost: String
        var tags: [String]
        var level: String
        var requiresApproval: Bool
        var locationPrivate: Bool
    }

    struct ServerError: LocalizedError {
        var message: String
        var status = 0
        var errorDescription: String? { message }
    }

    private struct ListResponse: Decodable { var events: [ServerEvent] }
    private struct ErrorResponse: Decodable { struct Body: Decodable { var message: String }; var error: Body }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Adds the signed-in user's token. Requests without one get 401 from the server.
    private static func authorize(_ request: inout URLRequest) async throws {
        if let token = try await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    static func fetchEvents(baseURL: URL) async throws -> [ServerEvent] {
        var components = URLComponents(url: baseURL.appending(path: "api/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")]
        let data = try await send("GET", components.url!)
        return try decoder.decode(ListResponse.self, from: data).events
    }

    static func create(_ event: NewEvent, baseURL: URL) async throws -> ServerEvent {
        let data = try await send("POST", baseURL.appending(path: "api/events"), body: try encoder.encode(event))
        return try decoder.decode(ServerEvent.self, from: data)
    }

    // MARK: Cover photos (see docs/API.md)

    /// Uploads the host's cover (a JPEG under 900 KB). Returns the event's new `image_url`.
    static func uploadCover(eventID: String, jpeg: Data, baseURL: URL) async throws -> String {
        struct Body: Encodable { var image: String }
        struct Reply: Decodable { var imageUrl: String }
        let data = try await send("PUT", baseURL.appending(path: "api/events/\(eventID)/cover"),
                                  body: try encoder.encode(Body(image: jpeg.base64EncodedString())))
        return try decoder.decode(Reply.self, from: data).imageUrl
    }

    /// Downloads a cover from its `image_url` (a path on this server).
    static func downloadCover(_ imageURL: String, baseURL: URL) async throws -> Data {
        guard let url = URL(string: imageURL, relativeTo: baseURL)?.absoluteURL else { throw URLError(.badURL) }
        return try await send("GET", url)
    }

    // MARK: Your name

    /// Tells the server the name from your profile; it's shown on your events and join requests.
    static func updateMyName(_ name: String, baseURL: URL) async throws {
        _ = try await send("PATCH", baseURL.appending(path: "api/auth/me"),
                           body: try JSONSerialization.data(withJSONObject: ["name": name]))
    }

    // MARK: Sign-in

    struct AuthConfig: Decodable { var allowedDomain: String; var devSignIn: Bool }
    struct SignedInUser: Decodable { var id: String; var email: String; var name: String }

    /// Public: whether the server allows dev sign-in (local servers with DEV_SIGN_IN=on only).
    static func authConfig(baseURL: URL) async throws -> AuthConfig {
        let data = try await send("GET", baseURL.appending(path: "api/auth/config"))
        return try decoder.decode(AuthConfig.self, from: data)
    }

    /// Tells the server you signed in; it checks the account is a verified @ucdavis.edu one.
    static func confirmSignIn(baseURL: URL) async throws -> SignedInUser {
        let data = try await send("POST", baseURL.appending(path: "api/auth/sign-in"))
        return try decoder.decode(SignedInUser.self, from: data)
    }

    // MARK: Attendees and private locations (see docs/API.md). The server checks who you are.

    private static func send(_ method: String, _ url: URL, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        try await authorize(&request)
        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return data
    }

    private static func send(_ method: String, _ path: String, baseURL: URL) async throws -> Data {
        try await send(method, baseURL.appending(path: path))
    }

    /// Joins (or asks to join) as the signed-in user. Asking again returns the same entry.
    static func requestToJoin(eventID: String, baseURL: URL) async throws -> Attendee {
        let data = try await send("POST", "api/events/\(eventID)/attendees", baseURL: baseURL)
        return try decoder.decode(Attendee.self, from: data)
    }

    /// Your own entry for someone else's event: pending until the host approves you.
    static func myAttendance(eventID: String, baseURL: URL) async throws -> Attendee {
        let data = try await send("GET", "api/events/\(eventID)/attendees/me", baseURL: baseURL)
        return try decoder.decode(Attendee.self, from: data)
    }

    static func attendees(eventID: String, baseURL: URL) async throws -> [Attendee] {
        struct Response: Decodable { var attendees: [Attendee] }
        let data = try await send("GET", "api/events/\(eventID)/attendees", baseURL: baseURL)
        return try decoder.decode(Response.self, from: data).attendees
    }

    static func approve(eventID: String, attendeeID: String, baseURL: URL) async throws {
        _ = try await send("POST", "api/events/\(eventID)/attendees/\(attendeeID)/approve", baseURL: baseURL)
    }

    /// The host removes someone (or declines a request), or you remove yourself.
    static func removeAttendee(eventID: String, attendeeID: String, baseURL: URL) async throws {
        _ = try await send("DELETE", "api/events/\(eventID)/attendees/\(attendeeID)", baseURL: baseURL)
    }

    /// The full location of a private event. The server answers 403 until the host has approved you.
    static func location(eventID: String, baseURL: URL) async throws -> Location {
        let data = try await send("GET", "api/events/\(eventID)/location", baseURL: baseURL)
        return try decoder.decode(Location.self, from: data)
    }

    /// For slower endpoints like the AI planner; the timeout is set per request.
    private static let slowSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// POSTs JSON (snake_case keys) and decodes a JSON reply. Cancelling the task cancels the request.
    static func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, baseURL: URL,
                                                           timeout: TimeInterval) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        try await authorize(&request)
        let (data, response) = try await slowSession.data(for: request)
        try check(response, data)
        return try decoder.decode(Response.self, from: data)
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ServerError(message: "No response from server") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data).error.message) ?? "Server error \(http.statusCode)"
            throw ServerError(message: message, status: http.statusCode)
        }
    }

    // MARK: JSON

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            // Python's isoformat() may or may not include fractional seconds.
            if let date = try? Date(string, strategy: .iso8601) { return date }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"))
        }
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// The app identifies events with UUIDs; server ids like "seed-001" get a stable UUID derived from the id.
    static func localID(for serverID: String) -> UUID {
        if let uuid = UUID(uuidString: serverID) { return uuid }
        return stableUUID("event:" + serverID)
    }

    static func stableUUID(_ key: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(key.utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }
}

// MARK: - Mapping between the server's format and the app's

extension ActivityCategory {
    /// Server categories are plain words. The app's own names map directly;
    /// the ones used by the backend's sample data are translated.
    init(serverValue: String) {
        if let match = ActivityCategory(rawValue: serverValue) {
            self = match
            return
        }
        self = switch serverValue {
        case "social": .games
        case "music": .concert
        case "outdoors": .hike
        case "tech": .study
        default: .explore
        }
    }
}

extension ActivityLevel {
    var apiValue: String {
        switch self {
        case .anyone: "anyone"
        case .beginner: "beginner"
        case .intermediate: "intermediate"
        case .advanced: "advanced"
        }
    }

    init(apiValue: String?) {
        self = ActivityLevel.allCases.first { $0.apiValue == apiValue } ?? .anyone
    }
}

extension Activity {
    init(server e: EventServer.ServerEvent, hostID: UUID) {
        let duration = e.endTime.map { max(15, Int($0.timeIntervalSince(e.startTime) / 60)) } ?? 60
        // A private location arrives without a name or coordinates; it stays hidden until the server shares it.
        let hidden = e.locationPrivate == true && e.locationName == nil
        self.init(
            id: EventServer.localID(for: e.id), title: e.title, category: ActivityCategory(serverValue: e.category),
            hostID: hostID, date: e.startTime, durationMinutes: duration, placeName: e.locationName ?? "",
            address: e.address ?? e.locationName ?? "",
            latitude: e.latitude ?? Geo.home.latitude, longitude: e.longitude ?? Geo.home.longitude,
            capacity: e.capacity ?? 30, attendeeIDs: [],
            details: e.description.isEmpty ? "No description yet." : e.description,
            tags: e.tags ?? [], level: ActivityLevel(apiValue: e.level),
            requiresApproval: e.requiresApproval ?? false, costNote: e.cost ?? "Free",
            serverID: e.id,
            privateLocation: e.locationPrivate == true ? true : nil,
            locationHidden: hidden ? true : nil,
            serverCoverURL: e.imageUrl
        )
    }

    func serverBody() -> EventServer.NewEvent {
        EventServer.NewEvent(
            id: id.uuidString.lowercased(), title: title, description: details, startTime: date, endTime: endDate,
            locationName: placeName, latitude: latitude, longitude: longitude, category: category.rawValue,
            address: address, capacity: min(max(capacity, 2), 500), cost: costNote,
            tags: Array(tags.prefix(10)).map { String($0.prefix(30)) }, level: level.apiValue,
            requiresApproval: requiresApproval || isLocationPrivate, locationPrivate: isLocationPrivate
        )
    }
}

extension Person {
    /// Stand-in profile for a host known only by name from the server.
    static func serverHost(named name: String?, category: ActivityCategory,
                           bio: String = "Posts plans on Swipe-n-Go.") -> Person {
        let display = name?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Campus host"
        let id = EventServer.stableUUID("host:" + display.lowercased())
        let hue = Double(id.uuid.0) / 255
        return Person(id: id, name: display, age: 0, bio: bio, pronouns: "",
                      interests: [category], hue: hue, emoji: "", isVerified: false, rating: 5.0,
                      activitiesDone: 0, school: "UC Davis")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
