import Foundation
import CryptoKit

/// Talks to the Flask backend (backend/ in this repo). See docs/API.md.
enum EventServer {
    struct ServerEvent: Codable {
        var id: String
        var title: String
        var description: String
        var startTime: Date
        var endTime: Date?
        var locationName: String
        var latitude: Double?
        var longitude: Double?
        var category: String
        var imageUrl: String?
        var hostName: String?
        var address: String?
        var capacity: Int?
        var attendeeCount: Int?
        var cost: String?
        var tags: [String]?
        var level: String?
        var requiresApproval: Bool?
    }

    /// Body for POST /api/events.
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
        var hostName: String
        var address: String
        var capacity: Int
        var cost: String
        var tags: [String]
        var level: String
        var requiresApproval: Bool
    }

    struct ServerError: LocalizedError {
        var message: String
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

    static func fetchEvents(baseURL: URL) async throws -> [ServerEvent] {
        var components = URLComponents(url: baseURL.appending(path: "api/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")]
        let (data, response) = try await session.data(from: components.url!)
        try check(response, data)
        return try decoder.decode(ListResponse.self, from: data).events
    }

    static func create(_ event: NewEvent, baseURL: URL) async throws -> ServerEvent {
        var request = URLRequest(url: baseURL.appending(path: "api/events"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(event)
        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return try decoder.decode(ServerEvent.self, from: data)
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
        let (data, response) = try await slowSession.data(for: request)
        try check(response, data)
        return try decoder.decode(Response.self, from: data)
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ServerError(message: "No response from server") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data).error.message) ?? "Server error \(http.statusCode)"
            throw ServerError(message: message)
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
        self.init(
            id: EventServer.localID(for: e.id), title: e.title, category: ActivityCategory(serverValue: e.category),
            hostID: hostID, date: e.startTime, durationMinutes: duration, placeName: e.locationName,
            address: e.address ?? e.locationName,
            latitude: e.latitude ?? Geo.home.latitude, longitude: e.longitude ?? Geo.home.longitude,
            capacity: e.capacity ?? 30, attendeeIDs: [],
            details: e.description.isEmpty ? "No description yet." : e.description,
            tags: e.tags ?? [], level: ActivityLevel(apiValue: e.level),
            requiresApproval: e.requiresApproval ?? false, costNote: e.cost ?? "Free",
            serverID: e.id
        )
    }

    func serverBody(hostName: String) -> EventServer.NewEvent {
        EventServer.NewEvent(
            id: id.uuidString.lowercased(), title: title, description: details, startTime: date, endTime: endDate,
            locationName: placeName, latitude: latitude, longitude: longitude, category: category.rawValue,
            hostName: hostName, address: address, capacity: min(max(capacity, 2), 500), cost: costNote,
            tags: Array(tags.prefix(10)).map { String($0.prefix(30)) }, level: level.apiValue,
            requiresApproval: requiresApproval
        )
    }
}

extension Person {
    /// Stand-in profile for a host known only by name from the server.
    static func serverHost(named name: String?, category: ActivityCategory) -> Person {
        let display = name?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Campus host"
        let id = EventServer.stableUUID("host:" + display.lowercased())
        let hue = Double(id.uuid.0) / 255
        return Person(id: id, name: display, age: 0, bio: "Posts plans on Swipe-n-Go.", pronouns: "",
                      interests: [category], hue: hue, emoji: "", isVerified: false, rating: 5.0,
                      activitiesDone: 0, school: "UC Davis")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
