import SwiftUI
import Observation

struct InAppBanner: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var color: Color
}

enum JoinOutcome { case joined, requested }

enum SwipeAction { case join, skip, save }

/// Single source of truth for the prototype. Persists to a JSON file on device
/// and simulates the "other side" (hosts approving, people replying).
@MainActor
@Observable
final class AppStore {
    // MARK: Persisted state
    var hasOnboarded = false
    var me: Person
    var people: [Person] = [] { didSet { rebuildIndex() } }
    var drafts: [ActivityDraft] = []
    var activities: [Activity] = []
    var joinedIDs: Set<UUID> = []
    var pendingIDs: Set<UUID> = []
    var savedIDs: Set<UUID> = []
    /// Save / unsave of server events not yet confirmed by the server (event server id → saved).
    var pendingSaves: [String: Bool] = [:]
    /// The profile name changed but the server hasn't accepted it yet.
    var nameNeedsSync = false
    var skippedIDs: Set<UUID> = []
    var conversations: [Conversation] = []
    var requests: [JoinRequest] = []
    var notificationsEnabled = true
    var radiusMiles: Double = 50
    var showAgeOnProfile = true

    // MARK: Transient UI state
    var banner: InAppBanner?
    var typing: [UUID: UUID] = [:]           // conversationID → personID currently "typing"
    var selectedTab: AppTab = .discover
    var showCreate = false                    // Host sheet, opened from the center tab
    var showPlanner = false                   // "I'm free…" AI planner, opened from Discover or an empty state
    var showProfile = false                   // Profile sheet, opened from the top-right avatar
    var openConversationID: UUID?
    var requestedChat: UUID?                  // set to deep-link into a conversation
    private(set) var swipeHistory: [(UUID, SwipeAction)] = []

