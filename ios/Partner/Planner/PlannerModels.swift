import Foundation

/// What the planner understood from "I'm free tomorrow after 5, want something active".
struct PlanRequest: Equatable {
    var start: Date
    var end: Date
    var categories: [ActivityCategory]
    var cheap: Bool
    var beginnerFriendly: Bool
    var wantsCompany: Bool
}

/// One suggested event and why it fits.
struct PlanPick: Identifiable, Equatable {
    var id: UUID { activity.id }
    let activity: Activity
    let reason: String
}

/// Who produced a plan.
enum PlanEngine: Equatable {
    /// Claude, through the team's server (`POST /api/planner`).
    case claude
    /// The keyword planner on the phone. Used offline or when the server's AI isn't available.
    case onDevice
}

struct PlanResult: Equatable {
    /// Short restatement shown at the top, e.g. "Tomorrow after 5 PM · something active".
    var understood: String
    var picks: [PlanPick]
    /// Set when nothing fit exactly and the search was widened.
    var note: String?
    var engine: PlanEngine
    /// Why Claude wasn't used, when the app fell back to on-device planning.
    var fallbackReason: String?
}

/// What the planners need to know about the person.
struct PlannerContext {
    var interests: [ActivityCategory]
    var myID: UUID

    /// Events worth considering: upcoming, not your own, not full.
    func candidates(from activities: [Activity], now: Date = .now) -> [Activity] {
        activities
            .filter { $0.date > now && $0.hostID != myID && !$0.isFull }
            .sorted { $0.date < $1.date }
    }
}

extension ActivityCategory {
    /// What "something active" means.
    static let active: [ActivityCategory] = [.run, .gym, .hike, .cycling, .sports, .yoga]
}
