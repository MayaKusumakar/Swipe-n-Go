import SwiftUI

/// Drives the "I'm free…" screen: runs a plan with Claude when the server is
/// reachable, falls back to the on-device planner otherwise, and remembers
/// recent searches.
@MainActor
@Observable
final class PlannerModel {
    enum Phase: Equatable {
        case idle
        case planning(step: Int)
        case finished(PlanResult)
    }

    /// The steps shown while planning.
    static let steps = ["Reading your request", "Checking what's on", "Picking the best fits"]

    private(set) var phase: Phase = .idle
    private(set) var recents: [String]
    var text = ""

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    private static let recentsKey = "plannerRecentSearches"
    private static let maxRecents = 5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = defaults.stringArray(forKey: Self.recentsKey) ?? []
    }

    var isPlanning: Bool { if case .planning = phase { true } else { false } }
    var canSubmit: Bool { !isPlanning && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Starts a plan. A new request cancels the one in flight.
    func submit(_ query: String? = nil, store: AppStore) {
        if let query { text = query }
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        remember(request)

        task?.cancel()
        let activities = store.feedActivities
        let context = PlannerContext(interests: store.me.interests, myID: store.me.id,
                                     canSeeLocation: { [store] in store.canSeeLocation($0) })
        let serverURL = store.serverURL
        task = Task { await run(request, activities: activities, context: context, serverURL: serverURL) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isPlanning { phase = .idle }
    }

    func reset() {
        cancel()
        text = ""
        phase = .idle
    }

    func clearRecents() {
        recents = []
        defaults.removeObject(forKey: Self.recentsKey)
    }

    // MARK: Running a plan

    private func run(_ request: String, activities: [Activity], context: PlannerContext, serverURL: URL?) async {
        phase = .planning(step: 0)
        let progress = Task { await advanceSteps() }
        defer { progress.cancel() }
        let started = ContinuousClock.now

        var result: PlanResult
        if let serverURL {
            do {
                result = try await ClaudePlanner(baseURL: serverURL).plan(request, activities: activities, context: context)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                result = OnDevicePlanner.plan(request, activities: activities, context: context,
                                              fallbackReason: Self.explain(error))
            }
        } else {
            result = OnDevicePlanner.plan(request, activities: activities, context: context,
                                          fallbackReason: "Connect to your team's server in Profile → Server to plan with Claude.")
        }

        // Let the progress steps be seen even when on-device planning is instant.
        let minimum = Duration.milliseconds(900)
        let elapsed = ContinuousClock.now - started
        if elapsed < minimum { try? await Task.sleep(for: minimum - elapsed) }
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { phase = .finished(result) }
    }

    private func advanceSteps() async {
        for step in 1..<Self.steps.count {
            try? await Task.sleep(for: .milliseconds(step == 1 ? 350 : 900))
            guard !Task.isCancelled, case .planning = phase else { return }
            withAnimation(.snappy) { phase = .planning(step: step) }
        }
    }

    private func remember(_ query: String) {
        recents.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recents.insert(query, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        defaults.set(recents, forKey: Self.recentsKey)
    }

    /// A short, human explanation for why Claude wasn't used.
    static func explain(_ error: Error) -> String {
        if let serverError = error as? EventServer.ServerError {
            let message = serverError.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return (message.hasSuffix(".") ? message : message + ".") + " These picks were made on your iPhone."
        }
        if error is URLError {
            return "Couldn't reach your team's server, so these picks were made on your iPhone."
        }
        return "Something went wrong with Claude, so these picks were made on your iPhone."
    }
}
