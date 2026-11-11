import Foundation
import Testing
@testable import Partner

/// A fixed "now": Wednesday, Nov 11 2026, 12:00 PM in the device's time zone.
private let now: Date = {
    var parts = DateComponents()
    (parts.year, parts.month, parts.day, parts.hour) = (2026, 11, 11, 12)
    return Calendar.current.date(from: parts)!
}()

private func at(daysFromNow days: Int, hour: Int, minute: Int = 0) -> Date {
    let day = Calendar.current.date(byAdding: .day, value: days, to: now)!
    return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

private let me = UUID()
private let host = UUID()

private func activity(_ title: String, _ category: ActivityCategory, _ date: Date, level: ActivityLevel = .anyone,
                      cost: String = "Free", attendees: Int = 0, approval: Bool = false, capacity: Int = 8) -> Activity {
    Activity(id: UUID(), title: title, category: category, hostID: host, date: date, durationMinutes: 60,
             placeName: "Somewhere", address: "Davis, CA", latitude: Geo.home.latitude, longitude: Geo.home.longitude,
             capacity: capacity, attendeeIDs: (0..<attendees).map { _ in UUID() }, details: "", tags: [],
             level: level, requiresApproval: approval, costNote: cost)
}

private let context = PlannerContext(interests: [.run, .food], myID: me)

@Suite("Reading the request")
struct KeywordParserTests {
    @Test func tomorrowAfterFive() {
        let r = KeywordParser.parse("free tomorrow after 5", now: now)
        #expect(r.start == at(daysFromNow: 1, hour: 17))
        #expect(r.end == at(daysFromNow: 2, hour: 0))
    }

    @Test func freeMeansAvailableNotCheap() {
        #expect(KeywordParser.parse("I'm free tomorrow", now: now).cheap == false)
        #expect(KeywordParser.parse("tomorrow, something cheap", now: now).cheap)
        #expect(KeywordParser.parse("anything for free tonight", now: now).cheap)
    }

    @Test func activeMeansAllActiveCategories() {
        let r = KeywordParser.parse("want something active", now: now)
        #expect(Set(r.categories) == Set(ActivityCategory.active))
    }

    @Test func specificCategoriesAndFlags() {
        let r = KeywordParser.parse("this weekend I want to try hiking for the first time, I don't know anyone", now: now)
        #expect(r.categories == [.hike])
        #expect(r.beginnerFriendly)
        #expect(r.wantsCompany)
    }

    @Test func weekendCoversSaturdayAndSunday() {
        let r = KeywordParser.parse("this weekend", now: now)
        #expect(r.start == at(daysFromNow: 3, hour: 0))     // Saturday
        #expect(r.end == at(daysFromNow: 5, hour: 0))       // end of Sunday
    }

    @Test func weekdayName() {
        let r = KeywordParser.parse("friday morning", now: now)
        #expect(r.start == at(daysFromNow: 2, hour: 6))
        #expect(r.end == at(daysFromNow: 2, hour: 12))
    }

    @Test func noTimeMeansTheNextWeek() {
        let r = KeywordParser.parse("something fun", now: now)
        #expect(r.start == now)
        #expect(r.end == at(daysFromNow: 7, hour: 0))
    }

    @Test(arguments: [("after 5pm", 17), ("after 17:00", 17), ("after 9am", 9), ("after 6", 18)])
    func afterHour(text: String, hour: Int) {
        #expect(KeywordParser.parse("tomorrow " + text, now: now).start == at(daysFromNow: 1, hour: hour))
    }
}

@Suite("Picking events")
struct OnDevicePlannerTests {
    @Test func prefersWhatTheyAskedForInsideTheWindow() {
        let basketball = activity("Pickup basketball", .sports, at(daysFromNow: 1, hour: 18), attendees: 2)
        let tacos = activity("Taco crawl", .food, at(daysFromNow: 1, hour: 18, minute: 30))
        let morningRun = activity("Morning run", .run, at(daysFromNow: 1, hour: 7))
        let result = OnDevicePlanner.plan("free tomorrow after 5, want something active", activities: [tacos, morningRun, basketball],
                                          context: context, now: now)
        #expect(result.picks.map(\.activity.title) == ["Pickup basketball"])
        #expect(result.engine == .onDevice)
        #expect(result.note == nil)
        // Built with the app's own formatting: iOS puts a narrow no-break space before "PM".
        let five = at(daysFromNow: 1, hour: 17)
        #expect(result.understood == "\(five.friendlyDay) after \(five.friendlyTime) · something active")
    }

    @Test func widensTheSearchAndSaysSo() {
        let later = activity("Board games", .games, at(daysFromNow: 3, hour: 19))
        let result = OnDevicePlanner.plan("tonight", activities: [later], context: context, now: now)
        #expect(result.picks.map(\.activity.title) == ["Board games"])
        #expect(result.note != nil)
    }

    @Test func skipsPastFullAndOwnEvents() {
        let past = activity("Yesterday", .run, at(daysFromNow: -1, hour: 18))
        let full = activity("Full", .run, at(daysFromNow: 1, hour: 18), attendees: 1, capacity: 2)
        var mine = activity("Mine", .run, at(daysFromNow: 1, hour: 18))
        mine.hostID = me
        let result = OnDevicePlanner.plan("tomorrow evening run", activities: [past, full, mine], context: context, now: now)
        #expect(result.picks.isEmpty)
    }

    @Test func companyFavoursEventsWithPeopleGoing() {
        let empty = activity("Quiet run", .run, at(daysFromNow: 1, hour: 18))
        let busy = activity("Group run", .run, at(daysFromNow: 1, hour: 18), attendees: 4)
        let result = OnDevicePlanner.plan("tomorrow after 5, running, I don't know anyone", activities: [empty, busy],
                                          context: context, now: now)
        #expect(result.picks.first?.activity.title == "Group run")
        #expect(result.picks.first?.reason.contains("5 people already going") == true)
    }

    @Test func privateLocationReasonHasNoDistance() {
        let secret = activity("House party", .drinks, at(daysFromNow: 1, hour: 21))
        let hidden = PlannerContext(interests: [], myID: me, canSeeLocation: { _ in false })
        let result = OnDevicePlanner.plan("tomorrow night drinks", activities: [secret], context: hidden, now: now)
        #expect(result.picks.count == 1)
        #expect(result.picks.first?.reason.contains("away") == false)
    }

    @Test func cheapOnlyWhenAsked() {
        let pricey = activity("Concert", .concert, at(daysFromNow: 1, hour: 20), cost: "$40")
        #expect(OnDevicePlanner.isCheap(pricey) == false)
        #expect(OnDevicePlanner.isCheap(activity("Run", .run, now, cost: "Free w/ ARC")))
        #expect(OnDevicePlanner.isCheap(activity("Tacos", .food, now, cost: "~$8")))
    }
}

@Suite("Claude planner mapping")
struct ClaudePlannerTests {
    @Test func requestBodyDescribesCandidates() {
        let run = activity("Sunrise 5K", .run, at(daysFromNow: 1, hour: 7), level: .beginner, attendees: 2)
        let body = ClaudePlanner.makeBody("tomorrow morning run", candidates: [run], context: context, now: now)
        #expect(body.query == "tomorrow morning run")
        #expect(body.interests == ["run", "food"])
        #expect(body.events.first?.id == run.id.uuidString.lowercased())
        #expect(body.events.first?.level == "beginner")
        #expect(body.events.first?.attendeeCount == 3)          // host + 2
        #expect(body.now.hasPrefix("2026-11-11T12:00:00"))
    }

    @Test func mapsPicksAndIgnoresUnknownOrDuplicateIDs() {
        let run = activity("Sunrise 5K", .run, at(daysFromNow: 1, hour: 7))
        let tacos = activity("Taco crawl", .food, at(daysFromNow: 1, hour: 18))
        let response = ClaudePlanner.ResponseBody(
            understood: "Tomorrow · anything fun",
            picks: [
                .init(eventId: tacos.id.uuidString.uppercased(), reason: "Tacos at 6."),
                .init(eventId: "not-a-real-id", reason: "Invented."),
                .init(eventId: tacos.id.uuidString.lowercased(), reason: "Duplicate."),
                .init(eventId: run.id.uuidString.lowercased(), reason: "Easy morning run."),
            ],
            note: "  "
        )
        let result = ClaudePlanner.result(from: response, candidates: [run, tacos])
        #expect(result.picks.map(\.activity.title) == ["Taco crawl", "Sunrise 5K"])
        #expect(result.picks.first?.reason == "Tacos at 6.")
        #expect(result.engine == .claude)
        #expect(result.note == nil)
    }

    @Test func privateLocationsAreNotSent() {
        let secret = activity("House party", .drinks, at(daysFromNow: 1, hour: 21))
        let hidden = PlannerContext(interests: [], myID: me, canSeeLocation: { $0.id != secret.id })
        let body = ClaudePlanner.makeBody("tomorrow night", candidates: [secret], context: hidden, now: now)
        #expect(body.events.first?.locationName == ClaudePlanner.hiddenPlace)
        #expect(body.events.first?.distanceMiles == nil)
    }

    @Test func candidatesAreCappedAndSorted() {
        let events = (0..<80).map { activity("E\($0)", .run, at(daysFromNow: 1 + $0 % 6, hour: 8 + $0 % 10)) }
        let candidates = context.candidates(from: events, now: now)
        #expect(candidates.count == 80)
        #expect(candidates == candidates.sorted { $0.date < $1.date })
        #expect(Array(candidates.prefix(ClaudePlanner.maxCandidates)).count == 60)
    }
}
