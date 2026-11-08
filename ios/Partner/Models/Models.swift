import SwiftUI
import CoreLocation

// MARK: - Category

enum ActivityCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case run, gym, hike, cycling, sports, yoga
    case food, coffee, drinks
    case concert, movies, art
    case study, games, explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Running"
        case .gym: "Gym"
        case .hike: "Hiking"
        case .cycling: "Cycling"
        case .sports: "Sports"
        case .yoga: "Yoga"
        case .food: "Food"
        case .coffee: "Coffee"
        case .drinks: "Drinks"
        case .concert: "Concerts"
        case .movies: "Movies"
        case .art: "Art & Museums"
        case .study: "Study"
        case .games: "Games"
        case .explore: "Day Out"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .gym: "dumbbell.fill"
        case .hike: "figure.hiking"
        case .cycling: "bicycle"
        case .sports: "basketball.fill"
        case .yoga: "figure.mind.and.body"
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .drinks: "wineglass.fill"
        case .concert: "music.mic"
        case .movies: "popcorn.fill"
        case .art: "paintpalette.fill"
        case .study: "book.fill"
        case .games: "gamecontroller.fill"
        case .explore: "map.fill"
        }
    }

    var color: Color {
        switch self {
        case .run: Color(red: 1.00, green: 0.42, blue: 0.21)
        case .gym: Color(red: 0.95, green: 0.27, blue: 0.33)
        case .hike: Color(red: 0.20, green: 0.68, blue: 0.40)
        case .cycling: Color(red: 0.10, green: 0.70, blue: 0.70)
        case .sports: Color(red: 0.98, green: 0.58, blue: 0.10)
        case .yoga: Color(red: 0.55, green: 0.45, blue: 0.95)
        case .food: Color(red: 0.96, green: 0.36, blue: 0.47)
        case .coffee: Color(red: 0.62, green: 0.42, blue: 0.30)
        case .drinks: Color(red: 0.75, green: 0.20, blue: 0.50)
        case .concert: Color(red: 0.58, green: 0.27, blue: 0.95)
        case .movies: Color(red: 0.90, green: 0.22, blue: 0.22)
        case .art: Color(red: 0.95, green: 0.45, blue: 0.75)
        case .study: Color(red: 0.20, green: 0.48, blue: 0.95)
        case .games: Color(red: 0.30, green: 0.40, blue: 0.90)
        case .explore: Color(red: 0.05, green: 0.62, blue: 0.85)
        }
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
    var coverPhotoData: Data? = nil

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

    var lastMessage: Message? { messages.last }
}

// MARK: - Join requests (for activities you host)

struct JoinRequest: Codable, Identifiable, Hashable {
    var id = UUID()
    var activityID: UUID
    var personID: UUID
    var note: String
    var date: Date
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
