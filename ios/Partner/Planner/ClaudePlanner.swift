import Foundation

/// Plans with Claude through the team's server (`POST /api/planner`, see docs/API.md).
/// The API key stays on the server; the app sends the request text, the person's
/// interests and the events it can see, and gets back picks with reasons.
struct ClaudePlanner {
    let baseURL: URL

    /// The server limits a request to 80 events; the nearest-in-time 60 are plenty.
    static let maxCandidates = 60

    /// All times go out in the phone's time zone with its offset ("2026-11-12T17:30:00-08:00"),
    /// so "tonight" means tonight here and reasons quote the times people see in the app.
    static var localTime: Date.ISO8601FormatStyle { Date.ISO8601FormatStyle(timeZone: .current) }

    /// What's sent instead of a private event's place (matches AppStore.placeLabel).
    static let hiddenPlace = "Location shared once accepted"

    struct RequestBody: Encodable {
        struct Event: Encodable {
            var id: String
            var title: String
            var category: String
            var startTime: String
            var durationMinutes: Int
            var locationName: String
            var distanceMiles: Double?          // left out for private locations
            var cost: String
            var level: String
            var attendeeCount: Int
            var spotsLeft: Int
            var requiresApproval: Bool
            var tags: [String]
        }
        var query: String
        var now: String
        var interests: [String]
        var events: [Event]
    }

    struct ResponseBody: Decodable, Equatable {
        struct Pick: Decodable, Equatable {
            var eventId: String
            var reason: String
        }
        var understood: String
        var picks: [Pick]
        var note: String
    }

    func plan(_ text: String, activities: [Activity], context: PlannerContext, now: Date = .now) async throws -> PlanResult {
        let candidates = Array(context.candidates(from: activities, now: now).prefix(Self.maxCandidates))
        let body = Self.makeBody(text, candidates: candidates, context: context, now: now)
        let response: ResponseBody = try await EventServer.post("api/planner", body: body, baseURL: baseURL, timeout: 45)
        return Self.result(from: response, candidates: candidates)
    }

    static func makeBody(_ text: String, candidates: [Activity], context: PlannerContext, now: Date) -> RequestBody {
        RequestBody(
            query: String(text.prefix(300)),
            now: Self.localTime.format(now),
            interests: context.interests.map(\.rawValue),
            events: candidates.map { a in
                RequestBody.Event(
                    id: a.id.uuidString.lowercased(), title: a.title, category: a.category.rawValue,
                    startTime: Self.localTime.format(a.date), durationMinutes: max(1, min(a.durationMinutes, 1440)),
                    locationName: context.canSeeLocation(a) ? a.placeName : hiddenPlace,
                    distanceMiles: context.canSeeLocation(a) ? (Geo.miles(to: a.coordinate) * 10).rounded() / 10 : nil,
                    cost: a.costNote, level: a.level.apiValue, attendeeCount: a.attendeeIDs.count + 1,
                    spotsLeft: a.spotsLeft, requiresApproval: a.requiresApproval, tags: Array(a.tags.prefix(10))
                )
            }
        )
    }

    /// Maps the server's answer back to the events on this phone. Unknown ids are ignored.
    static func result(from response: ResponseBody, candidates: [Activity]) -> PlanResult {
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id.uuidString.lowercased(), $0) })
        var seen = Set<UUID>()
        let picks = response.picks.compactMap { pick -> PlanPick? in
            guard let activity = byID[pick.eventId.lowercased()], seen.insert(activity.id).inserted else { return nil }
            return PlanPick(activity: activity, reason: pick.reason)
        }
        let note = response.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanResult(understood: response.understood, picks: Array(picks.prefix(5)),
                          note: note.isEmpty ? nil : note, engine: .claude, fallbackReason: nil)
    }
}
