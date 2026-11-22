import SwiftUI
import CoreLocation

// MARK: - Category

/// Club categories, modeled on how UC Davis groups its 750+ registered student
/// organizations (club sports, outdoors, cultural, service, Greek life, ...).
enum ActivityCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case sports, outdoors, wellness
    case cultural, arts, music
    case academic, career, tech
    case service, greek, faith
    case gaming, social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sports: "Club Sports"
        case .outdoors: "Outdoors"
        case .wellness: "Health & Wellness"
        case .cultural: "Cultural"
        case .arts: "Arts & Performance"
        case .music: "Music"
        case .academic: "Academic"
        case .career: "Career & Professional"
        case .tech: "Tech & Engineering"
        case .service: "Service & Volunteering"
        case .greek: "Greek Life"
        case .faith: "Faith & Spiritual"
        case .gaming: "Gaming"
        case .social: "Food & Social"
        }
    }

    var symbol: String {
        switch self {
        case .sports: "figure.soccer"
        case .outdoors: "figure.hiking"
        case .wellness: "figure.mind.and.body"
        case .cultural: "globe.americas.fill"
        case .arts: "theatermasks.fill"
        case .music: "music.mic"
        case .academic: "book.fill"
        case .career: "briefcase.fill"
        case .tech: "laptopcomputer"
        case .service: "heart.fill"
        case .greek: "building.columns.fill"
        case .faith: "hands.and.sparkles.fill"
        case .gaming: "gamecontroller.fill"
        case .social: "fork.knife"
        }
    }

    var color: Color {
        switch self {
        case .sports: Color(red: 0.98, green: 0.58, blue: 0.10)
        case .outdoors: Color(red: 0.20, green: 0.68, blue: 0.40)
        case .wellness: Color(red: 0.55, green: 0.45, blue: 0.95)
        case .cultural: Color(red: 0.95, green: 0.40, blue: 0.25)
        case .arts: Color(red: 0.95, green: 0.45, blue: 0.75)
        case .music: Color(red: 0.58, green: 0.27, blue: 0.95)
        case .academic: Color(red: 0.20, green: 0.48, blue: 0.95)
        case .career: Color(red: 0.30, green: 0.36, blue: 0.48)
        case .tech: Color(red: 0.10, green: 0.70, blue: 0.70)
        case .service: Color(red: 0.92, green: 0.28, blue: 0.38)
        case .greek: Color(red: 0.05, green: 0.45, blue: 0.75)
        case .faith: Color(red: 0.80, green: 0.62, blue: 0.15)
        case .gaming: Color(red: 0.30, green: 0.40, blue: 0.90)
        case .social: Color(red: 0.96, green: 0.36, blue: 0.47)
        }
    }

    /// Accepts today's names and the pre-club ones ("run", "coffee", "concert", ...), so
    /// plans and profiles saved by older versions, and older server events, still load.
    init?(anyName name: String) {
        if let current = ActivityCategory(rawValue: name) { self = current; return }
        switch name {
        case "run": self = .sports
        case "gym", "yoga": self = .wellness
        case "hike", "cycling", "explore": self = .outdoors
        case "food", "coffee", "drinks", "clubs": self = .social
        case "concert": self = .music
        case "movies", "art": self = .arts
        case "study": self = .academic
        case "games": self = .gaming
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        self = ActivityCategory(anyName: name) ?? .social
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [color, color.mix(with: .black, by: 0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var meshColors: [Color] {
        [
            color.mix(with: .white, by: 0.25), color, color.mix(with: .purple, by: 0.25),
            color.mix(with: .orange, by: 0.15), color.mix(with: .black, by: 0.15), color.mix(with: .blue, by: 0.2),
            color.mix(with: .black, by: 0.3), color.mix(with: .black, by: 0.45), color.mix(with: .black, by: 0.55)
        ]
    }
}

// MARK: - User

struct Person: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var age: Int
    var bio: String
    var pronouns: String
    var interests: [ActivityCategory]
    var hue: Double
    var emoji: String
    var isVerified: Bool
    var rating: Double
    var activitiesDone: Int
    var school: String
    var photoData: Data? = nil

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.95),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.75)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Activity

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case anyone = "Anyone welcome"
    case beginner = "Beginner friendly"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    var id: String { rawValue }
}

struct Activity: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var category: ActivityCategory
    var hostID: UUID
    var date: Date
    var durationMinutes: Int
    var placeName: String
    var address: String
    var latitude: Double
    var longitude: Double
    var capacity: Int
    var attendeeIDs: [UUID]
    var details: String
    var tags: [String]
    var level: ActivityLevel
    var requiresApproval: Bool
    var costNote: String
    var seriesID: UUID? = nil
    var coverPhotoData: Data? = nil
    /// Set when the event exists on the backend (nil = only on this phone).
    var serverID: String? = nil
    /// The host keeps the location hidden until they accept someone.
    var privateLocation: Bool? = nil
    /// True while the server has not shared this private location with you yet.
    var locationHidden: Bool? = nil
    /// Your join request on the server for someone else's event (your account id).
    var myAttendeeID: String? = nil
    /// Server attendee id for each person on this phone, so the host can remove them on the server.
    var serverAttendeeIDs: [UUID: String]? = nil
    /// The server's cover photo address (`image_url`), which changes when the photo changes.
    var serverCoverURL: String? = nil
    /// Which server cover `coverPhotoData` holds, so it's only downloaded or uploaded once.
    var coverSyncedURL: String? = nil

    var isLocationPrivate: Bool { privateLocation == true }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var spotsLeft: Int { max(0, capacity - attendeeIDs.count - 1) }
    var isFull: Bool { spotsLeft == 0 }
    var endDate: Date { date.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var isPast: Bool { endDate < .now }
}

