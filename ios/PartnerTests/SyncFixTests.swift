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
