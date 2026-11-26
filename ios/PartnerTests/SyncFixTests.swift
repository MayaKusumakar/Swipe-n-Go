import Foundation
import Testing
@testable import Partner

/// Decoding of the new server replies (the server's side is covered by backend/tests).
struct AccountSyncTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test func profileNameChosenOnAnotherDevice() throws {
        let json = #"{"id":"1","email":"ak@ucdavis.edu","name":"AK","picture_url":null,"display_name":"AK"}"#
        let user = try decoder.decode(EventServer.SignedInUser.self, from: Data(json.utf8))
        #expect(user.displayName == "AK")
    }

    @Test func olderServersWithoutDisplayNameStillDecode() throws {
        let json = #"{"id":"1","email":"ak@ucdavis.edu","name":"Anant"}"#
        let user = try decoder.decode(EventServer.SignedInUser.self, from: Data(json.utf8))
        #expect(user.displayName == nil)
        #expect(user.name == "Anant")
    }
}

struct FlyerPlaceTests {
    @Test func reviewCanCarryAPickedPlace() {
        let place = Place.presets[0]
        let fields = FlyerFields(title: "Run", date: .now, duration: nil,
                                 location: FlyerLocation(venue: place.name, address: place.address), place: place,
                                 details: "", cost: "", category: nil, cover: nil)
        #expect(fields.place == place)
    }
}

/// "Did you attend?" after a plan: which plans are asked about, and in what order.
struct AttendancePromptTests {
    private let me = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func plan(_ title: String, endedHoursAgo hours: Double, host: UUID = UUID()) -> Activity {
        Activity(id: UUID(), title: title, category: .social, hostID: host,
                 date: now.addingTimeInterval(-hours * 3600 - 3600), durationMinutes: 60,
                 placeName: "MU", address: "", latitude: 0, longitude: 0, capacity: 4, attendeeIDs: [],
                 details: "", tags: [], level: .anyone, requiresApproval: false, costNote: "Free")
    }

    private func queue(_ plans: [Activity], joined: [Activity], answers: [UUID: AttendanceAnswer] = [:]) -> [String] {
        AppStore.attendanceQueue(activities: plans, joinedIDs: Set(joined.map(\.id)), hostID: me,
                                 answers: answers, now: now).map(\.title)
    }

    @Test func endedPlansYouJoinedAreQueuedOldestFirst() {
        let recent = plan("Recent", endedHoursAgo: 1)
        let older = plan("Older", endedHoursAgo: 30)
        #expect(queue([recent, older], joined: [recent, older]) == ["Older", "Recent"])
    }

    @Test func onlyPlansYouJoinedThatAreOverAndRecent() {
        let notJoined = plan("Not joined", endedHoursAgo: 2)
        let upcoming = plan("Upcoming", endedHoursAgo: -5)
        let stillOn = plan("Still on", endedHoursAgo: -0.5)
        let longAgo = plan("Long ago", endedHoursAgo: 24 * 8)
        let hosted = plan("Mine", endedHoursAgo: 2, host: me)
        let joined = [upcoming, stillOn, longAgo, hosted]
        #expect(queue([notJoined] + joined, joined: joined).isEmpty)
    }

    @Test func eachPlanIsAskedOnceWhateverTheAnswer() {
        let a = plan("A", endedHoursAgo: 3), b = plan("B", endedHoursAgo: 2), c = plan("C", endedHoursAgo: 1)
        let answers: [UUID: AttendanceAnswer] = [
            a.id: AttendanceAnswer(response: .attended, feedback: "Fun", answeredAt: now),
            b.id: AttendanceAnswer(response: .dismissed, answeredAt: now),
        ]
        #expect(queue([a, b, c], joined: [a, b, c], answers: answers) == ["C"])
    }

    @Test func answersSurviveSavingAndOldSavesStillLoad() throws {
        let answer = AttendanceAnswer(response: .missed, feedback: nil, answeredAt: now, needsSync: true)
        let data = try JSONEncoder().encode([UUID(): answer])
        #expect(try JSONDecoder().decode([UUID: AttendanceAnswer].self, from: data).values.first == answer)
        // Saved before needsSync existed.
        let old = #"{"response":"attended","feedback":"Great","answeredAt":800000000}"#
        #expect(try JSONDecoder().decode(AttendanceAnswer.self, from: Data(old.utf8)).needsSync == nil)
    }
}