    // MARK: Server (see AppStore+Server.swift)
    /// Your @ucdavis.edu sign-in. Every server request carries its token.
    let auth = Auth()
    var serverStatus: ServerStatus = .off
    @ObservationIgnored var rejectedUploads: Set<UUID> = []   // plans the server refused; not retried
    @ObservationIgnored var debugPlannerQuery: String?         // DEBUG: `-plan "<text>"` opens I'm free… and runs it
    var serverURLString: String = UserDefaults.standard.string(forKey: AppStore.serverURLKey) ?? AppStore.defaultServerURL {
        didSet { UserDefaults.standard.set(serverURLString, forKey: AppStore.serverURLKey) }
    }
    var showSampleEvents: Bool = UserDefaults.standard.object(forKey: AppStore.showSampleEventsKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showSampleEvents, forKey: AppStore.showSampleEventsKey) }
    }

    @ObservationIgnored private var index: [UUID: Person] = [:]
    @ObservationIgnored private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "partner-state.json")
    }()

    init() {
        me = AppStore.defaultMe()
        if !load() { seed() }
        let auth = auth
        EventServer.tokenProvider = { try await auth.bearerToken() }
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    #if DEBUG
    /// `-demo` skips onboarding with a sample profile; `-tab <name>` opens a tab. Handy for screenshots.
    private func applyDebugLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-onboarding") { hasOnboarded = false }
        if args.contains("-host") { showCreate = true }
        if args.contains("-samples") { showSampleEvents = true; serverURLString = "" }
        if let i = args.firstIndex(of: "-server"), i + 1 < args.count { serverURLString = args[i + 1] }
        // `-devSignIn you@ucdavis.edu` signs in through a local server's dev sign-in (DEV_SIGN_IN=on).
        if let i = args.firstIndex(of: "-devSignIn"), i + 1 < args.count { auth.signInForDevelopment(email: args[i + 1], name: "") }
        if args.contains("-signOut") { auth.signOut() }
        if args.contains("-noSamples") { showSampleEvents = false }
        if let i = args.firstIndex(of: "-plan"), i + 1 < args.count {
            debugPlannerQuery = args[i + 1]
            showPlanner = true
        }
        if args.contains("-planner") { showPlanner = true }
        if args.contains("-hostTest"), hasOnboarded {
            // Posts a plan as if made in the Host sheet, to test the upload path.
            let date = Calendar.current.date(byAdding: .day, value: 2, to: .now)!
            host(Activity(id: UUID(), title: "Posted from the iPhone app", category: .coffee, hostID: me.id, date: date,
                          durationMinutes: 60, placeName: "Mishka's Café", address: "610 2nd St, Davis, CA",
                          latitude: 38.5440, longitude: -121.7407, capacity: 4, attendeeIDs: [],
                          details: "Testing the shared server.", tags: ["Coffee"], level: .beginner,
                          requiresApproval: false, costNote: "Free"))
        }
        if args.contains("-photo") {
            // A generated test picture, so the profile-photo UI can be screenshotted.
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { ctx in
                UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                UIColor.systemYellow.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 150, y: 120, width: 300, height: 300))
            }
            me.photoData = image.jpegData(compressionQuality: 0.8)
        }
        if args.contains("-demo"), !hasOnboarded, !args.contains("-onboarding") {
            completeOnboarding(name: "Anant Katiyar", age: 21, pronouns: "", interests: [.run, .concert, .food, .coffee, .hike])
            me.emoji = "😎"
            save()
        }
        if args.contains("-joined"), joinedIDs.isEmpty {
            for a in discoverDeck.filter({ !$0.requiresApproval }).prefix(2) { confirmJoin(a.id) }
            if let a = discoverDeck.first(where: { $0.requiresApproval }) { pendingIDs.insert(a.id) }
            savedIDs.formUnion(discoverDeck.suffix(2).map(\.id))
            save()
        }
        if args.contains("-chat"), let c = conversations.first(where: { $0.activityID != nil }) {
            requestedChat = c.id
        }
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            if args[i + 1] == "profile" { showProfile = true }
            selectedTab = ["discover": .discover, "explore": .explore, "plans": .plans, "chats": .chats][args[i + 1]] ?? .discover
        }
    }
    #endif

    static func defaultMe() -> Person {
        Person(id: UUID(), name: "", age: 21, bio: "", pronouns: "", interests: [], hue: 0.6, emoji: "😊",
               isVerified: false, rating: 5.0, activitiesDone: 0, school: "UC Davis")
    }

    // MARK: - Lookup

    func person(_ id: UUID) -> Person? { id == me.id ? me : index[id] }
    func activity(_ id: UUID) -> Activity? { activities.first { $0.id == id } }

    private func rebuildIndex() {
        index = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
    }

    func isHost(_ activity: Activity) -> Bool { activity.hostID == me.id }
    func isGoing(_ activity: Activity) -> Bool { joinedIDs.contains(activity.id) || isHost(activity) }
    func isPending(_ activity: Activity) -> Bool { pendingIDs.contains(activity.id) }
    func isSaved(_ activity: Activity) -> Bool { savedIDs.contains(activity.id) }

    /// A private location shows only to the host and to people the host accepted.
    /// For shared events the server enforces this: it doesn't send the location until then.
    func canSeeLocation(_ activity: Activity) -> Bool {
        guard activity.isLocationPrivate, !isHost(activity) else { return true }
        return joinedIDs.contains(activity.id) && activity.locationHidden != true
    }

    func placeLabel(_ activity: Activity) -> String {
        canSeeLocation(activity) ? activity.placeName : "Location shared once accepted"
    }

    func distanceLabel(_ activity: Activity) -> String {
        canSeeLocation(activity) ? Geo.distanceText(to: activity.coordinate) : "Private"
    }

    func attendees(of activity: Activity) -> [Person] {
        ([activity.hostID] + activity.attendeeIDs).compactMap(person)
    }

    func matchScore(_ activity: Activity) -> Int {
        var score = me.interests.contains(activity.category) ? 3 : 0
        if let host = person(activity.hostID) {
            score += Set(host.interests).intersection(me.interests).count
        }
        return score
    }

    // MARK: - Feeds

    var discoverDeck: [Activity] {
        feedActivities
            .filter { !$0.isPast && !isHost($0) && !joinedIDs.contains($0.id) && !pendingIDs.contains($0.id)
                && !skippedIDs.contains($0.id) && !$0.isFull && Geo.miles(to: $0.coordinate) <= radiusMiles }
            .sorted { lhs, rhs in
                let l = matchScore(lhs), r = matchScore(rhs)
                return l == r ? lhs.date < rhs.date : l > r
            }
    }

    var upcoming: [Activity] {
        activities.filter { !$0.isPast && (isGoing($0) || isPending($0)) }.sorted { $0.date < $1.date }
    }

    var hosting: [Activity] {
        activities.filter { isHost($0) && !$0.isPast }.sorted { $0.date < $1.date }
    }

    var saved: [Activity] {
        activities.filter { savedIDs.contains($0.id) && !$0.isPast }.sorted { $0.date < $1.date }
    }

    var totalUnread: Int { conversations.reduce(0) { $0 + ($1.muted ? 0 : $1.unreadCount) } }

    // MARK: - Onboarding & profile

    func completeOnboarding(name: String, age: Int, pronouns: String, interests: [ActivityCategory]) {
        me.name = name
        me.age = age
        me.pronouns = pronouns
        me.interests = interests
        me.hue = Double.random(in: 0...1)
        if me.bio.isEmpty { me.bio = "New to Swipe-n-Go — say hi! 👋" }
        hasOnboarded = true
        // Seed conversations reference the old `me` id; re-key them.
        seed(keepingMe: true)
        save()
        Task { await syncMyName() }
    }

    func updateProfile(_ person: Person) {
        let renamed = person.name != me.name
        me = person
        save()
        if renamed { Task { await syncMyName() } }
    }

    // MARK: - Swiping & joining

    func swipe(_ activity: Activity, _ action: SwipeAction) {
        swipeHistory.append((activity.id, action))
        switch action {
        case .skip: skippedIDs.insert(activity.id)
        case .save: savedIDs.insert(activity.id); skippedIDs.insert(activity.id); savedChanged(activity, saved: true)
        case .join: _ = join(activity)
        }
        save()
    }

    var canUndo: Bool { !swipeHistory.isEmpty }

    func undoLastSwipe() {
        guard let (id, action) = swipeHistory.popLast() else { return }
        switch action {
        case .skip: skippedIDs.remove(id)
        case .save:
            savedIDs.remove(id); skippedIDs.remove(id)
            if let a = activity(id) { savedChanged(a, saved: false) }
        case .join: if let a = activity(id) { leave(a, silently: true) }
        }
        save()
    }

    @discardableResult
    func join(_ activity: Activity) -> JoinOutcome {
        skippedIDs.remove(activity.id)
        let sharedPrivate = activity.serverID != nil && activity.isLocationPrivate
        if activity.serverID != nil, !isHost(activity), activity.myAttendeeID == nil {
            Task { await registerJoin(activity) }
        }
        if activity.requiresApproval || sharedPrivate {
            pendingIDs.insert(activity.id)
            save()
            // A real host has to accept you before the server shares a private location.
            if !sharedPrivate { simulateHostApproval(for: activity.id) }
            return .requested
        } else {
            confirmJoin(activity.id)
            return .joined
        }
    }

    private func confirmJoin(_ id: UUID) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        pendingIDs.remove(id)
        joinedIDs.insert(id)
        if !activities[i].attendeeIDs.contains(me.id) { activities[i].attendeeIDs.append(me.id) }
        let convo = groupConversation(for: activities[i])
        appendSystem("\(me.firstName) joined the plan", to: convo)
        simulateWelcome(in: convo, activity: activities[i])
        save()
    }

    /// Sends your join request for a shared event to the server, as your signed-in account.
    private func registerJoin(_ activity: Activity) async {
        guard let serverID = activity.serverID, let url = serverURL,
              let attendee = try? await EventServer.requestToJoin(eventID: serverID, baseURL: url),
              let i = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[i].myAttendeeID = attendee.id
        save()
    }

    /// The host of a shared private event accepted you (the server just shared the location).
    func confirmServerApproval(_ id: UUID) {
        guard let a = activity(id) else { return }
        confirmJoin(id)
        show(InAppBanner(title: "You're in! 🎉", subtitle: "\(person(a.hostID)?.firstName ?? "The host") accepted you. The location is now visible.",
                         symbol: a.category.symbol, color: a.category.color))
    }

    func leave(_ activity: Activity, silently: Bool = false) {
        joinedIDs.remove(activity.id)
        pendingIDs.remove(activity.id)
        if let i = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[i].attendeeIDs.removeAll { $0 == me.id }
            if let serverID = activities[i].serverID, let attendeeID = activities[i].myAttendeeID {
                Task { _ = await serverAction { try await EventServer.removeAttendee(eventID: serverID, attendeeID: attendeeID, baseURL: $0) } }
            }
            activities[i].myAttendeeID = nil
            if activities[i].isLocationPrivate, activities[i].serverID != nil { activities[i].locationHidden = true }
        }
        if let c = conversations.firstIndex(where: { $0.activityID == activity.id }) {
            if silently { conversations.remove(at: c) } else {
                conversations[c].messages.append(Message(senderID: me.id, text: "\(me.firstName) left the plan", date: .now, kind: .system))
            }
        }
        save()
    }

    func toggleSaved(_ activity: Activity) {
        let saved = !savedIDs.contains(activity.id)
        if saved { savedIDs.insert(activity.id) } else { savedIDs.remove(activity.id) }
        savedChanged(activity, saved: saved)
        save()
    }

    func resetSkipped() {
        skippedIDs.removeAll()
        swipeHistory.removeAll()
        save()
    }

    @discardableResult
    func saveDraft(_ draft: ActivityDraft) -> Bool {
        let previous = drafts
        drafts.removeAll { $0.id == draft.id }
        drafts.insert(draft, at: 0)
        guard save() else {
            drafts = previous
            return false
        }
        return true
    }

    @discardableResult
    func deleteDraft(_ id: UUID) -> Bool {
        let previous = drafts
        drafts.removeAll { $0.id == id }
        guard save() else {
            drafts = previous
            return false
        }
        return true
    }

    /// Publishes due local posts atomically with removing their drafts.
    func publishScheduledPosts() {
        let now = Date.now
        let due = drafts.filter { $0.scheduledAt.map { $0 <= now } ?? false }
        guard !due.isEmpty else { return }
        let previousDrafts = drafts
        let previousActivities = activities
        for draft in due {
            let occurrences = draft.activities(hostID: me.id)
            if draft.date > now, !occurrences.isEmpty {
                if !activities.contains(where: { $0.id == draft.id || $0.seriesID == draft.id }) {
                    activities.append(contentsOf: occurrences)
                }
                drafts.removeAll { $0.id == draft.id }
            } else if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
                // An event that has already started needs the host to update its date.
                drafts[index].scheduledAt = nil
            }
        }
        activities.sort { $0.date < $1.date }
        if !save() {
            drafts = previousDrafts
            activities = previousActivities
        } else {
            Task { await uploadPendingHostedEvents() }
        }
    }

    @discardableResult
    func publishDraft(_ draft: ActivityDraft) -> Bool {
        let occurrences = draft.activities(hostID: me.id)
        guard draft.date > .now, !occurrences.isEmpty else { return false }
        // Retrying a successful publication must not replace attendee state.
        guard !activities.contains(where: { $0.id == draft.id || $0.seriesID == draft.id }) else { return true }
        let previousDrafts = drafts
        let previousActivities = activities
        drafts.removeAll { $0.id == draft.id }
        activities.append(contentsOf: occurrences)
        activities.sort { $0.date < $1.date }
        guard save() else {
            drafts = previousDrafts
            activities = previousActivities
            return false
        }
        for activity in occurrences {
            _ = groupConversation(for: activity)
        }
        save()
        if let first = occurrences.first {
            simulateIncomingRequest(for: first.id)
        }
        Task { await uploadPendingHostedEvents() }
        return true
    }

    // MARK: - Hosting

    func host(_ activity: Activity) {
        var a = activity
        a.hostID = me.id
        activities.append(a)
        activities.sort { $0.date < $1.date }
        let convo = groupConversation(for: a)
        appendSystem("You created “\(a.title)”. Invite people or wait for requests!", to: convo)
        save()
        simulateIncomingRequest(for: a.id)
        Task { await upload(a) }
    }

    func cancel(_ activity: Activity) {
        activities.removeAll { $0.id == activity.id }
        conversations.removeAll { $0.activityID == activity.id }
        requests.removeAll { $0.activityID == activity.id }
        save()
    }

    func requests(for activity: Activity) -> [JoinRequest] {
        requests.filter { $0.activityID == activity.id }
    }

    func approve(_ request: JoinRequest) {
        if let attendeeID = request.serverAttendeeID, let a = activity(request.activityID), let serverID = a.serverID {
            Task {
                guard await serverAction({ try await EventServer.approve(eventID: serverID, attendeeID: attendeeID, baseURL: $0) }),
                      let i = activities.firstIndex(where: { $0.id == a.id }) else { return }
                activities[i].serverAttendeeIDs = (activities[i].serverAttendeeIDs ?? [:]).merging([request.personID: attendeeID]) { $1 }
                acceptLocally(request)
            }
        } else {
            acceptLocally(request)
        }
    }

    private func acceptLocally(_ request: JoinRequest) {
        requests.removeAll { $0.id == request.id }
        guard let i = activities.firstIndex(where: { $0.id == request.activityID }),
              let guest = person(request.personID) else { return }
        if !activities[i].attendeeIDs.contains(guest.id) { activities[i].attendeeIDs.append(guest.id) }
        let convo = groupConversation(for: activities[i])
        if let c = conversations.firstIndex(where: { $0.id == convo }),
           !conversations[c].participantIDs.contains(guest.id) {
            conversations[c].participantIDs.append(guest.id)
        }
        appendSystem("\(guest.firstName) joined the plan", to: convo)
        save()
        scheduleReply(in: convo, from: guest.id, text: "Thanks for having me! 🙌", after: 2.0)
    }

    func decline(_ request: JoinRequest) {
        if let attendeeID = request.serverAttendeeID, let a = activity(request.activityID), let serverID = a.serverID {
            Task {
                guard await serverAction({ try await EventServer.removeAttendee(eventID: serverID, attendeeID: attendeeID, baseURL: $0) })
                else { return }
                requests.removeAll { $0.id == request.id }
                save()
            }
        } else {
            requests.removeAll { $0.id == request.id }
            save()
        }
    }

    /// The host removes someone from their plan. For shared plans the server does it first,
    /// so they also lose access to a private location.
    func removeAttendee(_ personID: UUID, from activity: Activity) {
        guard isHost(activity), personID != me.id else { return }
        if let serverID = activity.serverID, let attendeeID = activity.serverAttendeeIDs?[personID] {
            Task {
                guard await serverAction({ try await EventServer.removeAttendee(eventID: serverID, attendeeID: attendeeID, baseURL: $0) })
                else { return }
                removeLocally(personID, from: activity.id)
            }
        } else {
            removeLocally(personID, from: activity.id)
        }
    }

    private func removeLocally(_ personID: UUID, from activityID: UUID) {
        guard let i = activities.firstIndex(where: { $0.id == activityID }) else { return }
        activities[i].attendeeIDs.removeAll { $0 == personID }
        activities[i].serverAttendeeIDs?[personID] = nil
        if let c = conversations.firstIndex(where: { $0.activityID == activityID }) {
            conversations[c].participantIDs.removeAll { $0 == personID }
        }
        if let name = person(personID)?.firstName {
            appendSystem("\(name) was removed from the plan", to: groupConversation(for: activities[i]))
        }
        save()
    }

    // MARK: - Chat

    @discardableResult
    func groupConversation(for activity: Activity) -> UUID {
        if let existing = conversations.first(where: { $0.activityID == activity.id }) { return existing.id }
        let participants = Array(Set([me.id, activity.hostID] + activity.attendeeIDs))
        let convo = Conversation(id: UUID(), activityID: activity.id, participantIDs: participants, messages: [])
        conversations.insert(convo, at: 0)
        return convo.id
    }

    @discardableResult
    func directConversation(with personID: UUID) -> UUID {
        if let existing = conversations.first(where: { $0.activityID == nil && Set($0.participantIDs) == [me.id, personID] }) {
            return existing.id
        }
        let convo = Conversation(id: UUID(), activityID: nil, participantIDs: [me.id, personID], messages: [])
        conversations.insert(convo, at: 0)
        save()
        return convo.id
    }

    func conversation(_ id: UUID) -> Conversation? { conversations.first { $0.id == id } }

    func title(for convo: Conversation) -> String {
        if let aid = convo.activityID, let a = activity(aid) { return a.title }
        return convo.participantIDs.filter { $0 != me.id }.compactMap(person).map(\.firstName).joined(separator: ", ")
    }

    func others(in convo: Conversation) -> [Person] {
        convo.participantIDs.filter { $0 != me.id }.compactMap(person)
    }

    func send(_ text: String, in conversationID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[i].messages.append(Message(senderID: me.id, text: trimmed, date: .now))
        bumpToTop(i)
        save()

        guard let responder = others(in: conversations[0]).randomElement() else { return }
        scheduleReply(in: conversationID, from: responder.id, text: reply(to: trimmed), after: Double.random(in: 1.6...3.2))
    }

    func toggleMute(_ conversationID: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[i].isMuted = !conversations[i].muted
        save()
    }

    /// Removes the chat from this phone. It doesn't leave the plan.
    func deleteConversation(_ conversationID: UUID) {
        conversations.removeAll { $0.id == conversationID }
        if openConversationID == conversationID { openConversationID = nil }
        save()
    }

    func markRead(_ conversationID: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationID }), conversations[i].unreadCount > 0 else { return }
        conversations[i].unreadCount = 0
        save()
    }

    private func reply(to text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("?") {
            if lower.contains("where") { return "Let's meet right at the entrance 📍" }
            if lower.contains("when") || lower.contains("time") { return "Let's aim for 10 min before start!" }
            return ["Yes for sure!", "I think so, yeah 👍", "Good question — let's figure it out together"].randomElement()!
        }
        if lower.contains("hi") || lower.contains("hey") || lower.contains("hello") { return "Hey!! 👋 So glad you're coming" }
        if lower.contains("thank") { return "Of course! 😊" }
        return SampleData.replies.randomElement()!
    }

    private func appendSystem(_ text: String, to conversationID: UUID) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[i].messages.append(Message(senderID: me.id, text: text, date: .now, kind: .system))
        bumpToTop(i)
    }

    private func bumpToTop(_ i: Int) {
        guard i != 0 else { return }
        let c = conversations.remove(at: i)
        conversations.insert(c, at: 0)
    }

    // MARK: - Simulation of the other side

    private func scheduleReply(in conversationID: UUID, from personID: UUID, text: String, after delay: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay * 0.4))
            self?.typing[conversationID] = personID
            try? await Task.sleep(for: .seconds(delay * 0.6))
            guard let self else { return }
            self.typing[conversationID] = nil
            guard let i = self.conversations.firstIndex(where: { $0.id == conversationID }) else { return }
            self.conversations[i].messages.append(Message(senderID: personID, text: text, date: .now))
            if self.openConversationID != conversationID { self.conversations[i].unreadCount += 1 }
            self.bumpToTop(i)
            self.save()
        }
    }

    private func simulateHostApproval(for activityID: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard let self, self.pendingIDs.contains(activityID), let a = self.activity(activityID) else { return }
            self.confirmJoin(activityID)
            let host = self.person(a.hostID)?.firstName ?? "The host"
            self.show(InAppBanner(title: "You're in! 🎉", subtitle: "\(host) approved your request for \(a.title)",
                                  symbol: a.category.symbol, color: a.category.color))
        }
    }

    private func simulateWelcome(in conversationID: UUID, activity: Activity) {
        let lines = [
            "Welcome \(me.firstName)! 👋 Stoked you're joining",
            "Yay welcome! See you \(activity.date.friendlyDay.lowercased() == "today" ? "later today" : activity.date.friendlyDay)",
            "Hey \(me.firstName)! Glad you're in 🙌"
        ]
        scheduleReply(in: conversationID, from: activity.hostID, text: lines.randomElement()!, after: 2.4)
    }

    private func simulateIncomingRequest(for activityID: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let a = self.activity(activityID) else { return }
            let candidates = self.people
                .filter { !a.attendeeIDs.contains($0.id) }
                .sorted { ($0.interests.contains(a.category) ? 0 : 1) < ($1.interests.contains(a.category) ? 0 : 1) }
            guard let guest = candidates.prefix(4).randomElement() else { return }
            self.requests.append(JoinRequest(activityID: a.id, personID: guest.id,
                                             note: SampleData.requestNotes.randomElement()!, date: .now))
            self.save()
            self.show(InAppBanner(title: "New join request", subtitle: "\(guest.firstName) wants to join \(a.title)",
                                  symbol: "person.crop.circle.badge.plus", color: a.category.color))
        }
    }

    func show(_ banner: InAppBanner) {
        guard notificationsEnabled else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { self.banner = banner }
        let id = banner.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.6))
            guard let self, self.banner?.id == id else { return }
            withAnimation(.smooth) { self.banner = nil }
        }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var hasOnboarded: Bool
        var me: Person
        var people: [Person]
        var activities: [Activity]
        var drafts: [ActivityDraft]?
        var joinedIDs: Set<UUID>
        var pendingIDs: Set<UUID>
        var savedIDs: Set<UUID>
        var pendingSaves: [String: Bool]? = nil
        var skippedIDs: Set<UUID>
        var conversations: [Conversation]
        var requests: [JoinRequest]
        var notificationsEnabled: Bool
        var radiusMiles: Double
        var showAgeOnProfile: Bool
    }

    @discardableResult
    func save() -> Bool {
        let snap = Snapshot(hasOnboarded: hasOnboarded, me: me, people: people, activities: activities, drafts: drafts,
                            joinedIDs: joinedIDs, pendingIDs: pendingIDs, savedIDs: savedIDs, pendingSaves: pendingSaves, skippedIDs: skippedIDs,
                            conversations: conversations, requests: requests, notificationsEnabled: notificationsEnabled,
                            radiusMiles: radiusMiles, showAgeOnProfile: showAgeOnProfile)
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            print("Partner: save failed — \(error)")
            return false
        }
    }

    @discardableResult
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return false }
        hasOnboarded = s.hasOnboarded
        me = s.me
        people = s.people
        drafts = s.drafts ?? []
        activities = s.activities
        joinedIDs = s.joinedIDs
        pendingIDs = s.pendingIDs
        savedIDs = s.savedIDs
        pendingSaves = s.pendingSaves ?? [:]
        skippedIDs = s.skippedIDs
        conversations = s.conversations
        requests = s.requests
        notificationsEnabled = s.notificationsEnabled
        radiusMiles = s.radiusMiles
        showAgeOnProfile = s.showAgeOnProfile
        // Keep the demo fresh: if every seeded plan has passed, reseed activities.
        if !activities.contains(where: { !$0.isPast && !isHost($0) }) {
            let hosted = activities.filter { isHost($0) }
            seed(keepingMe: true)
            activities.append(contentsOf: hosted)
            activities.sort { $0.date < $1.date }
        }
        return true
    }

    private func seed(keepingMe: Bool = false) {
        if !keepingMe { me = AppStore.defaultMe() }
        let seed = SampleData.make(for: me)
        people = seed.people
        activities = seed.activities
        conversations = seed.conversations
        requests = seed.requests
        joinedIDs = []
        pendingIDs = []
        savedIDs = []
        pendingSaves = [:]
        skippedIDs = []
        swipeHistory = []
    }

    /// Wipes everything, including the profile, and returns to onboarding.
    func resetEverything() {
        auth.signOut()
        try? FileManager.default.removeItem(at: fileURL)
        hasOnboarded = false
        drafts = []
        notificationsEnabled = true
        radiusMiles = 50
        seed()
        selectedTab = .discover
        showProfile = false
        showCreate = false
        showPlanner = false
    }

    /// Keeps the profile but restores fresh demo activities and chats.
    func refreshDemoContent() {
        seed(keepingMe: true)
        save()
    }
}