// MARK: - Chat

struct Message: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case text, system }
    var id = UUID()
    var senderID: UUID
    var text: String
    var date: Date
    var kind: Kind = .text
}

struct Conversation: Codable, Identifiable, Hashable {
    var id: UUID
    var activityID: UUID?
    var participantIDs: [UUID]
    var messages: [Message]
    var unreadCount: Int = 0
    /// Muted chats don't count toward the Chats badge. Optional so older saved chats still load.
    var isMuted: Bool? = nil

    var muted: Bool { isMuted ?? false }
    var lastMessage: Message? { messages.last }
}

// MARK: - Join requests (for activities you host)

struct JoinRequest: Codable, Identifiable, Hashable {
    var id = UUID()
    var activityID: UUID
    var personID: UUID
    var note: String
    var date: Date
    /// Set for requests that came from the server (a real person on another phone).
    var serverAttendeeID: String? = nil
}

// MARK: - Helpers

enum Geo {
    /// Downtown Davis, CA — the demo "current location".
    static let home = CLLocationCoordinate2D(latitude: 38.5449, longitude: -121.7405)

    static func miles(to coordinate: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: home.latitude, longitude: home.longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b) / 1609.34
    }

    static func distanceText(to coordinate: CLLocationCoordinate2D) -> String {
        let m = miles(to: coordinate)
        if m < 0.1 { return "Nearby" }
        return m < 10 ? String(format: "%.1f mi", m) : String(format: "%.0f mi", m)
    }
}

extension Date {
    var friendlyDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInTomorrow(self) { return "Tomorrow" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: self)).day,
           days > 1, days < 7 {
            return formatted(.dateTime.weekday(.wide))
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    var friendlyTime: String { formatted(date: .omitted, time: .shortened) }

    var friendlyDateTime: String { "\(friendlyDay) · \(friendlyTime)" }

    var relativeShort: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if Calendar.current.isDateInToday(self) { return friendlyTime }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}


struct ActivityDraft: Codable, Identifiable {
    var id = UUID()
    var category: ActivityCategory = .social
    var title = ""
    var date = Calendar.current.date(byAdding: .hour, value: 3, to: .now)!
    var duration = 90
    var place: Place?
    var capacity = 4
    var level: ActivityLevel = .anyone
    var requiresApproval = false
    var privateLocation: Bool? = nil
    var cost = "Free"
    var details = ""
    var coverPhotoData: Data?
    var scheduledAt: Date?
    var recurrence: EventRecurrence?
    var suggestedLocation: String?
    var reviewedFlyerLocation: FlyerLocation?
    var updatedAt = Date.now

    var activity: Activity? {
        guard let place, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Activity(
            id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category, hostID: UUID(), date: date, durationMinutes: duration,
            placeName: place.name, address: place.address,
            latitude: place.latitude, longitude: place.longitude,
            capacity: capacity, attendeeIDs: [], details: details,
            tags: [category.title], level: level, requiresApproval: requiresApproval || privateLocation == true,
            costNote: cost.isEmpty ? "Free" : cost, coverPhotoData: coverPhotoData,
            privateLocation: privateLocation == true ? true : nil
        )
    }
}


struct EventRecurrence: Codable, Equatable {
    enum Frequency: String, Codable, CaseIterable {
        case weekly = "Every week"
        case biweekly = "Every two weeks"
        case monthly = "Every month"
    }

    var frequency: Frequency = .weekly
    var count = 6
    var timeZoneID = TimeZone.current.identifier

    func dates(startingAt start: Date) -> [Date] {
        guard (2...12).contains(count) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let component: Calendar.Component = frequency == .monthly ? .month : .weekOfYear
        let interval = frequency == .biweekly ? 2 : 1
        return (0..<count).compactMap {
            calendar.date(byAdding: component, value: $0 * interval, to: start)
        }
    }
}

extension ActivityDraft {
    var occurrenceDates: [Date] {
        recurrence?.dates(startingAt: date) ?? [date]
    }

    func activities(hostID: UUID) -> [Activity] {
        guard let template = activity else { return [] }
        return occurrenceDates.enumerated().map { index, date in
            var occurrence = template
            occurrence.id = index == 0 ? id : UUID()
            occurrence.hostID = hostID
            occurrence.date = date
            occurrence.seriesID = recurrence == nil ? nil : id
            return occurrence
        }
    }
}

extension Array where Element: Hashable {
    /// The same elements in the same order, each only once.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