/// Guests hear about plans their host deleted (GET /api/events/cancelled).
struct CancelledPlanTests {
    @Test func cancellationsDecodeAndPointAtTheLocalPlan() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let json = #"{"event_id":"6f1c2b9e-1d2a-4c7b-9a51-0d6e2f3a4b5c","title":"Pickup Soccer","host_name":"Avery Lee","#
            + #""start_time":"2026-12-01T19:00:00Z","cancelled_at":"2026-11-23T18:00:00Z"}"#
        let c = try decoder.decode(EventServer.Cancellation.self, from: Data(json.utf8))
        #expect(c.title == "Pickup Soccer" && c.hostName == "Avery Lee")
        // The same id the plan got when it was synced, so the phone finds it.
        #expect(EventServer.localID(for: c.eventId) == UUID(uuidString: "6F1C2B9E-1D2A-4C7B-9A51-0D6E2F3A4B5C"))
    }
}

/// The host's Guest feedback screen: how the guest list is grouped.
struct HostFeedbackTests {
    private func guests(_ json: String) throws -> [EventServer.Attendee] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([EventServer.Attendee].self, from: Data(json.utf8))
    }

    @Test func guestsAreGroupedByAnswer() throws {
        // The shape GET /api/events/<id>/attendees answers with.
        let summary = EventServer.FeedbackSummary(try guests(#"""
        [{"id":"1","name":"Sam","status":"approved","attended":true,"feedback":"Loved it!","checked_in":true},
         {"id":"2","name":"ana","status":"approved","attended":true,"feedback":"Great host"},
         {"id":"3","name":"Lee","status":"approved","attended":true,"feedback":"   "},
         {"id":"4","name":"Kai","status":"approved","attended":false,"feedback":null},
         {"id":"5","name":"Zoe","status":"approved"},
         {"id":"6","name":"Pending Pat","status":"pending"}]
        """#))
        #expect(summary.comments.map(\.name) == ["ana", "Sam"])           // by name, any case
        #expect(summary.attendedQuietly.map(\.name) == ["Lee"])          // a blank comment isn't one
        #expect(summary.missed.map(\.name) == ["Kai"])
        #expect(summary.unanswered.map(\.name) == ["Zoe"])                // requests never approved aren't guests
        #expect((summary.guestCount, summary.answeredCount, summary.attendedCount) == (5, 4, 3))
        #expect(summary.comments.last?.checkedIn == true)
    }

    @Test func noGuestsMeansNothingToShow() {
        let summary = EventServer.FeedbackSummary([])
        #expect(summary.guestCount == 0 && summary.answeredCount == 0)
    }
}

/// Plan group chats on the server: decoding its replies, and merging them into the chat on this phone.
struct ServerChatTests {
    private let json = #"""
    {"messages": [
      {"id": "1764072000000-9f3a1c2e", "sender_id": "maya-account", "sender_name": "Maya", "text": "I'll bring snacks",
       "created_at": "2026-11-25T12:00:00.123+00:00", "client_id": null},
      {"id": "1764072005000-00aa11bb", "sender_id": "me-account", "sender_name": "Me", "text": "See you!",
       "created_at": "2026-11-25T12:00:05.000+00:00", "client_id": "MINE"}
    ], "has_more": false}
    """#

    private func page(clientID: UUID) throws -> EventServer.ChatPage {
        try EventServer.decoder.decode(EventServer.ChatPage.self,
                                       from: Data(json.replacingOccurrences(of: "MINE", with: clientID.uuidString).utf8))
    }

    @Test func decodesMessagesWithMilliseconds() throws {
        let page = try page(clientID: UUID())
        #expect(page.messages.count == 2 && !page.hasMore)
        #expect(page.messages[0].senderName == "Maya" && page.messages[0].clientId == nil)
        let expected = try Date("2026-11-25T12:00:00Z", strategy: .iso8601).addingTimeInterval(0.123)
        #expect(abs(page.messages[0].createdAt.timeIntervalSince(expected)) < 0.0005)   // milliseconds kept
    }

    @Test func ownMessagesAreMarkedDeliveredNotAddedTwice() throws {
        let me = UUID(), maya = UUID()
        let mine = Message(senderID: me, text: "See you!", date: .now, needsSync: true)
        var convo = Conversation(id: UUID(), activityID: UUID(), participantIDs: [me], messages: [mine])

        let added = convo.merge(try page(clientID: mine.id).messages) { $0.senderId == "maya-account" ? maya : me }

        #expect(added.map(\.text) == ["I'll bring snacks"] && added[0].senderID == maya)
        #expect(convo.messages.count == 2)
        let sent = try #require(convo.messages.first { $0.id == mine.id })
        #expect(sent.needsSync == nil && sent.serverID == "1764072005000-00aa11bb")
        #expect(convo.serverCursor == "1764072005000-00aa11bb")
    }

    @Test func mergingTheSameMessagesAgainChangesNothing() throws {
        var convo = Conversation(id: UUID(), activityID: UUID(), participantIDs: [], messages: [])
        let messages = try page(clientID: UUID()).messages
        _ = convo.merge(messages) { _ in UUID() }
        let again = convo.merge(messages) { _ in UUID() }
        #expect(again.isEmpty && convo.messages.count == 2)
    }

    @Test func cursorNeverMovesBack() throws {
        var convo = Conversation(id: UUID(), activityID: UUID(), participantIDs: [], messages: [])
        convo.serverCursor = "1764072009000-ffffffff"
        _ = convo.merge(try page(clientID: UUID()).messages) { _ in UUID() }
        #expect(convo.serverCursor == "1764072009000-ffffffff")
    }

    @Test func joinAndLeaveLinesFromTheServerAreSystemLines() throws {
        let json = #"{"id":"1795665533680-040335d7","sender_id":"maya-account","sender_name":"Maya","text":"Maya joined the plan","created_at":"2026-11-25T12:00:00.000+00:00","client_id":null,"kind":"system"}"#
        let line = try EventServer.decoder.decode(EventServer.ChatMessage.self, from: Data(json.utf8))
        var convo = Conversation(id: UUID(), activityID: UUID(), participantIDs: [], messages: [])
        let added = convo.merge([line]) { _ in UUID() }
        #expect(line.isSystem && added.count == 1 && added[0].kind == .system)
    }

    @Test func aLineThisPhoneAlreadyShowedIsNotShownTwice() throws {
        let created = try Date("2026-11-25T12:00:00Z", strategy: .iso8601)
        let local = Message(senderID: UUID(), text: "Maya joined the plan", date: created.addingTimeInterval(2), kind: .system)
        let oldLocal = Message(senderID: UUID(), text: "Sam left the plan", date: created.addingTimeInterval(-86400), kind: .system)
        var convo = Conversation(id: UUID(), activityID: UUID(), participantIDs: [], messages: [oldLocal, local])
        func line(_ id: String, _ text: String) -> EventServer.ChatMessage {
            EventServer.ChatMessage(id: id, senderId: "x", senderName: "X", text: text, createdAt: created, clientId: nil, kind: "system")
        }

        let added = convo.merge([line("1-a", "Maya joined the plan"), line("2-b", "Sam left the plan")]) { _ in UUID() }

        #expect(convo.messages.first { $0.id == local.id }?.serverID == "1-a")   // kept, now linked
        #expect(added.map(\.text) == ["Sam left the plan"])   // the day-old local line is a different event
    }

    @Test func olderServersWithoutKindAreText() throws {
        let page = try page(clientID: UUID())
        #expect(page.messages.allSatisfy { !$0.isSystem })
    }

    @Test func chatsSavedByOlderBuildsStillLoad() throws {
        let saved = #"{"id":"\#(UUID())","participantIDs":[],"messages":[{"id":"\#(UUID())","senderID":"\#(UUID())","text":"hi","date":0,"kind":"text"}],"unreadCount":0}"#
        let convo = try JSONDecoder().decode(Conversation.self, from: Data(saved.utf8))
        #expect(convo.serverCursor == nil && convo.messages[0].needsSync == nil)
    }
}

/// People from the server are told apart by account, so two Mayas get two avatars.
struct ServerPersonTests {
    @Test func sameNameDifferentAccountsAreDifferentPeople() {
        let a = Person.serverHost(named: "Maya", category: .social, accountID: "account-1")
        let b = Person.serverHost(named: "Maya", category: .social, accountID: "account-2")
        #expect(a.id != b.id)
    }

    @Test func oneAccountStaysOnePersonAfterARename() {
        let before = Person.serverHost(named: "Maya", category: .social, accountID: "account-1")
        let after = Person.serverHost(named: "Maya K.", category: .music, accountID: "account-1")
        #expect(before.id == after.id && before.hue == after.hue)
    }

    @Test func withoutAnAccountPeopleAreToldApartByName() {
        #expect(Person.serverHost(named: "Club", category: .social).id == Person.serverHost(named: "club", category: .arts).id)
    }
}
